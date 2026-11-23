# 実測スクリプトの共通部分。各スクリプトの先頭で source する（単独では実行しない）。
#
#   VERIF_ROOT        足場（作業用のリポジトリ）を作る親ディレクトリ。既定 C:/tmp/v21-verif。
#                     C:\tmp の下だけを受け付ける（C:/tmp/<名前>・/c/tmp/<名前>・C:\tmp\<名前>）。
#                     C:\tmp そのもの・.. を含むもの・リンクで C:\tmp の外へ出るものは、何もせずに終了コード 3 で止める。
#                     Git Bash の /tmp は利用者の Temp（C:\Users\…\AppData\Local\Temp）なので、/tmp/… は受け付けない。
#   VERIF_INHERIT_ENV 1 のとき、親プロセスの CLAUDE* 環境変数を引き継いだまま claude を起動する。
#                     既定（未設定・0）では CLAUDE で始まる環境変数をすべて外して起動する。
#   VERIF_KEEP_ENV    外す対象から除く変数名（空白区切り）。認証に要る変数があればここに書く。
#   VERIF_MODEL       claude -p のモデル。既定 haiku。

VERIF_ROOT="${VERIF_ROOT:-C:/tmp/v21-verif}"

# ---- 足場の検査（C:\tmp の下だけ）。ほかの処理より前に、文字列だけで確かめる ----
# verif_guard_tmp <パス>: C:\tmp の下（C:\tmp そのものは不可）で、.. を含まなければ 0。そうでなければ 3。
verif_guard_tmp() {
  local raw="$1" p
  p="${raw//\\//}"; p="${p,,}"
  case "$p" in /c/tmp/*) p="c:/tmp/${p#/c/tmp/}" ;; esac
  while [ "${p%/}" != "$p" ]; do p="${p%/}"; done
  case "$p" in
    *..*) echo "中止: VERIF_ROOT に .. を含めない: $raw" >&2; return 3 ;;
  esac
  case "$p" in
    c:/tmp/?*) ;;
    *) echo "中止: VERIF_ROOT は C:\\tmp の下（例 C:/tmp/<名前>）にする。C:\\tmp そのもの・ほかの場所は不可: $raw" >&2; return 3 ;;
  esac
  case "/${p#c:/tmp/}/" in
    */./*|*//*) echo "中止: VERIF_ROOT に . や空の要素を含めない: $raw" >&2; return 3 ;;
  esac
  return 0
}
# verif_resolved_under_tmp <存在するディレクトリ> [allow_equal]: リンクを解決した後のパスが C:\tmp の下なら 0
verif_resolved_under_tmp() {
  local r
  r="$(cd -P -- "$1" 2>/dev/null && { pwd -W 2>/dev/null || pwd -P; })" || return 1
  r="${r,,}"
  case "$r" in /c/tmp|/c/tmp/*) r="c:/tmp${r#/c/tmp}" ;; esac
  case "$r" in
    c:/tmp/?*) return 0 ;;
    c:/tmp) [ "${2:-}" = allow_equal ] && return 0 ;;
  esac
  return 1
}
verif_guard_tmp "$VERIF_ROOT" || exit 3
VERIF_ROOT="${VERIF_ROOT//\\//}"

VERIF_MODEL="${VERIF_MODEL:-haiku}"
VERIF_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || { echo "中止: lib.sh の場所へ移れません" >&2; exit 1; }

verif_die() { echo "中止: $*" >&2; exit 1; }

# Windows 形式（C:/...）の絶対パスを返す。Git Bash 以外では pwd と同じ。
verif_winpath() { (cd "$1" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); }

# VERIF_ROOT が置いてはいけない場所でないかを確かめ、無ければ作る。
verif_check_root() {
  # 相対パスは、作業ディレクトリ（README の手順ではこのリポジトリの中）の下に解決されるので、mkdir の前に拒否する
  case "$VERIF_ROOT" in
    /*|[A-Za-z]:/*|[A-Za-z]:\\*) ;;
    *) verif_die "VERIF_ROOT は絶対パスで指定する（/ か <ドライブ>:/ で始める）: $VERIF_ROOT" ;;
  esac
  case "$VERIF_ROOT" in
    *AppData/Local/Temp/claude*|*AppData\\Local\\Temp\\claude*)
      verif_die "VERIF_ROOT が scratchpad の下です（プロジェクトの資産がロードされない）: $VERIF_ROOT" ;;
    *cc-relative-info*)
      verif_die "VERIF_ROOT がリポジトリの中です（上位の CLAUDE.md が混ざる）: $VERIF_ROOT" ;;
  esac
  # mkdir の前に、いちばん近い既にある祖先を解決して確かめる（リンクの先に作らないように）
  local anc="$VERIF_ROOT"
  while [ ! -d "$anc" ]; do
    [ "${anc%/*}" != "$anc" ] || break
    anc="${anc%/*}"
  done
  verif_resolved_under_tmp "$anc" allow_equal \
    || { echo "中止: VERIF_ROOT の既にある祖先の解決先が C:\\tmp の外です: $anc" >&2; exit 3; }
  mkdir -p "$VERIF_ROOT" || verif_die "VERIF_ROOT を作れません: $VERIF_ROOT"
  verif_resolved_under_tmp "$VERIF_ROOT" \
    || { echo "中止: VERIF_ROOT の解決先が C:\\tmp の下ではありません: $VERIF_ROOT" >&2; exit 3; }
  VERIF_ROOT_W="$(verif_winpath "$VERIF_ROOT")"
  [ -n "$VERIF_ROOT_W" ] || verif_die "VERIF_ROOT に入れません: $VERIF_ROOT"
  # 解決した後のパスでも確かめる（記号リンクや別名で、文字列の検査をすり抜けないように）
  case "$VERIF_ROOT_W" in
    *AppData/Local/Temp/claude*|*cc-relative-info*)
      verif_die "VERIF_ROOT の解決先が置いてはいけない場所です: $VERIF_ROOT_W" ;;
  esac
  local top
  top="$(git -C "$VERIF_ROOT" rev-parse --show-toplevel 2>/dev/null)" \
    && verif_die "VERIF_ROOT が git リポジトリの中です（$top）。リポジトリの外に置く: $VERIF_ROOT_W"
  return 0
}

# Python の実行ファイル（python が無く python3 だけがある環境に合わせる）
if command -v python >/dev/null 2>&1; then VERIF_PY=python; else VERIF_PY=python3; fi

# PowerShell の -Command でスクリプトを & で呼んだ後に置く終わり方。構文エラーで 1 行も実行されなかったとき
# （$LASTEXITCODE が設定されない）に、終了コード 0 で終わらないようにする。
VERIF_PS_EXIT='$ok = $?; $rc = $LASTEXITCODE; if ($null -eq $rc) { $rc = 1 }; if (-not $ok -and $rc -eq 0) { $rc = 1 }; exit $rc'

# パスが VERIF_ROOT の下にあるかを確かめる（存在するディレクトリに対して使う）。
verif_under_root() {
  local w; w="$(verif_winpath "$1")"
  [ -n "$w" ] || return 1
  case "$w" in "$VERIF_ROOT_W"/*) return 0 ;; *) return 1 ;; esac
}

# VERIF_ROOT の下のディレクトリだけを消して作り直す。
verif_fresh_dir() {
  local d="$VERIF_ROOT/$1"
  case "$1" in ""|/*|*..*) verif_die "足場の名前が不正: $1" ;; esac
  if [ -e "$d" ]; then
    verif_under_root "$d" || verif_die "VERIF_ROOT の外は消さない: $d"
    rm -rf "$d"
  fi
  mkdir -p "$d" || verif_die "作れません: $d"
}

# ディレクトリへ移り、そこが VERIF_ROOT の下にある独立した git リポジトリの
# トップであることを確かめる。書き込み系の git の前に必ず呼ぶ。
#   verif_enter_repo <dir>          作業ツリーのトップ（.git がここにある）
#   verif_enter_repo <dir> bare     bare リポジトリ
verif_enter_repo() {
  cd "$1" || verif_die "cd できません: $1"
  verif_under_root . || verif_die "VERIF_ROOT の外です: $(pwd)"
  local gd
  gd="$(git rev-parse --git-dir 2>/dev/null)" || verif_die "git リポジトリではありません: $(pwd)"
  if [ "${2:-}" = bare ]; then
    [ "$gd" = "." ] || verif_die "bare リポジトリのトップではありません: $(pwd)（git-dir=$gd）"
  else
    # トップにいれば git-dir は ".git"。linked worktree ならファイルの .git が指す先になるので、
    # その場合は show-toplevel が自分自身であることで確かめる。
    if [ "$gd" != ".git" ]; then
      [ -f .git ] || verif_die "独立したリポジトリのトップではありません（親のリポジトリの可能性）: $(pwd)（git-dir=$gd）"
      [ "$(verif_winpath "$(git rev-parse --show-toplevel)")" = "$(verif_winpath .)" ] \
        || verif_die "worktree のトップではありません: $(pwd)"
    fi
  fi
}

# 足場に入る前提のディレクトリ（git リポジトリでなくてよい）へ移る。
verif_cd() {
  cd "$1" || verif_die "cd できません: $1"
  verif_under_root . || verif_die "VERIF_ROOT の外です: $(pwd)"
}

# claude を起動する。既定では CLAUDE* 環境変数を外す。stdin は /dev/null。
# 終了コードを返す（呼び出し側は直後に rc=$? で受ける）。
verif_claude() {
  local -a unset_args=()
  local n
  if [ "${VERIF_INHERIT_ENV:-0}" != 1 ]; then
    for n in $(env | sed -n 's/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p' | sort -u); do
      case " ${VERIF_KEEP_ENV:-} " in *" $n "*) continue ;; esac
      unset_args+=(-u "$n")
    done
  fi
  env "${unset_args[@]}" claude "$@" < /dev/null
}

# 起動の条件を出す。引数はこのセッションで使えるツールの説明（自由文）。
verif_header() {
  local tools="${1:-（指定なし）}" names
  echo "---- 起動の条件 ----"
  if [ "${VERIF_INHERIT_ENV:-0}" = 1 ]; then
    names="$(env | sed -n 's/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p' | sort -u | tr '\n' ' ')"
    echo "  環境変数: 引き継いだ（CLAUDE* の名前: ${names:-なし}）"
  else
    local n
    names=""
    for n in $(env | sed -n 's/^\(CLAUDE[A-Za-z0-9_]*\)=.*/\1/p' | sort -u); do
      case " ${VERIF_KEEP_ENV:-} " in *" $n "*) continue ;; esac
      names="$names$n "
    done
    echo "  環境変数: CLAUDE* を外した（外した名前: ${names:-なし}／残した名前: ${VERIF_KEEP_ENV:-なし}）"
  fi
  echo "  足場（起動ディレクトリ）: $(verif_winpath .)"
  echo "  モデル指定: ${VERIF_CUR_MODEL:-$VERIF_MODEL}"
  echo "  CLI の版: $(claude --version 2>/dev/null < /dev/null)"
  echo "  使えるツール: $tools"
  echo "  時刻: $(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "--------------------"
}

# stream-json を表示用に整形する。
verif_show() { "$VERIF_PY" -I -X utf8"$VERIF_LIB_DIR/stream-show.py" "$@"; }

# claude を stream-json で起動し、生の出力を <出力ファイル> に保存して整形表示する。
# 終了コードは claude 自身の値を VERIF_RC に入れる（パイプの後の $? ではない）。
#   verif_claude_stream <出力ファイル> <claude の引数...>
verif_claude_stream() {
  local out="$1"; shift
  verif_claude "$@" --output-format stream-json --verbose > "$out" 2> "$out.stderr"
  VERIF_RC=$?
  {
    verif_show "$out"
    if [ -s "$out.stderr" ]; then
      echo "  ---- stderr ----"; sed 's/^/  ! /' "$out.stderr"
    fi
    echo "  ---- claude の終了コード: $VERIF_RC"
  } > "$out.show"
  cat "$out.show"
}

# source した時点で VERIF_ROOT を確かめる（呼び忘れで VERIF_ROOT_W が空のまま進まないように）。
verif_check_root
