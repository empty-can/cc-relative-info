"""同件調査の (a) 文字列・正規表現で言い切れる型の拾い出し（Haiku を使わない）。

使い方: python -I -X utf8 grep_type.py <型の ID> <正規表現> <出力.tsv> <文書> [<文書> ...]
  正規表現は Python の re（行ごとに当てる）。出力は拾い出しの決まった書式（merge_findings.py と同じ）:
    ファイル<TAB>行<TAB>引用<TAB>型の ID<TAB>印
  印は空（機械の拾い出しには迷いが無い）。引用は当たった行の全体（前後の空白を除き、200 字まで）
  当たりが 0 件でも書式どおりのヘッダだけのファイルを書く（0 件であることを記録する）。正規表現が誤りなら終了コード 2、
  文書が読めない（無い・UTF-8 でない）なら書かずに終了コード 3
"""
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
HEADER = "ファイル\t行\t引用\t型の ID\t印"


def main(argv):
    if len(argv) < 4:
        print(__doc__, file=sys.stderr)
        return 2
    tid, pattern, out, *docs = argv
    try:
        rx = re.compile(pattern)
    except re.error as e:
        print(f"正規表現が誤り: {e}", file=sys.stderr)
        return 2
    rows = [HEADER]
    for d in docs:
        try:
            text = Path(d).read_bytes().decode("utf-8")
        except (OSError, UnicodeDecodeError) as e:
            print(f"文書が読めない（0 件にせず止める）: {d}: {e}", file=sys.stderr)
            return 3
        for no, line in enumerate(text.split("\n"), 1):
            if rx.search(line):
                q = line.strip().replace("\t", " ")[:200]
                rows.append("\t".join([d.replace("\\", "/"), str(no), q, tid, ""]))
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    Path(out).write_bytes(("\n".join(rows) + "\n").encode("utf-8"))
    print(f"型 {tid}: {len(rows) - 1} 件 → {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
