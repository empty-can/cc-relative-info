#!/usr/bin/env bash
# 本紙 §5-4 の定常手順の対照。誤った手順が、定常手順の検査（③）や lease でどう見えるかを測る。claude は起動しない。
#   (a) 兄弟の末端ブランチ（java/design・java/ut）を、それぞれ rebase main する。間に 2 秒待つ
#   (b) (a) と同じ操作を、待たずに行う（同じ秒の中で済むと、誤りが隠れることがある）
#   (c) 期待値を付けた --force-with-lease が、① の後に別のメンテナーが push した変更で拒否されること。
#       参考として、値を付けない --force-with-lease は、直前に fetch していれば他のメンテナーの変更を消すこと
# 各場面で maintain-setup.sh を呼んで足場を作り直す（$VERIF_ROOT/maintain-ca・-cb・-cc）。
# (a)(b) は python 系列の rebase を省くので、--no-contains main に python/base・python/coding が出る（所見ではない）。
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1
S="$(cd "$(dirname "$0")" && pwd)" || verif_die "スクリプトの場所へ移れません"

# 全ブランチ（main を含む）をローカルで origin に合わせる（ガードは省く。足場の m は手を加えていない）
sync_local() {
  git fetch -q --prune origin || verif_die "fetch"
  git switch -q --detach origin/main || verif_die "detach"
  for b in main java/base java/design java/ut python/base python/coding; do
    git branch -q -f "$b" "origin/$b" || verif_die "$b"
  done
}

naive() { # $1=足場の名前 $2=待ち秒
  bash "$S/maintain-setup.sh" "$1" > /dev/null 2>&1 || verif_die "足場を作れない: $1"
  (
    verif_enter_repo "$VERIF_ROOT/$1/m"
    sync_local
    git switch -q java/design && git -c rebase.updateRefs=true rebase main > /dev/null 2>&1
    echo "  java/design の rebase の終了コード: $?"
    sleep "$2"
    git switch -q java/ut && git -c rebase.updateRefs=true rebase main > /dev/null 2>&1
    echo "  java/ut の rebase の終了コード: $?"
    echo "  --no-contains main: [$(git branch --no-contains main --format='%(refname:short)' | tr '\n' ' ')]"
    if git merge-base --is-ancestor java/base java/ut; then echo "  java/base ⊂ java/ut: YES"; else echo "  java/base ⊂ java/ut: NO"; fi
    git log --oneline --graph --decorate java/design java/ut | sed 's/^/  /'
  )
}

echo "===== (a) 兄弟の末端ブランチを、それぞれ rebase main。間に 2 秒待つ"
naive maintain-ca 2
echo "===== (b) 同じ操作を待たずに行う"
naive maintain-cb 0

echo "===== (c) lease の拒否: m が fetch した後に、別のメンテナーが java/ut を push した"
bash "$S/maintain-setup.sh" maintain-cc > /dev/null 2>&1 || verif_die "足場を作れない: maintain-cc"
W="$VERIF_ROOT/maintain-cc"
( verif_cd "$W"; git clone -q shared.git other ) || verif_die "clone に失敗: other"
# m は割り込みの前に fetch を済ませ、その値で手順の②〜④を行う（① の後、④ の前に割り込まれたのと同じ状況）
( verif_enter_repo "$W/m"; git fetch -q --prune origin ) || verif_die "m: fetch"
( verif_enter_repo "$W/other"
  git switch -q java/ut && echo "他メンテナーの追記" >> rules/ut.md \
    && git commit -qam "java/ut: 他メンテナーの追記" && git push -q origin java/ut || verif_die "other: push"
  echo "  （他のメンテナーが java/ut を $(git rev-parse --short HEAD) へ進めた）" )
(
  verif_enter_repo "$W/m"
  git switch -q --detach origin/main || verif_die "detach"
  for b in main java/base java/design java/ut python/base python/coding; do git branch -q -f "$b" "origin/$b" || verif_die "$b"; done
  declare -A OLD
  for b in java/base java/design java/ut python/base python/coding; do OLD[$b]=$(git rev-parse "origin/$b"); done
  git switch -q java/design && git -c rebase.updateRefs=true rebase main > /dev/null 2>&1 || verif_die "rebase java/design"
  git switch -q java/ut && git rebase -q --onto java/base "${OLD[java/base]}" java/ut || verif_die "rebase java/ut"
  git switch -q python/coding && git -c rebase.updateRefs=true rebase main > /dev/null 2>&1 || verif_die "rebase python/coding"
  git push --atomic origin \
    "--force-with-lease=java/base:${OLD[java/base]}" "--force-with-lease=java/design:${OLD[java/design]}" \
    "--force-with-lease=java/ut:${OLD[java/ut]}" "--force-with-lease=python/base:${OLD[python/base]}" \
    "--force-with-lease=python/coding:${OLD[python/coding]}" \
    java/base java/design java/ut python/base python/coding 2>&1 | sed 's/^/  /'
  echo "  push の終了コード: ${PIPESTATUS[0]}"
  echo "  origin の java/base（動いていなければ --atomic が効いている）: $(git -C "$W/shared.git" rev-parse --short java/base) ／ OLD=${OLD[java/base]:0:7}"
  echo "  参考: 値を付けない --force-with-lease で java/ut を push する（直前に fetch して origin/java/ut を更新した場合）"
  git fetch -q origin
  git push --force-with-lease origin java/ut 2>&1 | sed 's/^/  /'
  echo "  push の終了コード: ${PIPESTATUS[0]}"
  echo "  → 他のメンテナーの追記は origin の java/ut に残ったか: $(git -C "$W/shared.git" log --oneline java/ut | grep -c '他メンテナー') 件"
)
