#!/usr/bin/env bash
# 【対照】maintain-steady.sh から、push の直前の ③ の再検査（2 回目の check）だけを除いた形。maintain-scenes.sh の S19c で使う
# メンテナーのクローンで、bash 4 以降で実行する: bash maintain-steady.sh
# 自分の共有リポに合わせて書くのは、REPO・URL・BRANCHES・PAIRS と、② の rebase の行である。
REPO='<メンテナーのクローンのパス>'
URL='<共有リポの URL>'
BRANCHES=(java/base java/design java/ut python/base python/coding)   # main 以外の、系列の全ブランチ
PAIRS=("main java/base" "java/base java/design" "java/base java/ut" \
       "main python/base" "python/base python/coding")              # 親 子

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

# ① fetch し、全ブランチ（main を含む）をローカルで origin に合わせる
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
for b in "${BRANCHES[@]}"; do
  OLD[$b]=$(git rev-parse -q --verify "refs/remotes/origin/$b") || fail "$b が origin に無い（BRANCHES を直す）"
done
# origin にあって BRANCHES に無いブランチ（main に取り込み済みのものを除く）は、rebase されずに残る。系列の名前（java/… など）なら止め、そのほかは ③' の前に表示する
extra=""; other=""
for b in $(git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin/ | grep -vxF -e HEAD -e main); do
  [ -n "${OLD[$b]+x}" ] && continue
  git merge-base --is-ancestor "origin/$b" origin/main && continue
  case " ${BRANCHES[*]%%/*} " in *" ${b%%/*} "*) extra="$extra $b" ;; *) other="$other $b" ;; esac
done
[ -z "$extra" ] || fail "origin に、BRANCHES に無いブランチがある:$extra（系列のブランチなら BRANCHES・PAIRS・② に足す。PR のブランチは足さず、マージか閉じた後に origin から消す）"

# ② 系列ごとに、末端ブランチ 1 本だけを main へ rebase し、兄弟は載せ直す
git switch -q java/design || fail "switch"
git -c rebase.updateRefs=true rebase main || fail "rebase java/design（衝突なら git rebase --abort で戻す）"   # java/base も動く
git switch -q java/ut || fail "switch"
git rebase --onto java/base "${OLD[java/base]}" java/ut || fail "rebase java/ut（衝突なら git rebase --abort で戻す）"
git switch -q python/coding || fail "switch"
git -c rebase.updateRefs=true rebase main || fail "rebase python/coding（衝突なら git rebase --abort で戻す）"   # python/base も動く

# ③ 取り残しが無いことを検査する（BRANCHES のブランチだけを見る）
for b in "${BRANCHES[@]}"; do
  git merge-base --is-ancestor main "$b" || fail "$b が main を取り込めていない"
done
for pair in "${PAIRS[@]}"; do
  set -- $pair
  git merge-base --is-ancestor "$1" "$2" || fail "$2 は $1 を先祖に持たない"
done

# ③' push の前に、末端ブランチを §7-2 手順 5 の形で確かめる。ここで入力を待つ
echo "③ の検査に合格した。push する前に、次の末端ブランチを確かめる（§7-2 手順 5）:"
for b in "${BRANCHES[@]}"; do
  printf '%s\n' "${PAIRS[@]}" | grep -q "^$b " || echo "  git clone --branch $b \"$(pwd)\" <検証用のリポジトリ>/.claude"
done
[ -z "$other" ] || echo "参考: origin にある、系列の名前でないブランチ:$other（新しい系列なら、y を入れずに終え、BRANCHES・PAIRS・② に足す）"
echo "確かめたら y を入れて push する。y 以外では push せずに終わる（次の実行の ① がローカルを origin に戻す）。"
read -r -p "push する [y/N]: " ans || ans=""
[ "$ans" = y ] || { echo "push しなかった。" >&2; exit 2; }

# ④ push する（main は含めない。① で記録した値を期待値にし、全部か無しか）
lease=()
for b in "${BRANCHES[@]}"; do lease+=("--force-with-lease=$b:${OLD[$b]}"); done
git push --atomic origin "${lease[@]}" "${BRANCHES[@]}" \
  || fail "push に失敗（拒否されたら、このスクリプトをもう一度実行する）"
echo "push した。"
