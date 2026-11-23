#!/usr/bin/env bash
# 共有 .claude リポジトリの手順（中間ブランチ java/base だけを更新したとき）: 子だけを載せ直し、子だけを push する
# メンテナーのクローンで、bash 4 以降で実行する: bash maintain-middle.sh
# 前提: java/base は早送りで進んだだけ（amend や rebase で書き換えていない）。書き換えたときは定常手順と同じく --onto が要る。
# 自分の共有リポに合わせて書くのは、REPO・URL・BRANCHES・PARENT・CHILDREN である。
REPO='<メンテナーのクローンのパス>'
URL='<共有リポの URL>'
BRANCHES=(java/base java/design java/ut python/base python/coding)   # main 以外の、系列の全ブランチ（定常手順と同じ）
PARENT=java/base
CHILDREN=(java/design java/ut)                                     # PARENT の子（載せ直して push するもの）

[ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || { echo "中断: bash 4 以降で実行する（今は ${BASH_VERSION:-bash 以外}）" >&2; exit 1; }
fail() { echo "中断: $*" >&2; exit 1; }
cd "$REPO" || fail "$REPO へ移れない"
[ "$(git remote get-url origin 2>/dev/null)" = "$URL" ] || fail "$REPO の origin が $URL ではない"
[ -z "$(git rev-parse --show-prefix)" ] || fail "$REPO がクローンのトップではない"
gd=$(git rev-parse --git-dir)
[ ! -d "$gd/rebase-merge" ] && [ ! -d "$gd/rebase-apply" ] \
  || fail "rebase の途中で止まっている。git rebase --abort で戻してから実行する"
[ -z "$(git status --porcelain --untracked-files=no)" ] \
  || fail "作業ツリーに commit していない変更がある（git status で確かめ、commit か git stash で片付ける）"

# ① 定常手順の ① の同期と同じ（BRANCHES に無いブランチの検査は行わない）
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
for b in "${BRANCHES[@]}"; do
  OLD[$b]=$(git rev-parse -q --verify "refs/remotes/origin/$b") || fail "$b が origin に無い（BRANCHES を直す）"
done

# ② 子を親の上へ載せ直す（親は早送りで進んだだけなので、素の rebase で足りる）
for b in "${CHILDREN[@]}"; do
  git switch -q "$b" || fail "switch $b"
  git rebase "$PARENT" || fail "rebase $b（衝突なら git rebase --abort で戻す）"
done

# ③ 検査（子だけを見る。main も進んでいるときは、この手順の後に定常手順を実行する）。④ の直前にもう一度行う
check() {
  for b in "${CHILDREN[@]}"; do
    git merge-base --is-ancestor "$PARENT" "$b" || fail "$b が $PARENT を取り込めていない"
  done
}
check

# ③' 確認（入力待ち）
echo "③ の検査に合格した。push する前に、次のブランチを確かめる（§7-2 手順 5）:"
for b in "${CHILDREN[@]}"; do echo "  git clone --branch $b \"$(pwd)\" <検証用のリポジトリ>/.claude"; done
echo "確かめたら y を入れて push する。y 以外では push せずに終わる（次の実行の ① がローカルを origin に戻す）。"
read -r -p "push する [y/N]: " ans || ans=""
[ "$ans" = y ] || { echo "push しなかった。" >&2; exit 2; }
check   # 待っている間に祖先関係が崩れていないか（中身の変更は見ない）

# ④ 動かした子だけを push する
lease=()
for b in "${CHILDREN[@]}"; do lease+=("--force-with-lease=$b:${OLD[$b]}"); done
git push --atomic origin "${lease[@]}" "${CHILDREN[@]}" \
  || fail "push に失敗（拒否されたら、このスクリプトをもう一度実行する）"
echo "push した。"
