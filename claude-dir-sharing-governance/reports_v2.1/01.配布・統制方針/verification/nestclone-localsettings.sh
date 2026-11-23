#!/usr/bin/env bash
# V6: 入れ子クローン .claude/ の中に置いた、git が追跡しない .claude/settings.local.json が
# 読まれるか（env・permissions.deny）を、起動する場所ごとに測る。単独で実行できる（足場は自分で作る）。
#
# usage: bash nestclone-localsettings.sh [回数] [場面...]
#   回数   各場面のセッションを何回ずつ起動するか（既定 2）
#   場面   nest-root nest-sub nest-wt nest-sublocal track-root track-sub（既定は全部）
#
# 足場（毎回作り直す）
#   $VERIF_ROOT/nclocal        入れ子クローン。作業リポジトリ work/（.gitignore に .claude/）の .claude/ が
#                              共有リポ shared.git のクローン。共有リポの .gitignore に settings.local.json。
#                              共有の settings.json には env SHAREDPROBE_ENV だけを書く（deny は書かない）。
#                              .claude/settings.local.json（追跡されない）に env LOCALPROBE_ENV と
#                              permissions.deny ["Bash(./denyprobe.sh)"] を書く
#   $VERIF_ROOT/nclocal-track  対照。作業リポジトリが .claude/ を普通に追跡する（settings.json を commit）。
#                              settings.local.json だけを作業リポジトリの .gitignore で外す。中身は上と同じ形
#
# 場面
#   nest-root      入れ子クローンの作業リポジトリのルートから起動
#   nest-sub       サブディレクトリ sub/ から起動（sub/ に .claude/ は無い）
#   nest-wt        作業リポジトリの linked worktree のルートから起動（worktree には .claude/ が無い）
#   nest-sublocal  追加の場面。sub2/.claude/settings.local.json（値 LOCAL-EV-SUB2、deny あり）を置いた sub2/ から起動。
#                  起動したディレクトリの local が読まれるかの陽性の対照（指示の 4 場面とは別）
#   track-root     対照の足場のルートから起動
#   track-sub      対照の足場の sub/ から起動
#
# 各場面で 2 セッション:
#   env : --tools Bash・--allowedTools Bash・--permission-mode default。printenv LOCALPROBE_ENV と
#         printenv SHAREDPROBE_ENV を別々のツール呼び出しで実行させ、ツールの結果（.show の result: 行）で判定する
#   deny: nestclone-lib.sh の nc_deny と同じ（./denyprobe.sh が実行されて denyprobe.out ができたか、permission_denials）
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1
source "$(dirname "$0")/nestclone-lib.sh" || exit 1
# 出力先はほかのスクリプトとぶつからないように自分のものにする（nc_deny はこの変数を使う）
NC_OUTDIR="$VERIF_ROOT/nclocal-stream"
mkdir -p "$NC_OUTDIR" || exit 1

REPEAT="${1:-2}"; shift || true
case "$REPEAT" in ''|*[!0-9]*) verif_die "第 1 引数は回数（数字）" ;; esac
SCENES=("$@")
[ ${#SCENES[@]} -gt 0 ] || SCENES=(nest-root nest-sub nest-wt nest-sublocal track-root track-sub)

NEST="$VERIF_ROOT/nclocal"
TRACK="$VERIF_ROOT/nclocal-track"
WT="$NEST/wt"

NL_ENV_PROMPT='次の 2 つを、それぞれ別の Bash ツール呼び出しで、この文字列のまま順に実行してください。ほかのコマンドは一切実行してはいけません。
1. `printenv LOCALPROBE_ENV`
2. `printenv SHAREDPROBE_ENV`
最後に、1 の出力を `LOCAL=<出力そのまま、出力が無ければ NONE>`、2 の出力を `SHARED=<同じ>` として 2 行だけ出力してください。'

write_local() {  # write_local <ファイル> <env の値>
  cat > "$1" <<EOF
{
  "env": {
    "LOCALPROBE_ENV": "$2"
  },
  "permissions": {
    "deny": ["Bash(./denyprobe.sh)"]
  }
}
EOF
}

write_shared() {  # write_shared <ファイル> <env の値>
  cat > "$1" <<EOF
{
  "env": {
    "SHAREDPROBE_ENV": "$2"
  }
}
EOF
}

write_denyprobe() {  # write_denyprobe <ファイル>
  cat > "$1" <<'EOF'
#!/usr/bin/env bash
# 実行されたら、起動したディレクトリに denyprobe.out を作る（deny が効いたかの判定用）
echo "DENYPROBE-RAN $(date +%s)" > denyprobe.out
echo "DENYPROBE-RAN"
EOF
  chmod +x "$1"
}

# ---------------- 足場: 入れ子クローン ----------------
setup_nest() {
  # 前回の worktree が残っていれば外す（足場ごと消すので、git の登録だけの後始末）
  verif_fresh_dir nclocal
  verif_cd "$NEST"
  git init -q --bare shared.git || verif_die "init に失敗"
  git clone -q shared.git shared 2>/dev/null || verif_die "clone に失敗"
  verif_enter_repo "$NEST/shared"
  git config user.email m@example.com
  git config user.name m
  printf 'settings.local.json\n' > .gitignore
  write_shared settings.json "SHARED-EV-NEST"
  git add -A && git commit -qm "共有 .claude（settings.json と .gitignore）" || verif_die "commit に失敗"
  git push -q origin "$(git rev-parse --abbrev-ref HEAD)" || verif_die "push に失敗"

  verif_cd "$NEST"
  mkdir work || exit 1
  verif_cd "$NEST/work"
  git init -q || verif_die "init に失敗"
  verif_enter_repo "$NEST/work"
  git config user.email w@example.com
  git config user.name w
  printf '.claude/\ndenyprobe.out\n' > .gitignore
  printf 'work repo\n' > README.md
  mkdir -p sub sub2 || exit 1
  write_denyprobe denyprobe.sh
  cp denyprobe.sh sub/denyprobe.sh
  cp denyprobe.sh sub2/denyprobe.sh
  printf 'サブディレクトリ\n' > sub/README.md
  git add -A
  git update-index --chmod=+x denyprobe.sh sub/denyprobe.sh sub2/denyprobe.sh
  git commit -qm "作業リポジトリ初期化（.claude/ は gitignore）" || verif_die "commit に失敗"
  git clone -q ../shared.git .claude 2>/dev/null || verif_die ".claude の clone に失敗"
  write_local .claude/settings.local.json "LOCAL-EV-ROOT"
  # 追加の場面用: sub2/.claude/settings.local.json（作業リポジトリの .gitignore の .claude/ に一致する）
  mkdir -p sub2/.claude || exit 1
  write_local sub2/.claude/settings.local.json "LOCAL-EV-SUB2"

  echo "=== 足場（入れ子クローン）: $(verif_winpath .) ==="
  echo "--- 作業リポジトリの git status --porcelain --ignored ---"
  git status --porcelain --ignored
  echo "--- .claude（共有リポのクローン）の中の git status --porcelain --ignored ---"
  ( verif_enter_repo "$NEST/work/.claude" && git status --porcelain --ignored \
    && echo "  .claude の git-dir: $(git rev-parse --git-dir) ／ ブランチ: $(git rev-parse --abbrev-ref HEAD)" \
    && echo "  git ls-files: $(git ls-files | tr '\n' ' ')" \
    && echo "  check-ignore: $(git check-ignore -v settings.local.json)" )
  echo "--- .claude/settings.json ---"; cat .claude/settings.json
  echo "--- .claude/settings.local.json ---"; cat .claude/settings.local.json
  echo "--- sub/ の中身（.claude/ が無いこと）---"; ls -a sub
  echo "--- sub2/.claude/settings.local.json（追加の場面用）---"; cat sub2/.claude/settings.local.json
  echo
}

# ---------------- 足場: 対照（作業リポジトリが .claude/ を追跡する）----------------
setup_track() {
  verif_fresh_dir nclocal-track
  verif_cd "$TRACK"
  git init -q || verif_die "init に失敗"
  verif_enter_repo "$TRACK"
  git config user.email w@example.com
  git config user.name w
  printf '.claude/settings.local.json\ndenyprobe.out\n' > .gitignore
  printf 'tracked .claude repo\n' > README.md
  mkdir -p sub .claude || exit 1
  write_denyprobe denyprobe.sh
  cp denyprobe.sh sub/denyprobe.sh
  printf 'サブディレクトリ\n' > sub/README.md
  write_shared .claude/settings.json "SHARED-EV-TRACK"
  write_local .claude/settings.local.json "LOCAL-EV-TRACK"
  git add -A
  git update-index --chmod=+x denyprobe.sh sub/denyprobe.sh
  git commit -qm "作業リポジトリ初期化（.claude/ を追跡、settings.local.json だけ gitignore）" || verif_die "commit に失敗"

  echo "=== 足場（対照）: $(verif_winpath .) ==="
  echo "--- git status --porcelain --ignored ---"; git status --porcelain --ignored
  echo "--- git ls-files .claude: $(git ls-files .claude | tr '\n' ' ')"
  echo "--- check-ignore: $(git check-ignore -v .claude/settings.local.json)"
  echo "--- sub/ の中身（.claude/ が無いこと）---"; ls -a sub
  echo
}

# ---------------- linked worktree（入れ子クローンの作業リポジトリ）----------------
remove_wt() {
  [ -d "$NEST/work/.git" ] || return 0
  ( verif_enter_repo "$NEST/work" \
    && { git worktree remove --force "$WT" >/dev/null 2>&1; git branch -q -D wt-probe >/dev/null 2>&1; true; } )
}
add_wt() {
  remove_wt
  ( verif_enter_repo "$NEST/work" && git worktree add -q -b wt-probe "$WT" ) || verif_die "worktree add に失敗"
  trap remove_wt EXIT
  ( verif_enter_repo "$WT" && echo "=== worktree: $(verif_winpath .) の中身（.claude/ があるか）===" && ls -a && echo )
}

# ---------------- セッション ----------------
# 指定したコマンドのツールの結果の行を取り出す。同じ手番で並列に呼ばれると、
# ツール呼び出しの行が先に並び結果の行が後に並ぶので、直後の行ではなく「n 番目の呼び出し ↔ n 番目の結果」で対応させる。
# stream-json の部分だけを見る（セッション記録の「記録 tool:」行は数えない）。
nl_result_of() {  # nl_result_of <.show> <コマンド>
  awk -v cmd="$2" '
    /---- セッション記録/ { exit }
    /^  \[手番[0-9]+\] tool: / { nt++; if (index($0, "\"command\": \"" cmd "\"") && !want) want=nt; next }
    /^ +result:/ && !/result: subtype=/ { nr++; if (nr == want) { sub(/^ +result: */, ""); print; exit } }
  ' "$1"
}

nl_env() {  # nl_env <ラベル>
  local tag="$1" out cmds rl rs
  echo "================ env: $tag ================"
  verif_header "--tools Bash（--allowedTools Bash）／ --permission-mode default"
  echo "  起動ディレクトリの .claude/: $(ls -A .claude 2>/dev/null | tr '\n' ' ' || true)"
  out="$NC_OUTDIR/env-$tag-$(date +%H%M%S).jsonl"
  verif_claude_stream "$out" --model "$VERIF_MODEL" --permission-mode default \
    --tools "Bash" --allowedTools Bash -p "$NL_ENV_PROMPT"
  cmds=$(sed -n 's/^  \[手番[0-9]*\] tool: Bash //p' "$out.show" | tr '\n' ' ')
  rl="$(nl_result_of "$out.show" "printenv LOCALPROBE_ENV")"
  rs="$(nl_result_of "$out.show" "printenv SHAREDPROBE_ENV")"
  echo "  ==== 要約 [env $tag] 実行を指示したコマンド: $cmds" \
       "／ printenv LOCALPROBE_ENV の結果: ${rl:-（呼ばれていない）}" \
       "／ printenv SHAREDPROBE_ENV の結果: ${rs:-（呼ばれていない）}" \
       "／ rc=$VERIF_RC"
  echo
}

run_scene() {  # run_scene <場面> <回目>
  local scene="$1" i="$2" tag="$1-$2"
  echo "######## 場面 $scene（$i 回目）########"
  case "$scene" in
    nest-root)     verif_enter_repo "$NEST/work" ;;
    nest-sub)      verif_enter_repo "$NEST/work"; verif_cd sub ;;
    nest-sublocal) verif_enter_repo "$NEST/work"; verif_cd sub2 ;;
    nest-wt)       verif_enter_repo "$WT" ;;
    track-root)    verif_enter_repo "$TRACK" ;;
    track-sub)     verif_enter_repo "$TRACK"; verif_cd sub ;;
    *) verif_die "場面の名前が不正: $scene" ;;
  esac
  nl_env "$tag"
  nc_deny "$tag"
}

setup_nest
setup_track
for s in "${SCENES[@]}"; do
  [ "$s" = nest-wt ] && { add_wt; break; }
done
for s in "${SCENES[@]}"; do
  for i in $(seq 1 "$REPEAT"); do
    run_scene "$s" "$i"
  done
done
echo "=== 終了 ==="
