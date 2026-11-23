"""2 つのコミットの差の大きさを数える（読み取りの git だけ）。確認の回で収束しなかったとき、台帳の記録に差の大きさを書くのに使う。

使い方: python -I -X utf8 diff_size.py <リポジトリ> <前の対象> <今の対象> [<パス> ...]
出力: 1 行目に「差分: n ファイル・+a 行／-d 行（<前>..<今>）」。続けてファイルごとの +a -d。git が失敗したら終了コード 2。
"""
import subprocess
import sys

sys.dont_write_bytecode = True


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    repo, a, b, *paths = argv
    cmd = ["git", "-C", repo, "-c", "core.quotepath=false", "diff", "--numstat", a, b, "--"] + paths
    r = subprocess.run(cmd, capture_output=True)
    if r.returncode != 0:
        sys.stderr.write(r.stderr.decode("utf-8", "replace"))
        return 2
    rows = []
    for line in r.stdout.decode("utf-8", "replace").splitlines():
        add, dele, path = line.split("\t", 2)
        rows.append((0 if add == "-" else int(add), 0 if dele == "-" else int(dele), path))
    print(f"差分: {len(rows)} ファイル・+{sum(x[0] for x in rows)} 行／-{sum(x[1] for x in rows)} 行（{a}..{b}）")
    for add, dele, path in rows:
        print(f"  +{add}\t-{dele}\t{path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
