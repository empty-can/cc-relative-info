"""足場を作る・消す・掃除するための固定のスクリプト。必ず C:\\tmp の下だけで動く。

使い方:
  python -I -X utf8 .claude/skills/cross-review/scripts/scaffold.py make <名前>
      C:\\tmp\\<名前> を作る。名前は英数字で始まり、英数字・. ・_ ・- だけ（区切り文字と .. は不可）
  python -I -X utf8 .claude/skills/cross-review/scripts/scaffold.py remove <名前 か パス>
      C:\\tmp の下のファイル・フォルダを消す。名前（C:\\tmp\\<名前>）でも、下の階層のパス（C:\\tmp\\<名前>\\a\\b、/c/tmp/... も可）でもよい。
      C:\\tmp そのものは受けない。担当は自分の足場だけを消す
  python -I -X utf8 .claude/skills/cross-review/scripts/scaffold.py clean
      C:\\tmp の中身を全部消す（C:\\tmp のフォルダは残す）。主担当（メインのセッション）だけが使う。
      クロスレビューの担当からの clean は hook_pre_bash.py が止める（並行で動くほかの担当の足場を消さないため）

消し方: C:\\tmp の下のジャンクション・シンボリックリンクは、リンクだけを外し、先をたどらない。読み取り専用のファイルも消す。
場所の確かめ: パスを正規化し（\\ と /、/c/tmp・C:/tmp・C:\\tmp の書き方、..、親のリンク）、guard_tmp.py の検査で C:\\tmp の下であることを確かめる。
テスト用の口: 環境変数 CROSS_REVIEW_SCAFFOLD_ROOT で C:\\tmp の代わりの根を渡せる。ただし、その根も本物の C:\\tmp の下でなければならない
（外を渡すと終了コード 2）。
Python 3.12 以上が要る（ジャンクションの判定 os.path.isjunction のため。未満なら終了コード 2）。根そのものがリンクなら動かない。
終了コード: 0 = できた（make で既にある・remove で無いときも 0。その旨を出す）/ 2 = 引数・場所が誤り / 1 = 消すのに失敗
"""
import importlib.util
import os
import re
import stat
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # .claude の下に __pycache__ を作らない

_spec = importlib.util.spec_from_file_location("guard_tmp", Path(__file__).resolve().parent / "guard_tmp.py")
guard = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(guard)

NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def err(msg, code=2):
    sys.stderr.write(msg + "\n")
    return code


def root_dir():
    """根（既定は C:/tmp）。差し替えの値は、本物の C:/tmp の下でなければ None。"""
    alt = os.environ.get("CROSS_REVIEW_SCAFFOLD_ROOT")
    if alt:
        return guard.canon(alt) if guard.is_under_tmp(alt) else None
    return guard.ROOT


def is_link(path):
    return os.path.islink(path) or (hasattr(os.path, "isjunction") and os.path.isjunction(path))


def resolve_target(arg, root):
    """remove の対象を、根の下の正規化したパスにする。誤りなら None。
    最後の要素はリンクのままにする（リンクだけを外すため）。親は realpath で解決する。"""
    p = arg.replace("\\", "/")
    if NAME_RE.match(p) and ".." not in p:
        p = f"{root}/{p}"
    m = re.match(r"^/([a-zA-Z])(/.*)$", p)
    if m:
        p = f"{m.group(1)}:{m.group(2)}"
    p = os.path.abspath(p)
    parent, last = os.path.split(p)
    if last in ("", ".", ".."):
        return None
    real_parent = guard.canon(parent)
    if not (real_parent == root or real_parent.startswith(root + "/")):
        return None
    return os.path.join(os.path.realpath(parent), last)


def _make_writable(path):
    try:
        os.chmod(path, stat.S_IWRITE | stat.S_IREAD)
    except OSError:
        pass


def remove_tree(path):
    """リンクをたどらずに消す。"""
    if is_link(path):
        if os.path.isdir(path):
            os.rmdir(path)          # ジャンクション・ディレクトリへのリンクは、リンクだけを外す
        else:
            os.unlink(path)
        return
    if os.path.isdir(path):
        with os.scandir(path) as it:
            entries = list(it)
        for e in entries:
            remove_tree(e.path)
        _make_writable(path)
        os.rmdir(path)
        return
    _make_writable(path)
    os.unlink(path)


def cmd_make(name, root):
    if not NAME_RE.match(name) or ".." in name:
        return err(f"名前が誤り（英数字・. ・_ ・- だけ。区切り文字と .. は不可）: {name!r}")
    t = os.path.join(root, name)
    if guard.check_paths([t]) or not guard.canon(t).startswith(root + "/"):
        guard.fail([t])
        return 2
    os.makedirs(root, exist_ok=True)
    if os.path.exists(t):
        print(f"既にある: {t}")
        return 0
    os.mkdir(t)
    print(f"作った: {t}")
    return 0


def cmd_remove(arg, root):
    t = resolve_target(arg, root)
    if t is None:
        return err(f"消せない場所（{root} そのもの・その外・.. を含む）: {arg!r}")
    if not os.path.lexists(t):
        print(f"無い（消すものが無い）: {t}")
        return 0
    try:
        remove_tree(t)
    except OSError as e:
        return err(f"消せなかった: {t}: {e}", 1)
    print(f"消した: {t}")
    return 0


def cmd_clean(root):
    if not os.path.isdir(root):
        print(f"無い: {root}")
        return 0
    failed = 0
    with os.scandir(root) as it:
        entries = list(it)
    for e in entries:
        try:
            remove_tree(e.path)
        except OSError as ex:
            failed += 1
            sys.stderr.write(f"消せなかった: {e.path}: {ex}\n")
    print(f"掃除した: {root} の中の {len(entries) - failed} 件（{root} は残した）")
    return 1 if failed else 0


def main(argv):
    if sys.version_info < (3, 12):
        return err("Python 3.12 以上が要る（ジャンクションをリンクと判定できないと、先の中身を消すため）")
    root = root_dir()
    if root is None:
        return err("CROSS_REVIEW_SCAFFOLD_ROOT が C:\\tmp の下ではない")
    if os.path.lexists(root) and (is_link(root) or os.path.realpath(root).replace("\\", "/").rstrip("/").lower() != root):
        return err(f"根 {root} がリンクか、解いた先が根と違う（先の中身を消さないため動かない）")
    if argv[:1] == ["clean"] and len(argv) == 1:
        return cmd_clean(root)
    if len(argv) == 2 and argv[0] == "make":
        return cmd_make(argv[1], root)
    if len(argv) == 2 and argv[0] == "remove":
        return cmd_remove(argv[1], root)
    return err("使い方: scaffold.py make <名前> | scaffold.py remove <名前 か パス> | scaffold.py clean（主担当だけ）")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
