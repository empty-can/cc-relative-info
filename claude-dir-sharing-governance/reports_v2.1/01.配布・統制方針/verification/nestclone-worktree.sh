#!/usr/bin/env bash
# 作業リポジトリの linked worktree から起動したとき、入れ子クローン .claude/ の資産が
# どこまでロードされるか、共有リポの permissions.deny が効くかを測る。
# 作業リポジトリは .claude/ を gitignore しているので、新しい worktree には .claude/ が作られない。
# 先に nestclone-setup.sh（deny の足場）を実行しておくこと。測り方は nestclone-run.sh と同じ。
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1
source "$(dirname "$0")/nestclone-lib.sh" || exit 1

WORK="$VERIF_ROOT/nestclone/work"
WT="$VERIF_ROOT/nestclone/wt"
verif_enter_repo "$WORK"
[ -d .claude/.git ] || verif_die "足場がありません。nestclone-setup.sh を先に実行してください"

remove_wt() {
  ( verif_enter_repo "$WORK" \
    && { git worktree remove --force "$WT" >/dev/null 2>&1; git branch -q -D wt-probe >/dev/null 2>&1; true; } )
}
remove_wt
git worktree add -q -b wt-probe "$WT" || verif_die "worktree add に失敗"
trap remove_wt EXIT

verif_enter_repo "$WT"
echo "=== worktree: $(verif_winpath .) の中身（.claude/ があるか）==="
ls -a
echo

nc_assets "worktree"
nc_deny "worktree"
