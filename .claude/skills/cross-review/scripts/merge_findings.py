"""同件調査の (b) 意味で判定する型の、2 体の Haiku の担当の拾い出しを突き合わせる。

使い方: python -I -X utf8 merge_findings.py <A.tsv> <B.tsv> <出力.md> [--line-window N] [--min-ratio R]
入力の書式（grep_type.py・cross-review-clerk の出力と同じ。1 行目はヘッダ）:
    ファイル<TAB>行<TAB>引用<TAB>型の ID<TAB>印
照合の決まり（同じ箇所とみなす条件。全部を満たすもの）:
  1. ファイルが同じ（\\ と / をそろえ、大文字小文字を区別しない）
  2. 型の ID が同じ
  3. 行の差が N 行以内（既定 3。担当が見出しや前後の行を数え違えるずれを吸収する）
  4. 引用を正規化して（NFKC、Markdown の ` * _ の除去、空白の詰め、句読点「。、」の除去）、片方がもう片方を含むか、
     似ている度合い（difflib の ratio）が R 以上（既定 0.6）
  1 つの項目は、相手の 1 つの項目とだけ組にする（行の差が小さく、ratio が高いものから先に組む）
出力: 項目ごとに「両方／A だけ／B だけ」の印と、迷いの印（どちらかに付いていれば）を付けた表。先頭に件数（両方・A だけ・B だけ・
食い違いの割合 = 片方だけ ÷ 全項目）。印が空で末尾のタブが落ちた 4 列の行は「印なし」と読む。書式が合わない入力
（ヘッダが違う・列の数が 4 か 5 でない・行が数でない）は終了コード 3。
"""
import difflib
import re
import sys
import unicodedata
from pathlib import Path

sys.dont_write_bytecode = True
HEADER = ["ファイル", "行", "引用", "型の ID", "印"]


class FormatError(Exception):
    pass


def load(path):
    text = Path(path).read_bytes().decode("utf-8")
    lines = [l for l in text.split("\n") if l.strip()]
    if not lines or lines[0].split("\t") != HEADER:
        raise FormatError(f"{path}: 1 行目が「{chr(9).join(HEADER)}」でない")
    items = []
    for no, l in enumerate(lines[1:], 2):
        cols = l.split("\t")
        if len(cols) == 4:
            cols.append("")   # 印が空で末尾のタブが落ちた行は「印なし」と読む
        if len(cols) != 5:
            raise FormatError(f"{path} の {no} 行目: 列が 5 つでない（{len(cols)} 個）")
        if not re.fullmatch(r"\d+", cols[1].strip()):
            raise FormatError(f"{path} の {no} 行目: 行が数でない: {cols[1]!r}")
        items.append({"file": cols[0].strip(), "line": int(cols[1]), "quote": cols[2].strip(),
                      "type": cols[3].strip(), "mark": cols[4].strip()})
    return items


def norm_file(p):
    return p.replace("\\", "/").lower()


def norm_quote(q):
    q = unicodedata.normalize("NFKC", q)
    q = re.sub(r"[`*_]", "", q)
    q = re.sub(r"[。、,.]", "", q)
    q = re.sub(r"\s+", "", q)
    return q


def similar(a, b, min_ratio):
    na, nb = norm_quote(a), norm_quote(b)
    if not na or not nb:
        return 0.0
    if na in nb or nb in na:
        return 1.0
    r = difflib.SequenceMatcher(None, na, nb).ratio()
    return r if r >= min_ratio else 0.0


def merge(a, b, window, min_ratio):
    cands = []
    for i, x in enumerate(a):
        for j, y in enumerate(b):
            if norm_file(x["file"]) != norm_file(y["file"]) or x["type"] != y["type"]:
                continue
            d = abs(x["line"] - y["line"])
            if d > window:
                continue
            s = similar(x["quote"], y["quote"], min_ratio)
            if s:
                cands.append((d, -s, i, j))
    cands.sort()
    used_a, used_b, pairs = set(), set(), []
    for d, s, i, j in cands:
        if i in used_a or j in used_b:
            continue
        used_a.add(i)
        used_b.add(j)
        pairs.append((i, j))
    rows = [("両方", a[i], b[j]) for i, j in pairs]
    rows += [("A だけ", a[i], None) for i in range(len(a)) if i not in used_a]
    rows += [("B だけ", None, b[j]) for j in range(len(b)) if j not in used_b]
    rows.sort(key=lambda r: (norm_file((r[1] or r[2])["file"]), (r[1] or r[2])["line"]))
    return rows


def main(argv):
    window, min_ratio = 3, 0.6
    for opt, conv in (("--line-window", int), ("--min-ratio", float)):
        if opt in argv:
            i = argv.index(opt)
            try:
                conv(argv[i + 1])
            except (IndexError, ValueError):
                print(f"{opt} の値が無いか、{'整数' if conv is int else '数'}でない\n" + __doc__, file=sys.stderr)
                return 2
    if "--line-window" in argv:
        i = argv.index("--line-window")
        window = int(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    if "--min-ratio" in argv:
        i = argv.index("--min-ratio")
        min_ratio = float(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        a, b = load(argv[0]), load(argv[1])
    except FormatError as e:
        print(f"書式が合わない: {e}", file=sys.stderr)
        return 3
    rows = merge(a, b, window, min_ratio)
    both = sum(1 for r in rows if r[0] == "両方")
    only_a = sum(1 for r in rows if r[0] == "A だけ")
    only_b = sum(1 for r in rows if r[0] == "B だけ")
    total = len(rows)
    ratio = (only_a + only_b) / total if total else 0.0
    out = [f"# 拾い出しの突き合わせ（A: `{argv[0]}`／B: `{argv[1]}`）", "",
           f"- 件数: 両方 {both}／A だけ {only_a}／B だけ {only_b}／全 {total}",
           f"- 食い違いの割合（片方だけ ÷ 全項目）: {ratio:.0%}",
           f"- 照合の決まり: 同じファイル・同じ型・行の差 {window} 行以内・引用の正規化後に包含か ratio {min_ratio} 以上",
           "- 片方だけの項目は、反映の担当が該当の文を読んで確かめる。迷いの印のある項目も同じ", "",
           "| # | 印 | ファイル | 行（A／B） | 型 | 引用 | 迷い |", "|---|---|---|---|---|---|---|"]
    for n, (mark, x, y) in enumerate(rows, 1):
        it = x or y
        lines = f"{x['line'] if x else '-'}／{y['line'] if y else '-'}"
        doubt = "・".join(m for m in ((x or {}).get("mark", ""), (y or {}).get("mark", "")) if m)
        quote = it["quote"].replace("|", "／")[:120]
        out.append(f"| {n} | {mark} | {it['file']} | {lines} | {it['type']} | {quote} | {doubt} |")
    Path(argv[2]).write_bytes(("\n".join(out) + "\n").encode("utf-8"))
    print(f"両方 {both}／A だけ {only_a}／B だけ {only_b}／食い違いの割合 {ratio:.0%} → {argv[2]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
