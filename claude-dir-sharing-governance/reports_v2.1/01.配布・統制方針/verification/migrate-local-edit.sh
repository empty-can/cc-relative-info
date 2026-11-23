#!/usr/bin/env bash
# 本紙 §7-3 の移行で、migrate-submodule.sh が測っていない状態を通す。claude は起動しない。
#   bash migrate-local-edit.sh        足場は $VERIF_ROOT/migrate-local-edit
# 場面:
#   f  通常のディレクトリから移った作業リポを、.claude/ の追跡ファイルを手元で編集していたメンバーが pull する
#   g  submodule から移った作業リポを、submodule の中に手元の変更を持つメンバーが pull し、§7-3 のメンバーの手順に進む
#   h  新しい作業リポジトリ（.claude/ がまだ無い）で、§7-3 の手順 2・4・5・7 を通す
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1
command -v pwsh >/dev/null || verif_die "pwsh が無い"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
LAUNCHER_SRC="$VERIF_LIB_DIR/launcher-example.ps1"

verif_fresh_dir migrate-local-edit
W="$VERIF_ROOT/migrate-local-edit"; verif_cd "$W"; W_W="$(verif_winpath "$W")"
echo "######## migrate-local-edit.sh $(date '+%Y-%m-%d %H:%M:%S %z') ／ $(git --version) ／ pwsh $(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()') ########"

IFS= read -r CLAUDE_LINE <<'EOF'
Write-Output ("[起動] .claude のブランチ=" + (git -C $ClaudeDir rev-parse --abbrev-ref HEAD) + " / git-dir=" + (git -C $ClaudeDir rev-parse --absolute-git-dir))
EOF
put_launcher() {
  awk -v u="\$SharedUrl = \"$W_W/shared.git\"" -v cl="$CLAUDE_LINE" '
    /^\$SharedUrl = / {print u; next}
    $0=="claude @ClaudeArgs" {print cl; next}
    {print}' "$LAUNCHER_SRC" > "$1/start_claude_code.ps1"
  [ "$(diff "$LAUNCHER_SRC" "$1/start_claude_code.ps1" | grep -c '^[<>]')" = 4 ] || verif_die "差し替えが 2 行ではない: $1"
}
run_launcher() {
  echo "  ランチャーを実行:"
  pwsh -NoProfile -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; & '$(verif_winpath "$1")/start_claude_code.ps1'; $VERIF_PS_EXIT" 2>&1 | sed 's/^/    | /'
  echo "    → 終了コード ${PIPESTATUS[0]}"
}
rm_under_root() { local p; for p in "$@"; do [ -e "$p" ] || continue; verif_under_root "$p" || verif_die "外は消さない: $p"; rm -rf "$p"; done; }

git init -q --bare -b main shared.git || verif_die "shared.git"
git clone -q shared.git s 2>/dev/null || verif_die "s"
( verif_enter_repo "$W/s"; printf 'settings.local.json\n' > .gitignore; echo shared > CLAUDE.md && git add -A && git commit -qm s && git push -q origin main ) || verif_die "共有リポ"

echo; echo "=== f: 通常のディレクトリ。メンバー f が .claude/CLAUDE.md（追跡）を手元で編集したまま、移行の commit を pull する"
git init -q --bare -b main workf.git || verif_die "workf"
git clone -q workf.git af 2>/dev/null || verif_die "af"
( verif_enter_repo "$W/af"; mkdir .claude && echo "旧 .claude" > .claude/CLAUDE.md && echo root > CLAUDE.md && git add -A && git commit -qm init && git push -q origin main ) || verif_die "af init"
git clone -q workf.git f 2>/dev/null || verif_die "f"
( verif_enter_repo "$W/f"; echo "f の手元の編集" >> .claude/CLAUDE.md; echo '{"p":1}' > .claude/settings.local.json )
( verif_enter_repo "$W/af"
  mv .claude .claude.bak && git rm -r -q --cached .claude && printf '.claude/\n.claude.bak/\n.claude.old/\n' >> .gitignore && git add .gitignore && git commit -qm "chore: .claude を gitignore" || exit 1
  git clone -q --branch main ../shared.git .claude 2>/dev/null || exit 1
  put_launcher "$W/af"; git add start_claude_code.ps1 && git commit -qm "launcher" && git push -q origin main ) || verif_die "af の移行"
( verif_enter_repo "$W/f"
  git pull -q 2>&1 | sed 's/^/  | /'; echo "  pull=${PIPESTATUS[0]}"
  echo "  pull の後の .claude の中身: [$(cd .claude 2>/dev/null && find . -type f | sort | tr '\n' ' ')]"
  echo "  作業リポの git status --short: [$(git status --short | tr '\n' ' ')]"
  echo "  start_claude_code.ps1: $( [ -f start_claude_code.ps1 ] && echo ある || echo 無い )" )

echo; echo "=== g: submodule。メンバー g が submodule の中の CLAUDE.md を手元で編集したまま、移行の commit を pull する"
git init -q --bare -b main workg.git || verif_die "workg"
git clone -q workg.git ag 2>/dev/null || verif_die "ag"
( verif_enter_repo "$W/ag"; echo root > CLAUDE.md && git add -A && git commit -qm init && git submodule add -q ../shared.git .claude && git commit -qm sub && git push -q origin main ) || verif_die "ag init"
git clone -q --recurse-submodules workg.git g 2>/dev/null || verif_die "g"
( verif_cd "$W/g/.claude"; echo "g の手元の編集" >> CLAUDE.md )
( verif_enter_repo "$W/ag"
  git submodule deinit -q -f .claude && git rm -q -f .claude && rm_under_root .git/modules/.claude && git commit -qm "chore: submodule 解除" || exit 1
  printf '.claude/\n' >> .gitignore && git add .gitignore && git commit -qm "ignore" || exit 1
  git clone -q --branch main ../shared.git .claude 2>/dev/null || exit 1
  put_launcher "$W/ag"; git add start_claude_code.ps1 && git commit -qm "launcher" && git push -q origin main ) || verif_die "ag の移行"
( verif_enter_repo "$W/g"
  git pull -q 2>&1 | sed 's/^/  | /'; echo "  pull=${PIPESTATUS[0]}"
  echo "  .claude/.git: $( [ -f .claude/.git ] && echo "ファイル（$(cat .claude/.git)）" || echo なし )"
  echo "  git -C .claude status --porcelain: [$(git -C .claude status --porcelain 2>&1 | tr '\n' ' ')]"
  echo "  §7-3 は「ローカル変更が無いことを確かめ」とだけ書く。変更があるときの扱いは書かれていない。ランチャーをそのまま実行する:"
  run_launcher "$W/g" )

echo; echo "=== h: 新しい作業リポジトリ（.claude/ が無い）で §7-3 の手順 2・4・5・7"
git init -q -b main h || verif_die "h"
( verif_enter_repo "$W/h"
  echo root > CLAUDE.md && git add -A && git commit -qm init || exit 1
  printf '.claude/\n' > .gitignore && git add .gitignore && git commit -qm "手順 2" ; echo "  手順 2 commit=$?"
  git clone -q --branch main ../shared.git .claude 2>/dev/null; echo "  手順 4 clone=$?"
  put_launcher "$W/h"; git add start_claude_code.ps1 && git commit -qm "手順 5"; echo "  手順 5 commit=$?"
  run_launcher "$W/h"
  echo "  手順 7: 作業リポの git status --short: [$(git status --short | tr '\n' ' ')]" )
echo; echo "######## 終了 ########"
