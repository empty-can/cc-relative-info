#!/usr/bin/env bash
# 【対照】中間ブランチだけを更新したときの手順の前の形（③ で java/* の全ローカルブランチを --no-contains java/base で数える）。maintain-scenes.sh が対照として使う
cd "<共有リポのパス>" || exit 1
fail() { echo "中断: $*" >&2; exit 1; }
git fetch --prune origin || fail "fetch に失敗"
git switch -q --detach origin/main || fail "detach に失敗"
for b in $(git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin/ | grep -vx HEAD); do
  if git show-ref --verify -q "refs/heads/$b"; then
    uniq=$(git cherry "refs/remotes/origin/$b" "refs/heads/$b" refs/remotes/origin/main | grep '^+')
    [ -z "$uniq" ] || fail "ローカルの $b に、origin に無い変更がある: $uniq"
    git branch -q -f "$b" "origin/$b" || fail "$b を origin に合わせられない"
  else
    git branch -q --track "$b" "origin/$b" || fail "$b を作れない"
  fi
done
declare -A OLD
for b in java/design java/ut; do
  OLD[$b]=$(git rev-parse "refs/remotes/origin/$b") || fail "$b が origin に無い"
done
git switch -q java/design || fail "switch"; git rebase java/base || fail "rebase java/design"
git switch -q java/ut || fail "switch"; git rebase java/base || fail "rebase java/ut"
nc=$(git branch --no-contains main --format='%(refname:short)')
[ -z "$nc" ] || fail "main を取り込めていない: $nc"
for pair in "main java/base" "java/base java/design" "java/base java/ut" \
            "main python/base" "python/base python/coding"; do
  set -- $pair
  git merge-base --is-ancestor "$1" "$2" || fail "$2 は $1 を先祖に持たない"
done
nc=$(git branch --list 'java/*' --no-contains java/base --format='%(refname:short)')
[ -z "$nc" ] || fail "java/base を取り込めていない: $nc"
git push --atomic origin \
  "--force-with-lease=java/design:${OLD[java/design]}" \
  "--force-with-lease=java/ut:${OLD[java/ut]}" \
  java/design java/ut || fail "push に失敗（拒否されたら ① からやり直す）"
