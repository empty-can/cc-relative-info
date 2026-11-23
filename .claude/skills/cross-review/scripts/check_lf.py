"""渡されたファイルに CR（\r）が入っていないかを数える。

使い方: python -I -X utf8 check_lf.py <ファイル> [<ファイル> ...]
終了コード: 0 = どのファイルにも CR が無い / 1 = CR があるファイルがある / 2 = 引数が無い、または読めないファイルがある
hook_post_write.py は count_cr() を使い回す。
"""
import sys


def count_cr(path):
    """CR の数を返す。読めないときは OSError をそのまま投げる。"""
    with open(path, "rb") as f:
        return f.read().count(b"\r")


def main(paths):
    if not paths:
        print("使い方: python -I -X utf8 check_lf.py <ファイル> [<ファイル> ...]", file=sys.stderr)
        return 2
    status = 0
    for path in paths:
        try:
            count = count_cr(path)
        except OSError as e:
            print(f"読めない\t{path}\t{e}", file=sys.stderr)
            status = 2
            continue
        if count:
            print(f"CR あり\t{count}\t{path}")
            if status == 0:
                status = 1
        else:
            print(f"LF のみ\t0\t{path}")
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
