#!/usr/bin/env bash
# 【対照】定常手順の前の形（③ でローカルの全ブランチを --no-contains main で数える・③ の後で止まらない・先頭の検査が無い）。maintain-scenes.sh が対照として使う。単独では使わない
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
declare -A OLD   # rebase 前の値（④ の期待値と、② の --onto の起点）
for b in java/base java/design java/ut python/base python/coding; do
  OLD[$b]=$(git rev-parse "refs/remotes/origin/$b") || fail "$b が origin に無い"
done
git switch -q java/design || fail "switch"
git -c rebase.updateRefs=true rebase main || fail "rebase java/design"     # java/base も動く
git switch -q java/ut || fail "switch"
git rebase --onto java/base "${OLD[java/base]}" java/ut || fail "rebase java/ut"
git switch -q python/coding || fail "switch"
git -c rebase.updateRefs=true rebase main || fail "rebase python/coding"   # python/base も動く
nc=$(git branch --no-contains main --format='%(refname:short)')
[ -z "$nc" ] || fail "main を取り込めていない: $nc"
for pair in "main java/base" "java/base java/design" "java/base java/ut" \
            "main python/base" "python/base python/coding"; do
  set -- $pair
  git merge-base --is-ancestor "$1" "$2" || fail "$2 は $1 を先祖に持たない"
done
git push --atomic origin \
  "--force-with-lease=java/base:${OLD[java/base]}" \
  "--force-with-lease=java/design:${OLD[java/design]}" \
  "--force-with-lease=java/ut:${OLD[java/ut]}" \
  "--force-with-lease=python/base:${OLD[python/base]}" \
  "--force-with-lease=python/coding:${OLD[python/coding]}" \
  java/base java/design java/ut python/base python/coding || fail "push に失敗（拒否されたら ① からやり直す）"
