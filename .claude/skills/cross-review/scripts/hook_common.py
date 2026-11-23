"""クロスレビューの hook の共通の部品（標準ライブラリだけ）。

hook のスクリプトは `python -I -X utf8 <スクリプト>` で動く。-I のときスクリプトのフォルダは sys.path に入らないので、
各 hook はこのファイルを importlib でパスから読み込む。

hook は「担当の癖を直す柵」であって、安全の境界ではない（README の (8)）。

設定ファイル: リポジトリの中の未追跡の固定のパス `.claude/workspace/cross-review-hook.json`（主担当が段階 0 で
templates/進行/hook設定.json から作る）。リポジトリのルートは、hook に渡る環境変数 CLAUDE_PROJECT_DIR、無ければこの
スクリプトの場所（.claude/skills/cross-review/scripts/）から求める。単体の確かめのためだけに、環境変数
CROSS_REVIEW_HOOK_CONFIG で差し替えられる（担当のコマンドからの差し替えは hook_pre_bash が止める）。
設定が無い・壊れている・雛型のまま・型が違うときは、クロスレビューの担当には「止める」（黙って緩めない）。
ログは設定の work_folder の 30_tmp/cross-review-hook.log。
"""
import datetime
import fnmatch
import json
import os
import re
import sys
from pathlib import Path

CONFIG_REL = ".claude/workspace/cross-review-hook.json"
SCRIPTS_DIR = Path(__file__).resolve().parent


def project_root():
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    if env:
        return env
    return str(SCRIPTS_DIR.parents[3])


def config_path():
    return os.environ.get("CROSS_REVIEW_HOOK_CONFIG") or os.path.join(project_root(), CONFIG_REL)


def norm(path):
    """比較用の形: \\ を / にし、Git Bash の /c/ 形を c:/ にそろえ、.. を解き、小文字にする。"""
    if not path:
        return ""
    p = str(path).replace("\\", "/")
    m = re.match(r"^/([a-zA-Z])(/.*)?$", p)
    if m:
        p = f"{m.group(1)}:{m.group(2) or '/'}"
    p = os.path.normpath(p).replace("\\", "/")
    return p.lower().rstrip("/")


def under(path, root):
    """path が root の下（root と等しいときも真）。両方とも .. を解いてから比べる。"""
    p, r = norm(path), norm(root)
    return bool(r) and (p == r or p.startswith(r + "/"))


def strictly_under(path, root):
    p, r = norm(path), norm(root)
    return bool(r) and p.startswith(r + "/")


def match_any(path, patterns):
    p = norm(path)
    for pat in patterns:
        q = norm(pat)
        base = q[:-3] if q.endswith("/**") else q
        if strictly_under(p, base) or fnmatch.fnmatchcase(p, q):
            return True
    return False


def is_cross_review_agent(data):
    """保険: hook はクロスレビューの担当の定義にだけ書くが、agent_type が cross-review- で始まらない入力
    （無いときも）は何もせず通す。メインのセッションや別の担当では効かない。"""
    return isinstance(data, dict) and str(data.get("agent_type") or "").startswith("cross-review-")


def read_input():
    raw = sys.stdin.buffer.read().decode("utf-8", errors="replace")
    try:
        data = json.loads(raw) if raw.strip() else {}
    except json.JSONDecodeError:
        data = {}
    return data if isinstance(data, dict) else {}


def load_config():
    """(設定, 誤りの文) を返す。誤りの文が空でなければ、担当の操作は止める。"""
    path = config_path()
    fix = f"主担当が段階 0 で templates/進行/hook設定.json を埋めて {CONFIG_REL} に置く（担当は書き換えない）"
    try:
        raw = Path(path).read_bytes().decode("utf-8")
    except OSError:
        return {}, f"hook の設定 {path} が無い。{fix}"
    except UnicodeDecodeError:
        # PowerShell 5.1 の Out-File・> の既定は UTF-16。hook の側の誤りではなく設定の誤りとして返す
        return {}, f"hook の設定 {path} が UTF-8 でない（UTF-16 など。PowerShell 5.1 の Out-File の既定）。{fix}。UTF-8（BOM なし）で書く"
    if "{{" in raw:
        return {}, f"hook の設定 {path} が雛型のまま（{{{{…}}}} が残っている）。{fix}"
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        return {}, f"hook の設定 {path} の JSON が壊れている（{e}）。{fix}"
    if not isinstance(data, dict) or not isinstance(data.get("work_folder"), str) or not isinstance(data.get("repo"), str):
        return {}, f"hook の設定 {path} に work_folder・repo（文字列）が無い。{fix}"
    allow = data.get("allow")
    if not isinstance(allow, dict) or not all(isinstance(v, list) and all(isinstance(x, str) for x in v) for v in allow.values()):
        return {}, f"hook の設定 {path} の allow が「担当の種類 → パスの配列」の形でない。{fix}"
    return data, ""


def log_path(config):
    work = config.get("work_folder") if config else None
    return os.path.join(work, "30_tmp", "cross-review-hook.log") if work else ""


def protected_paths(config):
    """担当が書き換えてはいけないファイル: hook の設定とログ。"""
    paths = [config_path(), os.path.join(project_root(), CONFIG_REL)]
    lp = log_path(config)
    if lp:
        paths.append(lp)
    return paths


# 理由の印（ログの 7 列目）。上から順に、理由の文に語があれば最初のものを採る。check_return.py と人が担当の報告と照らす材料
MARKS = [("設定", ("hook の設定 ", "allow に", "の行が無い")), ("保護", ("hook の設定・ログ", "テスト用の口")),
         ("記号", ("記号",)), ("背景", ("背景",)), ("前置き", ("前置き",)), ("clean", ("scaffold.py clean",)),
         ("guard", ("guard_tmp",)), ("リポジトリ", ("リポジトリの絶対パス", "リポジトリへ移って", "足場の外を指しうる")),
         ("書き込み系の git", ("書き込み系",)), ("ファイル", ("読めない",)), ("PowerShell", ("PowerShell のスクリプト",)),
         ("書き込み先", ("書いてよい場所の外", "一時の場所", "パスが無い")), ("CR", ("CR が",)), ("形", ("形",)), ("入力", ("",))]


def reason_mark(reason):
    return next(m for m, words in MARKS if any(w in reason for w in words))


def log(config, data, hook, verdict, reason, detail=""):
    """止めた記録・知らせた記録を 1 行ずつ足す。書けなくても hook の判定は変えない。
    列: 日時・agent_type・agent_id・tool_name・hook・判定（deny／notice）・理由の印・理由・コマンドかパス（300 字まで）。"""
    path = log_path(config)
    if not path:
        return
    line = "\t".join([
        datetime.datetime.now().isoformat(timespec="seconds"),
        str(data.get("agent_type", "main")),
        str(data.get("agent_id", "-")),
        str(data.get("tool_name", "-")),
        hook,
        verdict,
        reason_mark(reason),
        reason.replace("\t", " ").replace("\n", " "),
        str(detail).replace("\t", " ").replace("\n", "⏎")[:300],
    ])
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "ab") as f:
            f.write((line + "\n").encode("utf-8"))
    except OSError:
        pass


def deny(config, data, hook, reason, fix, detail=""):
    """PreToolUse を止める。stderr の文が Claude に届く（exit 2）。"""
    log(config, data, hook, "deny", reason, detail)
    where = log_path(config)
    msg = f"[cross-review hook] 止めた: {reason}\n直し方: {fix}" + (f"\n（記録: {where}）" if where else "")
    sys.stderr.buffer.write(msg.encode("utf-8"))
    sys.stderr.flush()
    sys.exit(2)


def guarded_main(hook, body):
    """想定外の入力・例外: クロスレビューの担当なら止める側、担当でなければ通す側。"""
    data = read_input()
    if not is_cross_review_agent(data):
        return 0
    try:
        return body(data)
    except SystemExit:
        raise
    except Exception as e:  # noqa: BLE001  想定外は全部、止める側に倒す
        msg = f"[cross-review hook] 止めた: hook {hook} の想定外の誤り（{type(e).__name__}: {e}）\n直し方: 主担当に知らせる（hook の側の誤りの可能性）"
        sys.stderr.buffer.write(msg.encode("utf-8"))
        sys.exit(2)
