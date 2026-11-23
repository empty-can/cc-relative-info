#!/usr/bin/env bash
# §5-4 の足場: 共有リポ（bare）に main → java/base → {java/design, java/ut}、main → python/base → python/coding。
# メンテナーのクローン m・m2 を作り（全ブランチをローカルに持つ。この時点の値）、
# その後に PR のマージに当たる操作で origin の main だけを進める（m・m2 のローカルの main は古いまま）。
# 足場は $VERIF_ROOT/<名前>（既定 maintain）。claude は起動しない。
#   bash maintain-setup.sh [名前]
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1

NAME="${1:-maintain}"
verif_fresh_dir "$NAME"
W="$VERIF_ROOT/$NAME"

verif_cd "$W"
git init -q --bare -b main shared.git || verif_die "bare リポジトリを作れない"
git clone -q shared.git seed 2>/dev/null || verif_die "clone に失敗"
verif_enter_repo "$W/seed"
[ "$(git symbolic-ref --short HEAD)" = main ] || verif_die "seed のブランチが main ではない"
c() { mkdir -p "$(dirname "$1")" && echo "$2" > "$1" && git add -A && git commit -qm "$3" || verif_die "commit に失敗: $3"; }
c CLAUDE.md "main 初版" "main: 初版"
git push -q origin main || verif_die "push に失敗"
git switch -qc java/base main             || verif_die "switch"; c rules/java.md   "java 共通" "java/base: java 共通 rule"
git switch -qc java/design java/base      || verif_die "switch"; c rules/design.md "設計"      "java/design: 設計 rule"
git switch -qc java/ut java/base          || verif_die "switch"; c rules/ut.md     "UT"        "java/ut: UT rule"
git switch -qc python/base main           || verif_die "switch"; c rules/python.md "py 共通"   "python/base: py 共通 rule"
git switch -qc python/coding python/base  || verif_die "switch"; c rules/coding.md "py 実装"   "python/coding: 実装 rule"
git push -q origin java/base java/design java/ut python/base python/coding || verif_die "push に失敗"

# メンテナー m と m2 のクローン（全ブランチをローカルに持つ。ただしこの時点の値）
for who in m m2; do
  verif_cd "$W"
  git clone -q shared.git "$who" || verif_die "clone に失敗: $who"
  verif_enter_repo "$W/$who"
  for b in java/base java/design java/ut python/base python/coding; do
    git branch -q --track "$b" "origin/$b" || verif_die "$who: $b を作れない"
  done
done

# PR のマージに当たる操作: 別のクローンから main を進める（m・m2 のローカルの main は古いまま）
verif_cd "$W"
git clone -q shared.git pr || verif_die "clone に失敗: pr"
verif_enter_repo "$W/pr"
echo "main 追記（PR #1）" >> CLAUDE.md && git commit -qam "main: PR #1 で追記" && git push -q origin main || verif_die "PR #1 に失敗"

verif_enter_repo "$W/shared.git" bare
echo "=== 足場（origin）==="
git log --oneline --graph --all --decorate
echo "=== m のローカル main（古い）: $(git -C "$W/m" log --oneline -1 main)"
