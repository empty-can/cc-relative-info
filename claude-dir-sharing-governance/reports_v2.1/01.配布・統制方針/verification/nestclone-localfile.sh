#!/usr/bin/env bash
# メンバーの手元の .claude/settings.local.json が、ランチャーの `git switch <B>` と
# `git reset --hard origin/<B>` の後に残るかを、条件を分けて測る。足場は $VERIF_ROOT/localfile。
#
#   (i)   共有リポの .gitignore に settings.local.json がある（どのブランチでも追跡されていない）
#   (ii)  .gitignore に無い（未追跡・ignore されていない）
#   (iii) あるブランチ tracked で settings.local.json が追跡されている
#         (iii-a) 手元のファイルは ignore されている  (iii-b) ignore されていない
#   (iv)  git status --porcelain と git clean -fd・-fdx が、未追跡のディレクトリ worktrees/・agent-memory/ と
#         ignore された settings.local.json の何を消すか
# 各段で、終了コード（PIPESTATUS）・現在のブランチ・ファイルの中身を出す。
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1

verif_fresh_dir localfile
ROOT="$VERIF_ROOT/localfile"

# new_shared <名前> <ignore する: yes|no>
#   master: CLAUDE.md（＋ .gitignore）／ other: master から CLAUDE.md を変更／
#   tracked: master から settings.local.json を追跡（中身 "BRANCH"）
new_shared() {
  CUR="$ROOT/$1"
  mkdir -p "$CUR" || exit 1
  verif_cd "$CUR"
  git init -q --bare shared.git || exit 1
  git clone -q shared.git maint 2>/dev/null || exit 1
  verif_enter_repo "$CUR/maint"
  git config user.email m@example.com; git config user.name m
  git switch -qc master 2>/dev/null || true
  echo "master の CLAUDE.md" > CLAUDE.md
  [ "$2" = yes ] && printf 'settings.local.json\n' > .gitignore
  git add -A && git commit -qm "master" && git push -q origin master || exit 1
  git switch -qc other || exit 1
  echo "other の CLAUDE.md" > CLAUDE.md
  git add -A && git commit -qm "other" && git push -q origin other || exit 1
  git switch -q master && git switch -qc tracked || exit 1
  echo '{ "env": { "FROM": "BRANCH" } }' > settings.local.json
  git add -f settings.local.json && git commit -qm "tracked: settings.local.json を追跡" && git push -q origin tracked || exit 1
  git switch -q master
  verif_cd "$CUR"
}

member() {
  case "$1" in ""|/*|*..*) verif_die "クローンの名前が不正: $1" ;; esac
  if [ -e "$CUR/$1" ]; then
    verif_under_root "$CUR/$1" || verif_die "VERIF_ROOT の外は消さない: $CUR/$1"
    rm -rf "$CUR/$1"
  fi
  git clone -q "$CUR/shared.git" "$CUR/$1" 2>/dev/null || exit 1
  verif_enter_repo "$CUR/$1"
  echo '{ "env": { "FROM": "PERSONAL" } }' > settings.local.json
}

show() {
  echo "      ブランチ=$(git rev-parse --abbrev-ref HEAD) HEAD=$(git rev-parse --short HEAD) CLAUDE.md=[$(cat CLAUDE.md 2>/dev/null)]"
  echo "      settings.local.json=[$(cat settings.local.json 2>/dev/null || echo '★無い★')]"
  echo "      status --porcelain=[$(git status --porcelain | tr '\n' ' ')] --ignored=[$(git status --porcelain --ignored | grep '^!!' | tr '\n' ' ')]"
}

step() {   # step <説明> <git の引数...>
  local d="$1"; shift
  echo "    \$ git $*   （$d）"
  git "$@" 2>&1 | sed 's/^/      | /'
  echo "      終了コード: ${PIPESTATUS[0]}"
  show
}

launcher() {  # ランチャーの手順（終了コードを検査しない）
  step "fetch" fetch -q --all --prune
  step "switch" switch "$1"
  step "reset" reset --hard "origin/$1"
}

echo "=== (i) .gitignore に settings.local.json がある。メンバーが other へ切り替える ==="
new_shared ign yes
member m1
echo "  前:"; show
launcher other
echo "  master へ戻る:"
launcher master

echo
echo "=== (ii) .gitignore に無い（未追跡・ignore されていない）。メンバーが other へ切り替える ==="
new_shared noign no
member m1
echo "  前:"; show
launcher other
echo "  master へ戻る:"
launcher master

echo
echo "=== (iii-a) ブランチ tracked が settings.local.json を追跡。手元のファイルは ignore されている ==="
CUR="$ROOT/ign"
member m2
echo "  前:"; show
launcher tracked
echo "  master へ戻る（tracked では追跡、master では ignore）:"
launcher master

echo
echo "=== (iii-b) ブランチ tracked が settings.local.json を追跡。手元のファイルは ignore されていない ==="
CUR="$ROOT/noign"
member m2
echo "  前:"; show
launcher tracked
echo "  master へ戻る:"
launcher master

echo
echo "=== (iv) git status --porcelain と git clean（(i) の足場。worktrees/・agent-memory/ は未追跡）==="
CUR="$ROOT/ign"
member m3
mkdir -p worktrees/x agent-memory || exit 1
echo wt > worktrees/x/file; echo mem > agent-memory/MEMORY.md
echo "  前:"; show
echo "    git status --porcelain:"; git status --porcelain | sed 's/^/      | /'
echo "    git status --porcelain --ignored:"; git status --porcelain --ignored | sed 's/^/      | /'
echo "    git clean -n -fd（消す予定の一覧）:"; git clean -n -fd | sed 's/^/      | /'
step "clean -fd" clean -fd
echo "      残ったもの: [$(ls -A | tr '\n' ' ')]"
mkdir -p worktrees/x agent-memory || exit 1
echo wt > worktrees/x/file; echo mem > agent-memory/MEMORY.md
echo "    git clean -n -fdx（消す予定の一覧）:"; git clean -n -fdx | sed 's/^/      | /'
step "clean -fdx" clean -fdx
echo "      残ったもの: [$(ls -A | tr '\n' ' ')]"
