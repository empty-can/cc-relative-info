# 足場の場所の検査（bash 用）。足場を使うスクリプトの冒頭で source し、C:\tmp の下で動いていることを保証する。
#
# 確かめるもの: 今の作業フォルダ（$PWD）と、環境変数 VERIF_ROOT があればその値と、
# `source guard_tmp.sh --paths <パス>...` で渡したパス。
# どれも、\ を / にし、realpath -m で .. とシンボリックリンクを解決し、/c/tmp・C:/tmp・C:\tmp の書き方をそろえたうえで、
# C:\tmp そのものではなく、その下にあることを確かめる。外なら stderr に文を出し、終了コード 3 で終わる（source 元ごと止まる）。
#
# 使い方（スクリプトの冒頭。<リポジトリ> は依頼文のリポジトリの絶対パス）:
#   VERIF_ROOT=C:/tmp/<名前>
#   cd "$VERIF_ROOT" || exit 3
#   source "<リポジトリ>/.claude/skills/cross-review/scripts/guard_tmp.sh" || exit 3

_guard_tmp_canon() {
  local p="${1//\\//}" r
  case "$p" in
    [A-Za-z]:/*) p="/${p:0:1}${p:2}" ;;
    [A-Za-z]:) p="/${p:0:1}" ;;
  esac
  r="$(realpath -m -- "$p" 2>/dev/null)" || r="$p"
  r="${r%/}"
  printf '%s' "${r,,}"
}

_guard_tmp_main() {
  local p c bad=0 paths=("$PWD")
  [ -n "${VERIF_ROOT:-}" ] && paths+=("$VERIF_ROOT")
  # source に引数を付けないと、呼んだスクリプトの引数がそのまま見えるので、--paths を付けたときだけ足す
  if [ "${1:-}" = "--paths" ]; then
    shift
    for p in "$@"; do paths+=("$p"); done
  fi
  for p in "${paths[@]}"; do
    c="$(_guard_tmp_canon "$p")"
    case "$c" in
      /c/tmp/?*) ;;
      *)
        printf '[guard_tmp] 足場（C:\\tmp\\<名前>）の外で動こうとしたので止めた: %s → %s\n' "$p" "$c" >&2
        bad=1 ;;
    esac
  done
  if [ "$bad" -ne 0 ]; then
    printf '%s\n' '直し方: 足場は `python -I -X utf8 .claude/skills/cross-review/scripts/scaffold.py make <名前>` で作り、スクリプトは冒頭で cd してから guard_tmp.sh を source する。C:\tmp そのもの・リポジトリの中では動かさない' >&2
    exit 3
  fi
}

_guard_tmp_main "$@"
