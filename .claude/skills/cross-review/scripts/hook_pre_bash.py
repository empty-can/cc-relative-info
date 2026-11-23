"""PreToolUse hook（Bash・PowerShell）: クロスレビューの担当のコマンドを「許す形の列挙」で絞る。

許す形（先頭の NAME=値 の並びを外した後。PowerShell は NAME=値 を受けない。実行ファイルは名前だけで書く。パスつきは止める）:
  1. bash <ファイル> [引数…]            bash -n <ファイル>（語がちょうど 3 つのときだけ。構文の確かめだけ。走査しない）
  2. python -I -X utf8 <ファイル> [引数…]
  3. git -C <パス> <読み取りのサブコマンド> [引数…]   （サブコマンドの前は -C <パス> と --no-pager だけ。git の前の NAME=値 は止める）
     読み取り: READ_SUB の 1 語、READ_SUB_WORD の 2 語、READ_SUB_OPT のオプションつき（後ろにオプションを続けない）、
     branch の一覧のオプション（BRANCH_FLAGS・BRANCH_VALOPT）、READ_SUB_BARE の引数なし。
     --output・--ext-diff・--open-files-in-pager などとその 4 字以上の略記、-O と grep の -lO の束ねは止める
  4. PowerShell ツールだけ: pwsh|powershell -NoProfile [-NonInteractive] [-NoLogo] [-ExecutionPolicy Bypass|RemoteSigned] -File <ファイル> [引数…]
ほかは全部止める（直し方: スクリプトファイルに書いて 1 コマンドで実行する。読むだけなら Read・Grep・Glob を使う）。
背景の実行（tool_input の run_in_background: true）は、ファイルを流す形（1・2・4）で走査を通れば通す。git -C は背景なら止める。
改行・連結の記号（; && || | & 改行）、ヒアドキュメント、$(…)、バッククォート、リダイレクト（> <）を含むものは止める
（引用符の中でも止める）。PowerShell ツールでは括弧 ( ) { } も止める（引数の位置の (式)・@(…) が実行される）。
前置きの NAME=値 のうち、BASH_ENV・PATH・GIT_*・CROSS_REVIEW_*・CLAUDE_* などは止める。

Bash ツールのコマンドは bash と同じ引用符の解き方（shlex の posix）で語に分ける。git の形は $ と波括弧の展開
（{a,b}・{a..b}）を含めば止める。
ファイルを流す形（1・2・4）は、必ずそのファイルを読んで走査する（拡張子によらない。読めなければ止める）。
skill の中の固定のスクリプト（このファイルと同じフォルダ。パスは .. とリンクを解いて比べる）は走査を飛ばす。
guard とみなすのは: sh は行の頭の source・. の後のパスが絶対パスで、skill の guard_tmp.sh そのもの（.. とリンクを
解いて比べる）／py は runpy.run_path(…guard_tmp.py…) の同じ呼び出しに run_name="guard_tmp_run" があるもの。
走査で止めるもの: 書き込み系の git か削除か「中身に書き込み系の git か削除を持つ・中身を読めない別のスクリプトを流す行」が
あるのに、それより前に guard が無い／対象のリポジトリの絶対パス（作業フォルダの 30_tmp の下は除く）と書き込み系の git か
削除が同じ行にある（clone の元は除く）／リポジトリへの cd と書き込み系の git か削除が同じスクリプトにある／
書き込み系の git の -C・--git-dir・--work-tree・cwd= が変数・式・.. を含むパス・C:\\tmp の外の絶対パス（足場からの
相対パスだけを許す）／guard の後で足場の外へ移りうる（cd -・popd・~・変数・式・足場の根より上へ出る ..・C:\\tmp の外への
cd・pushd・os.chdir）後の書き込み系の git・削除／guard の後の削除の対象に C:\\tmp と作業フォルダの 30_tmp の外の
絶対パスか .. がある／scaffold.py clean／テスト用の口と hook の設定・ログ。
別のスクリプトを流す行（bash・sh・source・.・python・pwsh -File、Python の ["bash", …]・["python", …]・
[sys.executable, …]・subprocess・os.system の文字列・runpy.run_path）は、流す先が字句で読めて実在すれば、
同じ走査にかける（深さ MAX_DEPTH まで。循環は 1 回だけ読む）。呼ぶ側のその行より前に guard があれば、呼ばれる側は
guard を読み込んだものとして読む（呼ばれる側の中の cd は追わない）。読めない（変数・実在しない・深すぎる）なら、
その行を「guard が要る行」に数える。
Python の配列の形の git（["git", "-C", REPO, "show", …]）は、改行をまたいで読み、引用符の無い要素を <式> として
位置を保つ。-C の値の { } は <式> とみなす。
走査は近似: 変数の中身、リダイレクト、文字列・コメントの中の語の区別は見ない（語を分けて書けば止まらない）。
PowerShell のスクリプト（-File）には guard が無いので、書き込み系の git か削除があれば止める（guard つきの bash の
ラッパーから呼ぶ）。agent_type が cross-review- で始まらない入力は、何もせず通す。
"""
import importlib.util
import os
import re
import shlex
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # .claude の下に __pycache__ を作らない

_spec = importlib.util.spec_from_file_location("hook_common", Path(__file__).resolve().parent / "hook_common.py")
hc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(hc)

HOOK = "pre_bash"
FIX_FORM = ("処理を Write ツールで `<作業フォルダ>\\30_tmp\\<担当名>\\` の .sh か .py に書き、`bash <ファイル>` か "
            "`python -I -X utf8 <ファイル>` の 1 コマンドで実行する。読むだけなら Read・Grep・Glob ツールを使う。"
            "読み取りの git は `git -C <パス> <サブコマンド> …` の形で書く")
FIX_GIT = ("対象のリポジトリで書き込み系の git を実行しない（コミットは主担当が行う）。足場（C:\\tmp\\<名前>）の git は、"
           "冒頭で足場へ移って guard_tmp を読み込むスクリプトの中で、足場からの相対パスで行う")
FIX_RM = ("消すのは足場だけ。`python -I -X utf8 .claude/skills/cross-review/scripts/scaffold.py remove <名前 か パス>` を使う。"
          "スクリプトで消すときは、冒頭で足場へ移って guard_tmp を読み込み、足場からの相対パスで消す")
_SD = hc.SCRIPTS_DIR.as_posix()
GUARD_LINE_SH = (f'source "{_SD}/guard_tmp.sh" || exit 3（その前に `cd "$VERIF_ROOT" || exit 3`。'
                 'パスは絶対パスで、この skill の guard_tmp.sh そのものを書く。変数・相対パスは guard とみなさない）')
GUARD_LINE_PY = (f'runpy.run_path(r"{_SD}/guard_tmp.py", run_name="guard_tmp_run")'
                 '（その前に `os.chdir(r"C:\\tmp\\<名前>")`。run_name を省くと guard は何もしない）')
FIX_READONLY = "読むだけのスクリプトなら、文字列やコメントの git commit・rm -rf の語を分けて書く（git-commit・rm-rf のように空白を外す）"
MAX_DEPTH = 3   # 別のスクリプトを流す行を追う深さの上限

READ_SUB = {"diff", "show", "log", "status", "ls-files", "ls-tree", "rev-parse", "cat-file", "blame", "grep",
            "shortlog", "describe", "merge-base", "rev-list", "show-ref", "for-each-ref", "name-rev", "cherry",
            "diff-tree", "diff-index", "diff-files", "count-objects", "check-ignore", "check-attr", "whatchanged",
            "range-diff", "annotate", "var", "version"}
# 2 語で決まる読み取り（2 語目が動作の名前）。後ろのオプションも受ける
READ_SUB_WORD = {("worktree", "list"), ("stash", "list"), ("stash", "show"), ("reflog", "show"), ("remote", "get-url")}
# オプションで決まる読み取り。後ろにオプションを続けない。後ろの語（パターン・キー）は (最小, 最大) 個まで
READ_SUB_OPT = {("remote", "-v"): (0, 0), ("config", "--get"): (1, 2), ("config", "--get-regexp"): (1, 2),
                ("config", "--list"): (0, 0), ("config", "-l"): (0, 0), ("tag", "--list"): (0, 9), ("tag", "-l"): (0, 9)}
# branch の一覧のオプション。これだけから成れば読み取り。パターン（オプションでない語）は --list・-l があるときだけ受ける
BRANCH_FLAGS = {"-a", "--all", "-r", "--remotes", "-v", "-vv", "--verbose", "--list", "-l", "--show-current",
                "--no-color", "--no-column", "--omit-empty"}
BRANCH_VALOPT = {"--contains", "--no-contains", "--merged", "--no-merged", "--points-at", "--sort", "--format"}
# 引数の無いときだけ読み取り（一覧を出す）
READ_SUB_BARE = {"branch", "tag", "reflog", "remote"}
# ファイルへ書き出す・別のプログラムを動かす長いオプション。git は一意な略記（--op= など）も受けるので、4 字以上の頭でも止める
DANGER_LONG = ("--output", "--ext-diff", "--open-files-in-pager", "--exec", "--upload-pack", "--receive-pack")
GREP_VALUE_SHORT = set("efABCm")   # grep の短いオプションのうち値を取るもの（束ねの中でこの後ろは値）
META = re.compile(r"[;&|<>`\n\r]|\$\(")
PS_OPTS = {"-noprofile", "-noninteractive", "-nologo"}
# 前置きの NAME=値 で受けない名前（スクリプトの走査を外す・別のプログラムを動かす・hook とテストの口を差し替える）
ENV_DENY = {"BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS", "PATH", "LD_PRELOAD", "PROMPT_COMMAND", "PYTHONSTARTUP"}
ENV_DENY_PREFIX = ("GIT_", "BASH_FUNC_", "CROSS_REVIEW_", "CLAUDE_")
DELETE_SH = re.compile(r"(?<![\w.-])(?:\S*/)?(?:rm|rmdir|unlink|shred)(?=\s|$)|(?<=\s)-delete(?=\s|$)")
DELETE_PS = re.compile(r"(?i)(?<![\w.-])(?:remove-item|ri|rd|del|rm|rmdir|erase|clear-content)(?=\s|$|\()|(?:::|\.)delete\s*\(")
DELETE_PY = re.compile(r"shutil\.(?:rmtree|move)\s*\(|os\.(?:remove|unlink|rmdir|removedirs|system|popen)\s*\(|\.(?:unlink|rmdir)\s*\("
                       r"|(?<![\w.])(?:rmtree|removedirs)\s*\(|subprocess\.\w+\s*\(\s*\[?\s*['\"](?:rm|rmdir|del)['\"\s]")
# from shutil・os import の後で前置きなしに呼べる、削除・別のコマンドを動かす名前
PY_DEL_NAMES = {"rmtree", "move", "remove", "unlink", "rmdir", "removedirs", "system", "popen"}
GIT_OPT_WITH_VALUE = {"-c", "--git-dir", "--work-tree", "--namespace", "--exec-path", "--super-prefix", "--config-env"}
# コマンドの位置（行の頭・; && || | ( { の後・then do else exec time if while until の後）
CMDPOS = r"(?:^\s*|[;&|(){]\s*|\b(?:then|do|else|exec|time|if|while|until)\s+)"
CALL_SH = re.compile(CMDPOS + r"(?:[A-Za-z_]\w*=\S*\s+)*(bash|sh|source|\.|python[\d.]*|py|pwsh|powershell)(?:\.exe)?(?=\s)", re.I)
CALL_PS = re.compile(r"(?:^|[;|(){]|&&)\s*&(?!&)\s*(?=\S)")   # PowerShell の呼び出し演算子 &（&& の中の & は除く）
CD_SH = re.compile(CMDPOS + r"(cd|pushd|popd)(?=\s|$|[;&|)])")
CALL_PY_ARR = re.compile(r"""[\[(]\s*(?:[rbfuRBFU]{0,2}["'](?:[^"'\n]*[/\\])?(bash|sh|python[\d.]*|py|pwsh|powershell)(?:\.exe)?["']"""
                         r"""|(sys\.executable))\s*,""", re.I)
GIT_PY_ARR = re.compile(r"""[\[(]\s*[rbfuRBFU]{0,2}["'](?:[^"'\n]*[/\\])?git(?:\.exe)?["']\s*,""", re.I)
PY_STR = re.compile(r"""[rbfuRBFU]{0,2}(["'])((?:(?!\1).)*)\1""")


def tokens(cmd, posix=False):
    """posix=True は bash と同じ引用符の解き方（"cherry"-pick → cherry-pick）。Bash ツールのコマンドに使う。
    posix=False は外側の引用符だけを外す（PowerShell ツールのコマンドと、スクリプトの行の走査に使う）。"""
    if posix:
        return shlex.split(cmd, comments=False, posix=True)
    lex = shlex.shlex(cmd, posix=False)
    lex.whitespace_split = True
    lex.commenters = ""
    return [t[1:-1] if len(t) >= 2 and t[0] == t[-1] and t[0] in "\"'" else t for t in lex]


def sh_words(s, posix=True):
    """行の残りを語に分け、最初のコマンドの区切り（; & | ( ) < >）までを返す。分けられなければ空白で分ける。
    posix=True は bash の解き方。PowerShell のスクリプトの行は posix=False（\\ を外さず、外側の引用符だけを外す）。"""
    try:
        if not posix:
            return tokens(re.split(r"[;&|()<>]", s, maxsplit=1)[0])
        lex = shlex.shlex(s, posix=True, punctuation_chars=";&|()<>")
        lex.whitespace_split = True
        lex.commenters = ""
        out = []
        for t in lex:
            if t and all(c in ";&|()<>" for c in t):
                break
            out.append(t)
        return out
    except ValueError:
        return s.split()


def git_subcommand(toks):
    """toks[0] が git のとき、(サブコマンド, サブコマンドの後ろの語の一覧, サブコマンドの前のオプションの一覧) を返す。"""
    i, opts = 1, []
    while i < len(toks) and toks[i].startswith("-"):
        o = toks[i]
        opts.append(o)
        if o == "-C" or o in GIT_OPT_WITH_VALUE:
            if i + 1 < len(toks):
                opts.append(toks[i + 1])
            i += 2
        else:
            i += 1
    sub = toks[i].lower() if i < len(toks) else ""
    return sub, toks[i + 1:], opts


def is_read_git(sub, rest):
    """読み取りのサブコマンドの一覧（README に書く）に当たるか。rest はサブコマンドの後ろの語。"""
    nxt = rest[0].lower() if rest else ""
    if sub in READ_SUB:
        return True
    if (sub, nxt) in READ_SUB_WORD:
        return True
    if (sub, nxt) in READ_SUB_OPT:
        lo, hi = READ_SUB_OPT[(sub, nxt)]
        tail = rest[1:]
        return not any(t.startswith("-") for t in tail) and lo <= len(tail) <= hi
    if sub == "branch" and rest:
        return is_read_branch(rest)
    return sub in READ_SUB_BARE and not rest


def bad_git_arg(sub, a):
    """サブコマンドの後ろの語が、ファイルへ書き出す・別のプログラムを動かすオプション（その略記・束ねを含む）か。"""
    if a.startswith("--"):
        name = a.split("=", 1)[0].lower()
        return len(name) >= 4 and any(x.startswith(name) for x in DANGER_LONG)
    if a.startswith("-O"):
        return True
    if sub == "grep" and re.match(r"^-[A-Za-z0-9]", a):   # -5Oecho のように数の後ろにも束ねを続けられる
        for ch in a[1:]:   # 短いオプションの束ね（-lO<命令>）。値を取るオプションの後ろは値
            if ch == "O":
                return True
            if ch in GREP_VALUE_SHORT:
                break
    return False


def is_read_branch(rest):
    """git branch の後ろが一覧のオプション（BRANCH_FLAGS・BRANCH_VALOPT とその値）だけか。パターンは --list・-l のときだけ。"""
    i, flags, pats = 0, set(), []
    while i < len(rest):
        t = rest[i]
        name = t.split("=", 1)[0].lower()
        if t.lower() in BRANCH_FLAGS:
            flags.add(t.lower())
        elif name in BRANCH_VALOPT:
            if "=" not in t and i + 1 < len(rest) and not rest[i + 1].startswith("-"):
                i += 1   # 値（コミット・並べ方・書式）
        elif t.startswith("-"):
            return False
        else:
            pats.append(t)
        i += 1
    return not pats or bool(flags & {"--list", "-l"})


def _elem_value(e):
    """Python の配列の 1 要素: 文字列の字句ならその中身、ほか（変数・式）は <式>。"""
    m = re.match(r"""^\s*[rbfuRBFU]{0,2}(["'])(.*)\1\s*$""", e)
    return m.group(2) if m else "<式>"


def _strip_tok(t):
    return t.strip("\"'`()[]{},;")


def _py_elems(text):
    """Python の配列・タプルの残り（最初の要素の後ろの , から）を、深さ 0 の , で切って要素の字句の一覧にする。"""
    elems, cur, depth, quote = [], "", 0, None
    pairs = {"(": ")", "[": "]", "{": "}"}
    for ch in text:
        if quote:
            cur += ch
            if ch == quote:
                quote = None
            continue
        if ch in "\"'":
            quote = ch
            cur += ch
        elif ch in pairs:
            depth += 1
            cur += ch
        elif ch in ")]}":
            if depth == 0:
                break
            depth -= 1
            cur += ch
        elif ch == "," and depth == 0:
            elems.append(cur)
            cur = ""
        else:
            cur += ch
    elems.append(cur)
    return [e for e in elems if e.strip()]


def py_git_arrays(text):
    """Python の配列・タプルの形の git（["git", "-C", REPO, "push"]）を本文全体で探す（1 要素 1 行の書き方も読む）。
    書き込み系のものを {行の番号: (サブコマンド, 前のオプション)} で返す。行の番号は配列の始まりの行。"""
    hits = {}
    for m in GIT_PY_ARR.finditer(text):
        elems = ["git"] + [_elem_value(e) for e in _py_elems(text[m.end():])]
        sub, rest, opts = git_subcommand(elems)
        if sub and not is_read_git(sub, rest):
            hits.setdefault(text.count("\n", 0, m.start()) + 1, (sub, opts))
    return hits


def git_line_writes(line, arrays=True):
    """1 行の中の git の呼び出しが書き込み系（読み取りの一覧に無いもの）なら、そのサブコマンドを返す。
    コマンドの形（git -C x commit、文字列の中の "git -C x commit"）と、arrays のとき Python の配列・タプルの形
    （["git", "-C", REPO, "push"]。引用符の無い要素は <式> として位置を保つ）を見る。
    文字列の形の語の { }（f 文字列・format の差し込み）は <式> として位置を保つ。"""
    for m in (GIT_PY_ARR.finditer(line) if arrays else ()):
        elems = ["git"] + [_elem_value(e) for e in _py_elems(line[m.end():])]
        sub, rest, opts = git_subcommand(elems)
        if sub and not is_read_git(sub, rest):
            return sub, opts
    for m in re.finditer(r"""(?i)(?:^|(?<=[\s"'`(=]))(?:[^\s"'`(]*[/\\])?git(?:\.exe)?(?=\s)""", line):
        try:
            rest = tokens(line[m.end():])
        except ValueError:
            rest = line[m.end():].split()
        # 語の途中の引用符より後ろ（"… push".format(repo) の .format(repo）は、git の引数ではないので外す
        cut = ["<式>" if ("{" in t or "}" in t) else re.split(r"[\"']", _strip_tok(t))[0] for t in rest]
        toks = ["git"] + [t for t in cut if t]
        sub, rest2, opts = git_subcommand(toks)
        if sub and not is_read_git(sub, rest2):
            return sub, opts
    return None, []


def git_target_outside(opts):
    """書き込み系の git の -C・--git-dir・--work-tree の値が、足場の外を指しうるか（変数・式・C:\\tmp の外の絶対パス）。
    足場からの相対パス（guard_tmp で今の場所が足場の下と分かっている）だけを許す。"""
    for k, v in zip(opts, opts[1:] + [""]):
        if k not in ("-C", "--git-dir", "--work-tree"):
            continue
        if v == "<式>" or any(c in v for c in "$%~{}") or not v or ".." in re.split(r"[/\\]", v):
            return v or "（値なし）"   # .. を含む相対パスは足場の外へ出られる
        if re.match(r"^(?:[A-Za-z]:|[/\\])", v) and not hc.norm(v).startswith("c:/tmp/"):
            return v
    return None


PATH_RE = re.compile(r"""(?i)(?:[a-z]:[\\/]|(?<![\w.])/[a-z]/)[^\s"'`,;()\[\]{}<>|]*""")


def line_paths(line):
    """1 行の中の絶対パス（C:/…・C:\\…・Git Bash の /c/…）を比較用の形で返す。変数（$REPO など）は解かない（近似）。"""
    return [hc.norm(m.group(0)) for m in PATH_RE.finditer(line)]


def repo_paths(line, repo, work_tmp):
    """行の中の、対象のリポジトリの下のパス（作業フォルダの 30_tmp の下は除く）。"""
    return [p for p in line_paths(line) if repo and hc.under(p, repo) and not (work_tmp and hc.under(p, work_tmp))]


def _native(p):
    """Git Bash の /c/… を c:/… にする（ほかはそのまま）。"""
    m = re.match(r"^/([a-zA-Z])(/.*)?$", p)
    return f"{m.group(1)}:{m.group(2) or '/'}" if m else p


def _is_abs(p):
    return bool(re.match(r"^(?:[A-Za-z]:[\\/]|/[A-Za-z]/|[\\/])", p))


def resolve_target(tok, base):
    """流す先の語を実在するファイルの実パスにする。読めない（変数・式・相対で base が無い・無い）なら None。"""
    if not tok or tok == "<式>" or any(c in tok for c in "$`*?~{}%<>"):
        return None
    p = _native(tok)
    if not _is_abs(p):
        if not base:
            return None
        p = os.path.join(base, p)
    real = os.path.realpath(p)
    return real if os.path.isfile(real) else None


def is_skill_script(real):
    return hc.strictly_under(real, os.path.realpath(str(hc.SCRIPTS_DIR)))


def guard_sh_problem(line):
    """行の頭の source・. が guard_tmp.sh を読み込む行なら、問題の文（正しい guard なら ""）を返す。guard の行でなければ None。"""
    if not re.match(r"^\s*(?:source|\.)\s+\S*guard_tmp\.sh", line):
        return None
    words = sh_words(re.sub(r"^\s*(?:source|\.)\s+", "", line))
    tok = words[0] if words else ""
    want = hc.norm(os.path.realpath(str(hc.SCRIPTS_DIR / "guard_tmp.sh")))
    if not tok or any(c in tok for c in "$`~{}") or not _is_abs(_native(tok)):
        return f"guard のパス {tok} が絶対パスでない（変数・相対パスは読み込めないことがあり、bash は無いファイルの source で止まらない）"
    if hc.norm(os.path.realpath(_native(tok))) != want:
        return f"guard のパス {tok} が skill の guard_tmp.sh でない"
    return ""


def guard_py_problem(stmt):
    """runpy.run_path(…guard_tmp.py…) の文なら問題の文（正しければ ""）、guard の文でなければ None。"""
    if not re.search(r"""runpy\.run_path\s*\(\s*[rR]?["'][^"']*guard_tmp\.py""", stmt):
        return None
    if not re.search(r"""run_name\s*=\s*["']guard_tmp_run["']""", stmt):
        return 'guard の runpy.run_path に run_name="guard_tmp_run" が無い（無いと guard は何もしない）'
    return ""


def py_del_re(text):
    """from shutil・os import で前置きなしに使える名前と、import shutil as X の X を、削除の字句に足す。"""
    pats = []
    for m in re.finditer(r"^\s*from\s+(?:shutil|os|os\.path)\s+import\s+\(?([^\n#)]+)", text, re.M):
        for part in m.group(1).split(","):
            bits = part.split()
            if bits and bits[0] in PY_DEL_NAMES:
                pats.append(re.escape(bits[2] if len(bits) >= 3 and bits[1] == "as" else bits[0]))
    extra = [rf"(?<![\w.])(?:{'|'.join(pats)})\s*\("] if pats else []
    for m in re.finditer(r"^\s*import\s+(?:shutil|os)\s+as\s+(\w+)", text, re.M):
        extra.append(rf"(?<![\w.]){re.escape(m.group(1))}\.(?:{'|'.join(sorted(PY_DEL_NAMES))})\s*\(")
    return re.compile("|".join([DELETE_PY.pattern] + extra)) if extra else DELETE_PY


def py_stmt(lines, i, limit=30):
    """i 行目（0 始まり）から、括弧が閉じるまでの文（改行をまたぐ）を返す。文字列の中の括弧は数えない（近似）。"""
    depth, quote, out = 0, None, []
    for raw in lines[i:i + limit]:
        out.append(raw)
        for ch in raw:
            if quote:
                quote = None if ch == quote else quote
            elif ch in "\"'":
                quote = ch
            elif ch == "#":
                break
            elif ch in "([{":
                depth += 1
            elif ch in ")]}":
                depth -= 1
        if depth <= 0:
            break
    return " ".join(out)


def py_line_depths(lines):
    """各行の頭での括弧の深さ（Python）。文字列（三重引用符を含む）・コメントの中の括弧は数えない。複数行の文字列の中の行は 1 以上。"""
    depths, depth, q = [], 0, None
    for line in lines:
        depths.append(depth if q is None else max(depth, 1))
        i = 0
        while i < len(line):
            if q:
                if line.startswith(q, i):
                    i, q = i + len(q), None
                else:
                    i += 2 if line[i] == "\\" else 1
                continue
            c = line[i]
            if c == "#":
                break
            if line.startswith(('"""', "'''"), i):
                q, i = line[i:i + 3], i + 3
                continue
            if c in "\"'":
                q = c
            elif c in "([{":
                depth += 1
            elif c in ")]}":
                depth = max(0, depth - 1)
            i += 1
        if q in ('"', "'"):
            q = None   # 1 つの引用符の文字列は行の終わりで閉じる（近似）
    return depths


def enclosing_stmt(lines, depths, i, limit=40):
    """i 行目（0 始まり）を含む文（括弧が開いたまま続く行のまとまり）を返す。"""
    s = i
    while s > 0 and depths[s] > 0 and i - s < limit:
        s -= 1
    e = i
    while e + 1 < len(lines) and depths[e + 1] > 0 and e - i < limit:
        e += 1
    return " ".join(lines[s:e + 1])


def py_cwd_outside(stmt):
    """文の中の cwd= の値が足場の外を指しうるなら、その値を返す（-C と同じ見方。字句の相対パスと C:\\tmp の下だけ許す）。"""
    m = re.search(r"\bcwd\s*=\s*", stmt)
    if not m:
        return None
    elems = _py_elems(stmt[m.end():])
    v = _elem_value(elems[0]) if elems else "<式>"
    return git_target_outside(["-C", v])


def del_outside(line, pos, work_tmp):
    """guard の後の削除の行で、対象に C:\\tmp と作業フォルダの 30_tmp の外の絶対パスか .. があれば、それを返す。
    見るのは削除の語（pos）を含むコマンドだけ（前後の ; && || | まで。同じ行の cd .. && rm -rf x の cd .. は見ない）。"""
    seps = [m.end() for m in re.finditer(r";|&&|\|\||\|", line[:pos])]
    m = re.search(r";|&&|\|\||\|", line[pos:])
    line = line[(seps[-1] if seps else 0):(pos + m.start() if m else len(line))]
    for p in line_paths(line):
        if not (p.startswith("c:/tmp/") or (work_tmp and hc.under(p, work_tmp))):
            return p
    if ".." in re.split(r"""[/\\\s"'=,()\[\]]""", line):
        return ".."
    return None


def call_target(cmd, words):
    """別のスクリプトを流す語の並び（cmd の後ろ）から、(流す先の語, 種類) を返す。ファイルを流さない形（-c・-m）は None。"""
    c = cmd.lower()
    c = c[:-4] if c.endswith(".exe") else c
    if c in ("source", "."):
        return (words[0], "sh") if words else None
    if c in ("bash", "sh"):
        for w in words:
            if w.startswith("-") and not w.startswith("--") and ("c" in w[1:] or "n" in w[1:]):
                return None   # -c（文字列を流す。同じ行の語は走査で読む）・-n（実行しない）
            if not w.startswith(("-", "+")):
                return (w, "sh")
        return None
    if c in ("pwsh", "powershell"):
        for k, w in enumerate(words):
            if w.lower() in ("-file", "-f") and k + 1 < len(words):
                return (words[k + 1], "ps1")
        return None
    k = 0   # python
    while k < len(words):
        w = words[k]
        if w in ("-X", "-W"):
            k += 2
        elif w.startswith("-") and not w.startswith("--") and ("c" in w[1:] or "m" in w[1:]):
            return None
        elif w.startswith("-"):
            k += 1
        else:
            return (w, "py")
    return None


class CdState:
    """guard の後の今の場所。guard を読み込んだ場所を深さ 0 とし、足場の外へ移りうれば left にする。"""

    def __init__(self):
        self.depth, self.stack, self.left, self.why = 0, [], False, ""

    def apply(self, op, arg, raw):
        if op == "popd":
            if self.stack:
                self.depth = self.stack.pop()
            else:
                self._out(raw)   # guard より前の pushd の元（足場の外）へ戻る
            return
        if op == "pushd":
            self.stack.append(self.depth)
        if not arg or arg == "-" or arg.startswith("~") or arg == "<式>" or any(c in arg for c in "$`%{}*"):
            return self._out(raw)   # 元の場所・ホーム・変数・式
        p = _native(arg)
        if _is_abs(p):
            n = hc.norm(p)
            if n.startswith("c:/tmp/"):
                self.left, self.depth = False, len(n.split("/")) - 3
            else:
                self._out(raw)
            return
        for seg in re.split(r"[/\\]", p):
            if seg == "..":
                self.depth -= 1
                if self.depth < 0:
                    return self._out(raw)   # guard の場所より上へ出る
            elif seg not in ("", "."):
                self.depth += 1

    def _out(self, raw):
        self.left, self.why = True, raw.strip()[:80]


def line_cd_ops(line, kind):
    """行の中の場所を移す操作 [(cd・pushd・popd, 引数)]。py は os.chdir。ps1 は追わない（guard が無い）。"""
    ops = []
    if kind == "py":
        for m in re.finditer(r"os\.chdir\s*\(", line):
            el = _py_elems(line[m.end():])
            ops.append(("cd", _elem_value(el[0]) if el else "<式>"))
    elif kind == "sh":
        for m in CD_SH.finditer(line):
            w = sh_words(line[m.end():])
            while w and w[0].startswith("-") and w[0] != "-":
                w.pop(0)   # cd -P <dir> など
            ops.append((m.group(1).lower(), w[0] if w else None))
    return ops


def line_calls(line, kind, stmt):
    """行の中の、別のスクリプトを流す箇所 [(流す先の語, 種類)]。py は stmt（改行をまたぐ文）のうち、この行で始まるもの。"""
    out = []
    if kind in ("sh", "ps1"):
        posix = kind == "sh"
        for m in CALL_SH.finditer(line):
            t = call_target(m.group(1), sh_words(line[m.end():], posix))
            if t:
                out.append((t[0], "ps1" if kind == "ps1" and m.group(1) == "." else t[1]))
        for m in (CALL_PS.finditer(line) if kind == "ps1" else ()):
            w = sh_words(line[m.end():], posix=False)
            ext = os.path.splitext(w[0])[1].lower() if w else ""
            # & <スクリプト> か & <変数> だけを数える（& git … などのコマンドは、同じ行の語の走査で読む）
            if w and (ext in (".ps1", ".py", ".sh", ".bat", ".cmd") or "$" in w[0]):
                out.append((w[0], {".py": "py", ".sh": "sh"}.get(ext, "ps1")))
        return out
    for m in CALL_PY_ARR.finditer(stmt):
        if m.start() < len(line):
            t = call_target(m.group(1) or "python", [_elem_value(e) for e in _py_elems(stmt[m.end():])])
            if t:
                out.append(t)
    if re.search(r"subprocess\.\w+\s*\(|os\.(?:system|popen)\s*\(", line):
        for s in PY_STR.finditer(stmt):
            for m in CALL_SH.finditer(s.group(2)):
                t = call_target(m.group(1), sh_words(s.group(2)[m.end():]))
                if t:
                    out.append(t)
    for m in re.finditer(r"runpy\.run_path\s*\(", line):
        el = _py_elems(line[m.end():])
        out.append((_elem_value(el[0]) if el else "<式>", "py"))
    return out


def check_hit(path, no, raw, line, stmt, kind, what, sub, gopts, del_hit, repo, work_tmp, cd_repo, left_line, st, guard_seen):
    """危ない行（書き込み系の git・削除・危ない別のスクリプトを流す行）1 つの検査。問題があれば (理由, 直し方)。"""
    if sub:
        outside = git_target_outside(gopts) if sub != "clone" else None
        if outside:
            return (f"スクリプト {path} の {no} 行目の{what}が -C・--git-dir・--work-tree で {outside} を指す（足場の外を指しうる）: "
                    f"{raw}", FIX_GIT)
        cwd_out = py_cwd_outside(stmt) if kind == "py" else None
        if cwd_out:
            return (f"スクリプト {path} の {no} 行目の{what}が cwd= で {cwd_out} を指す（足場の外を指しうる）: {raw}",
                    FIX_GIT + "。cwd= は付けない（guard で足場の中にいる）か、足場からの相対パスにする")
    if sub or del_hit:
        hits = repo_paths(line, repo, work_tmp)
        if sub == "clone" and not del_hit:
            hits = hits[1:]   # clone の元（最初のリポジトリのパス）は読むだけ。送り先がリポジトリの中なら止める
        if hits:
            return (f"スクリプト {path} の {no} 行目に、対象のリポジトリの絶対パス（作業フォルダの 30_tmp の下を除く）への{what}がある: "
                    f"{raw}", FIX_GIT if sub else FIX_RM)
    if cd_repo:
        return (f"スクリプト {path} が対象のリポジトリへ移ってから{what}を行う", FIX_GIT if sub else FIX_RM)
    if left_line:
        return (f"スクリプト {path} の {no} 行目の{what}は、guard_tmp の後で足場の外へ移りうる場所の移動（{st.why}）の後にある: {raw}",
                "guard の後は、足場の中の下の階層へだけ移る（cd <下のフォルダ>・cd .. で戻る）。cd -・popd・cd \"$変数\"・"
                "os.chdir(<変数>) で元の場所へ戻らない。片付けも足場の中で、足場からの相対パスで行う")
    if guard_seen and del_hit:
        o = del_outside(line, del_hit.start(), work_tmp)
        if o:
            return (f"スクリプト {path} の {no} 行目の削除の対象に、C:\\tmp と作業フォルダの 30_tmp の外（{o}）がある"
                    f"（guard_tmp は今の場所しか確かめない）: {raw}", FIX_RM)
    return None


def scan_script(path, kind, data, config, inherit=False, depth=0, chain=()):
    """流そうとしたスクリプトの中身を見る。(問題 (理由, 直し方) か None, 危ない行があったか) を返す。kind は sh・py・ps1。
    inherit: 呼ぶ側がその行より前に guard を読み込んでいる（呼ばれる側の走査）。chain: 呼び出しの連なりの実パス（循環の検出）。"""
    text = Path(path).read_bytes().decode("utf-8", errors="replace")
    repo = config.get("repo") or ""
    work_tmp = os.path.join(config.get("work_folder", ""), "30_tmp") if config.get("work_folder") else ""
    if re.search(r"scaffold\.py\W+clean\b", re.sub(r"[\"']", "", text), re.I):
        return (f"スクリプト {path} の中の scaffold.py clean（C:\\tmp の全部の掃除は主担当だけ）", "自分の足場だけを scaffold.py remove で消す"), True
    if re.search(r"CROSS_REVIEW_(SCAFFOLD_ROOT|HOOK_CONFIG)|cross-review-hook\.", text):
        return (f"スクリプト {path} が hook の設定・ログ・テスト用の口に触れる", "担当は hook の設定とログに触れない（読むのは Read ツールで）"), True
    del_re = py_del_re(text) if kind == "py" else (DELETE_PS if kind == "ps1" else DELETE_SH)
    raws = text.split("\n")
    # コメントとみなすのは、行の頭（空白の後）が # の行だけ（行の途中の # は引用符の中でありうるので、消さずに読む）
    lines = [re.sub(r"^\s*#.*$", "", r) for r in raws]
    arrays = py_git_arrays("\n".join(lines)) if kind == "py" else {}
    depths = py_line_depths(lines) if kind == "py" else []
    chain = chain + (hc.norm(os.path.realpath(path)),)
    base = None if depth else (data.get("cwd") or os.getcwd())   # 相対の流す先は、場所を移す前のトップのスクリプトだけ解く
    guard_seen, tracking, st, bad_guard = inherit, False, CdState(), ""
    moved, cd_repo, first_hit = False, False, None
    for no, line in enumerate(lines, 1):
        if not line.strip():
            continue
        raw = raws[no - 1].strip()[:120]
        stmt = py_stmt(lines, no - 1) if kind == "py" else line
        gp = guard_sh_problem(line) if kind == "sh" else (guard_py_problem(stmt) if kind == "py" else None)
        if gp == "":
            guard_seen, tracking, st = True, True, CdState()
            continue
        if gp:
            bad_guard = f"（{no} 行目の guard の行は効かない: {gp}）"
        if re.search(r"(?i)(?<![\w.-])(?:cd|pushd|set-location|sl|os\.chdir)(?![\w-])", line) and repo_paths(line, repo, work_tmp):
            cd_repo = True
        ops = line_cd_ops(line, kind)
        left_before = st.left
        for op, arg in (ops if tracking else ()):
            st.apply(op, arg, raw)
        moved = moved or bool(ops)
        left_line = tracking and (left_before or st.left)
        sub, gopts = (arrays.get(no) or git_line_writes(line, arrays=False)) if kind == "py" else git_line_writes(line)
        del_hit = del_re.search(line)
        call_hit = None
        for tok, ck in line_calls(line, kind, stmt):
            real = resolve_target(tok, None if moved else base)
            if real and is_skill_script(real):
                continue   # skill の固定のスクリプト（scaffold.py clean は上で止める）
            if real and hc.norm(real) in chain:
                continue   # 循環: もう読んでいる
            if not real or depth + 1 > MAX_DEPTH:
                # 「読めない」の語はログの印「ファイル」に当たるので使わない（印は guard・PowerShell に落とす）
                call_hit = call_hit or f"別のスクリプトを流す行（流す先 {tok} の中身を hook が読み取れない）"
                continue
            found, danger = scan_script(real, ck, data, config, guard_seen, depth + 1, chain)
            if found:
                return (f"{found[0]}（{path} の {no} 行目から呼ぶ）", found[1]), True
            if danger:
                call_hit = call_hit or f"git の書き込みか削除を持つ別のスクリプト（{real}）を流す行"
        if not (sub or del_hit or call_hit):
            continue
        what = f"書き込み系の git（{sub}）" if sub else ("削除" if del_hit else call_hit)
        # cwd= は、git の配列・文字列と別の行に書かれうる（整形ツールの出力）ので、括弧の閉じるまでの文全体で見る
        cstmt = enclosing_stmt(lines, depths, no - 1) if (kind == "py" and sub) else stmt
        found = check_hit(path, no, raw, line, cstmt, kind, what, sub, gopts, del_hit, repo, work_tmp,
                          guard_seen and cd_repo, left_line, st, guard_seen)
        if found:
            return found, True
        if first_hit is None:
            first_hit = (no, what, raw, guard_seen, tracking)
    if first_hit:
        no, what, snippet, had_guard, own_guard = first_hit
        if kind == "ps1" and not inherit:
            return (f"PowerShell のスクリプト {path} に{what}がある（{no} 行目: {snippet}）。PowerShell には足場の検査が無い",
                    f"guard_tmp を読み込む bash のラッパー（足場へ cd → {GUARD_LINE_SH} → pwsh -NoProfile -File <そのスクリプト>）を書いて、"
                    "ラッパーを流す"), True
        if not had_guard:
            guard = GUARD_LINE_PY if kind == "py" else GUARD_LINE_SH
            fix = (f"スクリプトの冒頭に次の 1 行を足してから実行する: {guard}。足場は scaffold.py で作って消す"
                   + ("。別のスクリプトから呼ばれるものは、呼ぶ側で呼ぶ行より前に読み込んでもよい" if depth else "")
                   + "。流す先のスクリプトは字句の絶対パスで書く（hook が中身を読む）。" + FIX_READONLY)
            return (f"スクリプト {path} に{what}がある（{no} 行目: {snippet}）のに、それより前に足場の検査 guard_tmp を読み込んでいない{bad_guard}",
                    fix), True
        if cd_repo:
            return (f"スクリプト {path} が対象のリポジトリへ移ってから{what}を行う", FIX_GIT if "git" in what else FIX_RM), True
    # 呼ぶ側へ返す「危ない」は、呼ぶ側の guard に頼る（自分の guard の前に危ない行がある）ときだけ。自分で guard を
    # 読み込んでから危ない行を行うスクリプトは、guard の無い呼ぶ側から呼んでもよい
    return None, bool(first_hit) and not first_hit[4]


def check_file(path_tok, kind, data, config, d):
    cwd = data.get("cwd") or os.getcwd()
    p = Path(path_tok)
    if not p.is_absolute():
        p = Path(cwd) / p
    real = os.path.realpath(str(p))
    if hc.strictly_under(real, os.path.realpath(str(hc.SCRIPTS_DIR))) and os.path.isfile(real):
        return   # skill の中の固定のスクリプト（.. とリンクを解いた後で、scripts の真に下にあるファイル）
    if not os.path.isfile(real):
        d(f"流そうとしたファイル {path_tok} が読めない（無い・フォルダ）", "ファイルのパスを確かめる。スクリプトは Write ツールで書いてから流す")
    found, _ = scan_script(real, kind, data, config)
    if found:
        d(found[0], found[1])


def body(data):
    config, err = hc.load_config()
    tool = data.get("tool_name", "")
    ti = data.get("tool_input")
    if not isinstance(ti, dict):
        hc.deny(config, data, HOOK, "tool_input の形が想定外", "主担当に知らせる")
    cmd = str(ti.get("command") or "")
    d = lambda reason, fix: hc.deny(config, data, HOOK, reason, fix, cmd)
    if err:
        d(err, "主担当に、hook の設定を段階 0 の手順で置いてもらう")
    background = bool(ti.get("run_in_background"))   # 背景の指定だけでは止めない（ファイルを流す形で走査を通れば通す）
    if not cmd.strip():
        d("コマンドが空", FIX_FORM)
    m = META.search(cmd)
    if m:
        what = {"\n": "改行", "\r": "改行", "`": "バッククォート", "$(": "$(…)", "<": "< （リダイレクト・ヒアドキュメント）", ">": "> （リダイレクト）"}.get(m.group(0), m.group(0))
        hint = "。git の --format の ; | は %x3b・%x7c で書ける（例 --format=%h%x3b%s）" if m.group(0) in (";", "|") else ""
        d(f"1 回の呼び出しで 2 つ以上のコマンドをつなぐ・埋め込む記号（{what}）", FIX_FORM + hint)
    is_ps = tool == "PowerShell"
    if is_ps and re.search(r"[(){}]", cmd):
        # PowerShell は引数の位置の (式)・@(…) を評価してから渡すので、括弧の中で別のコマンドが動く
        d("PowerShell の引数の括弧（( ) { }。中の式が実行される）", FIX_FORM)
    try:
        # Bash ツールは bash と同じ引用符の解き方で分ける（"cherry"-pick・"--out"put= を bash と同じ 1 語に読む）
        toks = tokens(cmd, posix=not is_ps)
    except ValueError:
        d("コマンドの引用符が閉じていない", FIX_FORM)
    env_names = []
    while not is_ps and toks and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", toks[0]):
        env_names.append(toks.pop(0).split("=", 1)[0])
    if any(n.startswith(("CROSS_REVIEW_", "CLAUDE_")) for n in env_names) or "CROSS_REVIEW_" in cmd:
        d("hook・scaffold.py の設定の差し替え（テスト用の口・環境変数の前置きを含む）", "担当は差し替えない。既定のまま scaffold.py を使う")
    bad_env = [n for n in env_names if n.upper() in ENV_DENY or n.upper().startswith(ENV_DENY_PREFIX)]
    if bad_env:
        d(f"前置きの環境変数 {'・'.join(bad_env)}（スクリプトの走査を外す・別のプログラムを動かす名前）",
          "前置きに使ってよいのは VERIF_ROOT のような値の受け渡しだけ。処理はスクリプトの中に書く")
    if "cross-review-hook." in cmd:
        d("hook の設定・ログに触れるコマンド", "担当は hook の設定とログに触れない（読むのは Read ツールで）")
    if not toks:
        d("コマンドが空", FIX_FORM)
    exe = toks[0].replace("\\", "/")
    head = exe.lower().rsplit("/", 1)[-1]
    if head in ("bash", "bash.exe", "python", "python.exe", "git", "git.exe", "pwsh", "pwsh.exe", "powershell", "powershell.exe") \
            and exe.lower() != head:
        d(f"{head} をパスつきで呼ぶ形（{toks[0]}）", f"`{head.replace('.exe', '')}` を名前だけで呼ぶ（PATH の上のものを使う）。" + FIX_FORM)
    if head in ("bash", "bash.exe"):
        if len(toks) == 3 and toks[1] == "-n" and not toks[2].startswith(("-", "+")):
            return 0   # 構文の確かめだけ（実行しない）。走査しない。+n（noexec を外す）などを後ろに付けた形は通さない
        if len(toks) < 2 or toks[1].startswith("-"):
            d("bash にオプションを付ける・ファイルを渡さない形", FIX_FORM)
        check_file(toks[1], "sh", data, config, d)
        return 0
    if head in ("python", "python.exe"):
        if toks[1:4] != ["-I", "-X", "utf8"] or len(toks) < 5 or toks[4].startswith("-"):
            d("python の形が `python -I -X utf8 <ファイル> [引数…]` でない（-c・-m・別のオプション）", FIX_FORM)
        if re.search(r"scaffold\.py$", toks[4].replace("\\", "/"), re.I) and len(toks) > 5 \
                and re.sub(r"[\"']", "", toks[5]).lower() == "clean":
            d("scaffold.py clean（C:\\tmp の全部の掃除）は主担当だけが使う", "自分の足場だけを `scaffold.py remove <名前>` で消す")
        check_file(toks[4], "py", data, config, d)
        return 0
    if head in ("git", "git.exe"):
        if background:
            d("読み取りの git を背景（run_in_background）で実行する形", "読み取りの git は前面で実行する（背景にする理由が無い）")
        if env_names:
            d("git の前の環境変数の前置き", "読み取りの git は前置きを付けずに `git -C <パス> <サブコマンド> …` で書く")
        if re.search(r"\$|\{[^{}]*(?:,|\.\.)[^{}]*\}", cmd):
            d("git の形に $・波括弧の展開（{a,b}・{a..b}）がある（シェルが語を組み立て直すので、hook の読みと食い違う）",
              "読み取りの git は展開の無い字句だけで書く。組み立てが要るならスクリプトに書く")
        rest = toks[1:]
        if not rest or rest[0] not in ("-C", "--no-pager"):
            d("git の形が `git -C <パス> <読み取りのサブコマンド> …` でない（git は -C <パス> から始める読み取りだけ。"
              "clone・init など足場の git は、guard つきのスクリプトの中で行う）",
              FIX_GIT + "。読み取りは `git -C <パス> <サブコマンド>` の形で")
        n_c = 0
        while rest and rest[0] in ("-C", "--no-pager"):
            if rest[0] == "-C":
                if len(rest) < 2 or rest[1].startswith("-"):
                    break
                n_c, rest = n_c + 1, rest[2:]
            else:
                rest = rest[1:]
        if n_c != 1 or not rest or rest[0].startswith("-"):
            d("git の形が `git -C <パス> <読み取りのサブコマンド> …` でない（-c・--exec-path などサブコマンドの前のオプション）", FIX_GIT + "。読み取りは `git -C <パス> <サブコマンド>` の形で")
        sub, args = rest[0].lower(), rest[1:]
        if not is_read_git(sub, args):
            d(f"書き込み系か、読み取りの一覧に無い git のサブコマンド（{' '.join(rest[:2])}）", FIX_GIT)
        if any(bad_git_arg(sub, a) for a in args):
            d("ファイルへ書き出す・別のプログラムを動かす git のオプション（--output・--ext-diff・--open-files-in-pager とその略記、-O など）",
              "出力はスクリプトでファイルに書き出す")
        return 0
    if is_ps and head in ("pwsh", "pwsh.exe", "powershell", "powershell.exe"):
        i, seen = 1, set()
        while i < len(toks):
            o = toks[i].lower()
            if o in PS_OPTS:
                seen.add(o)
                i += 1
            elif o == "-executionpolicy" and i + 1 < len(toks) and toks[i + 1].lower() in ("bypass", "remotesigned"):
                i += 2
            else:
                break
        if "-noprofile" not in seen or i + 1 >= len(toks) or toks[i].lower() != "-file":
            d("pwsh・powershell の形が `pwsh -NoProfile -File <ファイル> [引数…]` でない（-NoProfile が無い・-Command・-EncodedCommand など）", FIX_FORM)
        check_file(toks[i + 1], "ps1", data, config, d)
        return 0
    d(f"許す形に無いコマンド（{toks[0]}）", FIX_FORM)
    return 0


if __name__ == "__main__":
    sys.exit(hc.guarded_main(HOOK, body))
