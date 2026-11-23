#!/usr/bin/env bash
# 本紙 §7-2 手順 2・3: main にある資産を、作業種別ブランチへ移す順序。claude は起動しない。
#   誤った順序: main からブランチを切り、ブランチで別の資産を足した後に、main から資産を外す（PR）→ §5-4 の rebase
#               → 外した資産がブランチからも消える（エラーにも衝突にもならない）
#   正しい順序: 先に main から外す（PR）→ origin/main から --no-track で切り、外す前のコミットから資産を足し直して commit・push
#               → main にもう 1 コミット足してから §5-4 の rebase → 資産はブランチに残る
# 足場は $VERIF_ROOT/maintain-move（wrong・right）。
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1

verif_fresh_dir maintain-move
W="$VERIF_ROOT/maintain-move"
rules_of() { git ls-tree --name-only "$1" rules/ | tr '\n' ' '; }

echo "===== 誤った順序: main からブランチを切った後に、main から資産を外す"
(
  verif_cd "$W"
  git init -q -b main wrong || verif_die "init"
  verif_enter_repo "$W/wrong"
  mkdir rules && echo common > CLAUDE.md && echo "java だけで要る" > rules/java.md && echo "共通" > rules/common.md
  git add -A && git commit -qm "main: 共通資産" || verif_die "commit"
  git switch -qc java/base main || verif_die "switch"
  echo "java の別の rule" > rules/java2.md && git add -A && git commit -qm "java/base: rule を足す" || verif_die "commit"
  git switch -q main && git rm -q rules/java.md && git commit -qm "main: java 専用の rule を外す（PR）" || verif_die "commit"
  echo "  rebase 前の java/base: rules=[$(rules_of java/base)]"
  git switch -q java/base || verif_die "switch"
  git -c rebase.updateRefs=true rebase main 2>&1 | sed 's/^/  /'; echo "  rebase の終了コード: ${PIPESTATUS[0]}"
  echo "  rebase 後の java/base: rules=[$(rules_of java/base)]"
)

echo "===== 正しい順序: 先に main から外し、origin/main から切って足し直す"
(
  verif_cd "$W"
  git init -q --bare -b main shared.git || verif_die "init"
  git clone -q shared.git right 2>/dev/null || verif_die "clone"
  verif_enter_repo "$W/right"
  [ "$(git symbolic-ref --short HEAD)" = main ] || verif_die "right のブランチが main ではない"
  mkdir rules && echo common > CLAUDE.md && echo "java だけで要る" > rules/java.md && echo "共通" > rules/common.md
  git add -A && git commit -qm "main: 共通資産" && git push -q origin main || verif_die "commit"
  KEEP=$(git rev-parse HEAD)
  # (1) 先に main から外す（PR に当たる）
  git rm -q rules/java.md && git commit -qm "main: java 専用の rule を外す（PR）" && git push -q origin main || verif_die "PR"
  # (2) 外した後の origin/main から切り、外したファイルをブランチのコミットとして足し直す
  git fetch -q origin || verif_die "fetch"
  git switch -qc java/base --no-track origin/main || verif_die "switch"
  git checkout -q "$KEEP" -- rules/java.md && git commit -qm "java/base: java の rule を置く" || verif_die "commit"
  git push -q -u origin java/base || verif_die "push"
  echo "  足し直した後の java/base: rules=[$(rules_of java/base)]"
  # main にもう 1 コミット足してから rebase する（rebase が実際に動くように）
  git switch -q main && git pull -q --ff-only && echo "main 追記" >> CLAUDE.md && git commit -qam "main: 追記（PR）" && git push -q origin main || verif_die "main"
  git switch -q java/base || verif_die "switch"
  git -c rebase.updateRefs=true rebase main 2>&1 | sed 's/^/  /'; echo "  rebase の終了コード: ${PIPESTATUS[0]}"
  echo "  rebase 後の java/base: rules=[$(rules_of java/base)] ／ main の追記: $(git show java/base:CLAUDE.md | grep -c 'main 追記') 件"
)
