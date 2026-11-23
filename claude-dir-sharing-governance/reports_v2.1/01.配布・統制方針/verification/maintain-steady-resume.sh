#!/usr/bin/env bash
# 共有 .claude リポジトリの定常手順（main を更新したとき）: ① 同期 → ② rebase → ③ 検査 → ③' 確認（入力待ち）→ ④ push
# メンテナーのクローンで、bash 4 以降で実行する: bash maintain-steady-resume.sh [resume]
# （選択肢の版）② の衝突を手で解いて git rebase --continue した後は、resume を付けて実行する。
#   resume では ① の fetch と同期を飛ばし、前回の ① で記録した値（.git/steady-old）を期待値に使う。
#   ② は、既に載っているブランチを飛ばす。
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
  || fail "作業ツリーに commit していない変更がある（git status で確かめ、git stash で退避するか変更を捨ててから、もう一度実行する。origin にあるブランチでの commit では片付かない: push していない commit があると ① で止まる）"

# ① fetch し、全ブランチ（main を含む）をローカルで origin に合わせる（resume では飛ばす）
if [ "${1:-}" != resume ]; then
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
fi
declare -A OLD   # rebase 前の値（④ の期待値と、② の --onto の起点）
if [ "${1:-}" = resume ]; then
  [ -f "$gd/steady-old" ] || fail "前回の ① の記録が無い。resume を付けずに実行する"
  source "$gd/steady-old"   # 間に fetch があっても、① の時点の値を使う
else
  for b in "${BRANCHES[@]}"; do
    OLD[$b]=$(git rev-parse -q --verify "refs/remotes/origin/$b") || fail "$b が origin に無い（BRANCHES を直す）"
  done
  declare -p OLD > "$gd/steady-old"
fi
# origin にあって BRANCHES に無いブランチ（main に取り込み済みのものを除く）は、rebase されずに残る。系列の名前（java/… など）なら止め、そのほかは ③' の前に表示する
extra=""; other=""
for b in $(git for-each-ref --format='%(refname:strip=3)' refs/remotes/origin/ | grep -vxF -e HEAD -e main); do
  [ -n "${OLD[$b]+x}" ] && continue
  git merge-base --is-ancestor "origin/$b" origin/main && continue
  case " ${BRANCHES[*]%%/*} " in *" ${b%%/*} "*) extra="$extra $b" ;; *) other="$other $b" ;; esac
done
[ -z "$extra" ] || fail "origin に、BRANCHES に無いブランチがある:$extra（系列のブランチなら BRANCHES・PAIRS・② に足す。PR のブランチは足さず、マージか閉じた後に origin から消す）"

# ② 系列ごとに、末端ブランチ 1 本だけを main へ rebase し、兄弟は載せ直す
git merge-base --is-ancestor main java/design || {
  git switch -q java/design || fail "switch"
  git -c rebase.updateRefs=true rebase main || fail "rebase java/design（衝突なら解いて continue し、resume で実行する）"; }
git merge-base --is-ancestor java/base java/ut || {
  git switch -q java/ut || fail "switch"
  git rebase --onto java/base "${OLD[java/base]}" java/ut || fail "rebase java/ut（衝突なら解いて continue し、resume で実行する）"; }
git merge-base --is-ancestor main python/coding || {
  git switch -q python/coding || fail "switch"
  git -c rebase.updateRefs=true rebase main || fail "rebase python/coding（衝突なら解いて continue し、resume で実行する）"; }

# ③ 取り残しが無いことを検査する（BRANCHES のブランチだけを見る）。④ の直前にもう一度行う
check() {
  for b in "${BRANCHES[@]}"; do
    git merge-base --is-ancestor main "$b" || fail "$b が main を取り込めていない"
  done
  for pair in "${PAIRS[@]}"; do
    set -- $pair
    git merge-base --is-ancestor "$1" "$2" || fail "$2 は $1 を先祖に持たない"
  done
}
check

# ③' push の前に、末端ブランチを §7-2 手順 5 の形で確かめる。ここで入力を待つ
declare -A TIP   # 待つ前の、このクローンでの先頭（push するブランチと、その載せ先の main）。④ の直前に比べる
for b in main "${BRANCHES[@]}"; do TIP[$b]=$(git rev-parse -q --verify "refs/heads/$b"); done
# 載せ直しでブランチから消えるファイル（① の値と比べる）を、あるときだけ表示する（意図した削除と見分けられないので、止めない）
declare -A GONE; names=()
for b in "${BRANCHES[@]}"; do
  while IFS= read -r -d '' f; do [ -n "${GONE[$f]+x}" ] || names+=("$f"); GONE[$f]="${GONE[$f]:-} $b"; done \
    < <(git diff -z --no-renames --name-only --diff-filter=D "${OLD[$b]}" "$b")
done
[ ${#names[@]} -eq 0 ] || echo "注意: この push で、次のファイルがブランチから消える（main で消したものなど）:"
for f in "${names[@]}"; do
  left=""; for b in "${BRANCHES[@]}"; do git cat-file -e "$b:$f" 2>/dev/null && left="$left $b"; done
  echo "  $f（消えるブランチ:${GONE[$f]}）$([ -n "$left" ] && echo "。残るブランチ:$left" || echo "。BRANCHES のどのブランチにも残らない")"
done
[ ${#names[@]} -eq 0 ] || echo "  意図した削除なら、そのまま y でよい。土台へ移す資産で、移す先のブランチに残っていないなら、y で push した後に、移す先の土台へ足し直して push し、土台の手順を実行する。意図していないなら、y を入れずに終える。"
echo "③ の検査に合格した。push する前に、次の末端ブランチを確かめる（§7-2 手順 5）:"
for b in "${BRANCHES[@]}"; do
  printf '%s\n' "${PAIRS[@]}" | grep -q "^$b " || echo "  git clone --branch $b \"$(pwd)\" <検証用のリポジトリ>/.claude"
done
[ -z "$other" ] || echo "参考: origin にある、系列の名前でないブランチ:$other（新しい系列なら、y を入れずに終え、BRANCHES・PAIRS・② に足す）"
echo "確かめたら y を入れて push する。y 以外では push せずに終わる（次の実行の ① がローカルを origin に戻す）。"
read -r -p "push する [y/N]: " ans || ans=""
[ "$ans" = y ] || { echo "push しなかった。" >&2; exit 2; }
moved=""   # 待っている間に、このクローンで動いたブランチ（commit・branch -f・消したもの）
for b in main "${BRANCHES[@]}"; do
  [ "$(git rev-parse -q --verify "refs/heads/$b")" = "${TIP[$b]}" ] || moved="$moved $b"
done
[ -z "$moved" ] || { back=""; for b in $moved; do back="$back git branch -f $b ${TIP[$b]};"; done
  fail "入力を待つ間に、このクローンの次のブランチが動いた:$moved（push は 1 本もしていない。待つ間の変更を確かめ、残すなら控えてから、git switch --detach の後に待つ前の値へ戻し（$back）、このスクリプトをもう一度実行する。resume を付けて実行していたなら、resume を付ける）"; }
check   # 待っている間に祖先関係が崩れていないか（中身の変更は見ない。上の比べを通れば崩れていないが、残す）

# ④ push する（main は含めない。① で記録した値を期待値にし、全部か無しか）
lease=()
for b in "${BRANCHES[@]}"; do lease+=("--force-with-lease=$b:${OLD[$b]}"); done
git push --atomic origin "${lease[@]}" "${BRANCHES[@]}" \
  || fail "push に失敗（拒否されたら、このスクリプトをもう一度実行する）"
echo "push した。"
