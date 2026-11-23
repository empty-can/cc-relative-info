"""クロスレビューの台帳（templates/進行/台帳.md の形）を作り、書き足す（バイトモード。LF）。

使い方: python -I -X utf8 ledger.py <動作> <台帳> ...
  init <台帳> <項目>=<値> ...      テンプレートから作る。項目: 作業フォルダ・リポジトリ・対象の文書・報告書の置き場所・
                                   公式ドキュメントの断面・判断基準・扱う状態の範囲・文書の決まり（無い項目は「無し」）
  stage <台帳> <段階> <次にすること>
  version <台帳> <観点> <版> <対象のコミット> <残る C・I>
  agent <台帳> <担当名> <subagent_type> <エージェント ID> <依頼文> <状態>   （担当名が既にあれば、その行を書き換える）
  decide <台帳> <事項> <決定> <決めた人・日付> <決まるまでの書き方>
  carry <台帳> <元の ID・項目> <中身> <変わらない|変わる（判断待ちへ）>
  log <台帳> <段階> <出来事>        （日時は自動）
  get <台帳> <項目>                 固有の値を 1 つ出す（依頼文の埋め込みが使う）
台帳の見出し・表が見つからないときは終了コード 3。
"""
import datetime
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
TPL = Path(__file__).resolve().parent.parent / "templates" / "進行" / "台帳.md"
KEYS = ["作業フォルダ", "リポジトリ", "対象の文書", "報告書の置き場所", "公式ドキュメントの断面", "判断基準", "扱う状態の範囲", "文書の決まり"]
SECTIONS = {"version": "観点ごとの版", "agent": "担当", "decide": "決定（作業指示者の裁定と、主担当の決定）",
            "carry": "持ち越し（仕上げの回へ回したもの）", "log": "記録"}


class FormatError(Exception):
    pass


def read(p):
    data = Path(p).read_bytes()
    if b"\r" in data:
        raise FormatError(f"CR が入っている: {p}")
    return data.decode("utf-8")


def write(p, text):
    assert "\r" not in text
    Path(p).write_bytes(text.encode("utf-8"))


def cell(v):
    return str(v).replace("|", "／").replace("\n", " ")


def table_span(lines, heading):
    """見出し「## <heading>」の下の表の、(ヘッダ行, 最後の行) の位置。"""
    try:
        h = lines.index(f"## {heading}")
    except ValueError:
        raise FormatError(f"見出し「## {heading}」が無い")
    i = h + 1
    while i < len(lines) and not lines[i].startswith("|"):
        if lines[i].startswith("## "):
            raise FormatError(f"「## {heading}」の下に表が無い")
        i += 1
    if i >= len(lines):
        raise FormatError(f"「## {heading}」の下に表が無い")
    j = i
    while j + 1 < len(lines) and lines[j + 1].startswith("|"):
        j += 1
    return i, j


def append_row(path, section, cells, key_col=None):
    lines = read(path).split("\n")
    head, last = table_span(lines, SECTIONS[section])
    rows = list(range(head + 2, last + 1))
    for r in [r for r in rows if "{{" in lines[r]]:   # テンプレートの例の行は、最初に書くときに外す
        lines[r] = None
    new = "| " + " | ".join(cell(c) for c in cells) + " |"
    replaced = False
    if key_col is not None:
        for r in rows:
            if lines[r] is None:
                continue
            cols = [c.strip() for c in lines[r].strip("|").split("|")]
            if cols[key_col] == cell(cells[key_col]):
                lines[r] = new
                replaced = True
    if not replaced:
        lines.insert(last + 1, new)
    write(path, "\n".join(l for l in lines if l is not None))
    print(("書き換えた: " if replaced else "足した: ") + new)


def cmd_init(path, *pairs):
    if Path(path).exists():
        raise FormatError(f"既にある（作り直さない）: {path}")
    if any("=" not in p for p in pairs):
        print("引数が「項目=値」の形でない: " + "、".join(p for p in pairs if "=" not in p) + "\n" + __doc__, file=sys.stderr)
        return 2
    vals = dict(p.split("=", 1) for p in pairs)
    bad = set(vals) - set(KEYS)
    if bad:
        raise FormatError(f"知らない項目: {sorted(bad)}（{'・'.join(KEYS)}）")
    text = read(TPL)
    for k in KEYS:
        pat = re.compile(r"^\| " + re.escape(k) + r" \| [^\n]*\|$", re.M)
        if not pat.search(text):
            raise FormatError(f"テンプレートに「| {k} |」の行が無い")
        row = f"| {k} | {cell(vals.get(k, '無し'))} |"
        text = pat.sub(lambda m: row, text, count=1)   # 値の \ を置換の記号と読ませない
    name = Path(vals.get("対象の文書", "対象の文書")).name
    text = text.replace("（{{対象の文書の名前}}）", f"（{name}）", 1)
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    write(path, text)
    cmd_stage(path, "0 準備", "権限の事前列挙と hook の設定")
    return 0


def cmd_stage(path, stage, nxt):
    text = read(path)
    a = re.compile(r"^- 段階: [^\n]*$", re.M)
    b = re.compile(r"^- 次にすること: [^\n]*$", re.M)
    if not a.search(text) or not b.search(text):
        raise FormatError("「## 今の段階」の「- 段階:」「- 次にすること:」の行が無い")
    text = a.sub(lambda m: f"- 段階: {stage}", text, count=1)
    text = b.sub(lambda m: f"- 次にすること: {nxt}", text, count=1)
    write(path, text)
    print(f"段階: {stage}／次にすること: {nxt}")
    return 0


def cmd_get(path, key):
    m = re.search(r"^\| " + re.escape(key) + r" \| ([^\n]*) \|$", read(path), re.M)
    if not m:
        raise FormatError(f"固有の値に「{key}」の行が無い")
    print(m.group(1).strip("`"))
    return 0


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    op, path, *rest = argv
    try:
        if op == "init":
            return cmd_init(path, *rest)
        if op == "stage" and len(rest) == 2:
            return cmd_stage(path, *rest)
        if op == "get" and len(rest) == 1:
            return cmd_get(path, *rest)
        if op == "version" and len(rest) == 4:
            append_row(path, "version", rest, key_col=0)
            return 0
        if op == "agent" and len(rest) == 5:
            append_row(path, "agent", rest, key_col=0)
            return 0
        if op == "decide" and len(rest) == 4:
            lines = read(path).split("\n")
            head, last = table_span(lines, SECTIONS["decide"])
            n = sum(1 for l in lines[head + 2:last + 1] if "{{" not in l) + 1
            append_row(path, "decide", [n] + rest)
            return 0
        if op == "carry" and len(rest) == 3:
            lines = read(path).split("\n")
            head, last = table_span(lines, SECTIONS["carry"])
            n = sum(1 for l in lines[head + 2:last + 1] if "{{" not in l) + 1
            append_row(path, "carry", [n] + rest)
            return 0
        if op == "log" and len(rest) == 2:
            append_row(path, "log", [datetime.datetime.now().strftime("%Y-%m-%d %H:%M")] + rest)
            return 0
    except FormatError as e:
        print(f"書式が合わない: {e}", file=sys.stderr)
        return 3
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
