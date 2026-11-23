"""足場の場所の検査（Python 用）。足場を使うスクリプトの冒頭で読み込み、C:\\tmp の下で動いていることを保証する。

確かめるもの: 今の作業フォルダ（os.getcwd()）と、環境変数 VERIF_ROOT があればその値。どちらも、..・シンボリックリンク・
ジャンクションを解決し（os.path.realpath）、/c/tmp・C:/tmp・C:\\tmp の書き方をそろえたうえで、
C:\\tmp そのものではなく、その下にあることを確かめる。外なら stderr に文を出し、終了コード 3 で終わる。

使い方（スクリプトの冒頭。<リポジトリ> は依頼文のリポジトリの絶対パス）:
    import os, runpy
    os.chdir(r"C:\\tmp\\<名前>")
    runpy.run_path(r"<リポジトリ>/.claude/skills/cross-review/scripts/guard_tmp.py", run_name="guard_tmp_run")
単独で: python -I -X utf8 guard_tmp.py [<パス> ...]   （パスを渡すと、今の作業フォルダの代わりにそれらを確かめる）
ほかのスクリプトから関数として: check_paths([...]) は外れたパスの一覧（空なら全部よい）を返す。
"""
import os
import re
import sys

ROOT = "c:/tmp"


def canon(path):
    """比較用の形にする。Git Bash の /c/... は C:/... に直してから realpath する。"""
    p = str(path).replace("\\", "/")
    m = re.match(r"^/([a-zA-Z])(/.*)?$", p)
    if m:
        p = f"{m.group(1)}:{m.group(2) or '/'}"
    real = os.path.realpath(p)
    return real.replace("\\", "/").rstrip("/").lower()


def is_under_tmp(path):
    c = canon(path)
    return c.startswith(ROOT + "/") and c != ROOT


def check_paths(paths):
    return [p for p in paths if p and not is_under_tmp(p)]


def default_paths():
    paths = [os.getcwd()]
    if os.environ.get("VERIF_ROOT"):
        paths.append(os.environ["VERIF_ROOT"])
    return paths


def fail(bad):
    lines = "\n".join(f"  {p} → {canon(p)}" for p in bad)
    sys.stderr.write(
        "[guard_tmp] 足場（C:\\tmp\\<名前>）の外で動こうとしたので止めた:\n"
        f"{lines}\n"
        "直し方: 足場は `python -I -X utf8 .claude/skills/cross-review/scripts/scaffold.py make <名前>` で作り、"
        "スクリプトは冒頭でそこへ移ってから（cd・os.chdir）guard_tmp を読み込む。C:\\tmp そのもの・リポジトリの中では動かさない\n")


def check_or_exit(paths=None):
    bad = check_paths(paths if paths else default_paths())
    if bad:
        fail(bad)
        sys.exit(3)


if __name__ == "__main__":
    check_or_exit(sys.argv[1:] or None)
    print("[guard_tmp] よい: " + ", ".join(canon(p) for p in (sys.argv[1:] or default_paths())))
elif __name__ == "guard_tmp_run":
    check_or_exit()
