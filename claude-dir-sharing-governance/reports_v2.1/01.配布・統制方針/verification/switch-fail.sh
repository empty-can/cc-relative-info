#!/usr/bin/env bash
# ランチャーの Step 3（`git switch <B>` の後に `git reset --hard origin/<B>`。同じ名前 B を渡す）で、
# switch の終了コードを検査せずに reset を続けると、どの場面で
# 「ブランチ名は元のまま、中身が origin/<B> になる」かを測る。足場は $VERIF_ROOT/switchfail。
#
#   場面1 : B がどこにも無い（switch も reset も失敗するはず）
#   場面2 : B にだけある追跡ファイルと同じパスに、手元の未追跡ファイル（ignore されていない）がある
#   場面3 : 場面2 と同じで、手元のファイルが ignore されている
#   場面4 : D/F。手元にローカルブランチ java があり、リモートは java を消して java/design を作った（master にいる）
#   場面4b: 場面4 で、手元のローカルブランチ java にいる
#   参考  : 旧版の形（switch と reset に別の名前を渡す）
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1

verif_fresh_dir switchfail
ROOT="$VERIF_ROOT/switchfail"

# new_env <場面名> [master の .gitignore の内容]: remote.git・maint を作る。master に asset.txt。
# CUR に場面のディレクトリを入れ、そこへ移って戻る。
new_env() {
  CUR="$ROOT/$1"
  mkdir -p "$CUR" || exit 1
  verif_cd "$CUR"
  git init -q --bare remote.git || exit 1
  git clone -q remote.git maint 2>/dev/null || exit 1
  verif_enter_repo "$CUR/maint"
  git config user.email t@example.com; git config user.name t
  git switch -qc master 2>/dev/null || true
  echo "master の資産" > asset.txt
  [ -n "${2:-}" ] && printf '%s\n' "$2" > .gitignore
  git add -A && git commit -qm "master 初版" && git push -q origin master || exit 1
  verif_cd "$CUR"
}

# maint_branch <ブランチ> <追加するファイル> <内容>: maint で master から B を作り push
maint_branch() {
  verif_enter_repo "$CUR/maint"
  git switch -q master && git switch -qc "$1" || exit 1
  echo "$1 の資産" > asset.txt
  printf '%s\n' "$3" > "$2"
  # ignore されているパスでも追跡させる（場面3）
  git add -A && git add -f "$2" && git commit -qm "$1 版" && git push -q origin "$1" || exit 1
  echo "  （maint: $1 が追跡するファイル: $(git ls-files | tr '\n' ' ')）"
  git switch -q master
  verif_cd "$CUR"
}

consumer() {
  git clone -q "$CUR/remote.git" "$CUR/consumer" 2>/dev/null || exit 1
  verif_enter_repo "$CUR/consumer"
}

state() {
  echo "    現在のブランチ: $(git rev-parse --abbrev-ref HEAD)"
  echo "    HEAD         : $(git rev-parse HEAD 2>/dev/null)"
  echo "    origin/$1 : $(git rev-parse --verify -q "origin/$1" || echo '（無い）')"
  echo "    origin/master: $(git rev-parse --verify -q origin/master)"
  echo "    asset.txt    : $(cat asset.txt 2>/dev/null || echo '（無い）')"
  [ -n "${2:-}" ] && echo "    $2: $(cat "$2" 2>/dev/null || echo '（無い）')"
  echo "    status --porcelain --ignored: [$(git status --porcelain --ignored | tr '\n' ' ')]"
}

# launcher <B> [見るファイル]: ランチャーの手順を、終了コードを検査せずに実行する
launcher() {
  local B="$1" head ob cur
  git fetch -q --all --prune 2>&1 | sed 's/^/    fetch: /'
  echo "    fetch --prune の終了コード: ${PIPESTATUS[0]}"
  git switch "$B" 2>&1 | sed 's/^/    switch: /'
  echo "    switch の終了コード: ${PIPESTATUS[0]}"
  git reset --hard "origin/$B" 2>&1 | sed 's/^/    reset: /'
  echo "    reset の終了コード: ${PIPESTATUS[0]}"
  echo "  --- 後:"
  state "$B" "${2:-}"
  head=$(git rev-parse HEAD); ob=$(git rev-parse --verify -q "origin/$B"); cur=$(git rev-parse --abbrev-ref HEAD)
  if [ "$cur" != "$B" ] && [ -n "$ob" ] && [ "$head" = "$ob" ]; then
    echo "  ★ 判定: ブランチ名は $cur のまま、中身が origin/$B になった"
  else
    echo "  判定: 「名前はそのまま中身が origin/$B」にはなっていない（現在 $cur）"
  fi
}

echo "=== 場面1: B がどこにも無い（B=does/not/exist）==="
new_env s1
consumer
echo "  --- 前:"; state does/not/exist
launcher does/not/exist

echo
echo "=== 場面2: B にだけある追跡ファイル extra.md と同じパスに、手元の未追跡ファイル（ignore なし）==="
new_env s2
maint_branch feature extra.md "feature が追跡する extra.md"
consumer
echo "手元の個人ファイル" > extra.md
echo "  --- 前:"; state feature extra.md
launcher feature extra.md

echo
echo "=== 場面3: 場面2 と同じで、手元の extra.md は master の .gitignore で ignore されている ==="
new_env s3 extra.md
maint_branch feature extra.md "feature が追跡する extra.md"
consumer
echo "手元の個人ファイル" > extra.md
echo "  --- 前:"; state feature extra.md
launcher feature extra.md

echo
echo "=== 場面4: D/F（手元にローカルブランチ java、リモートは java を消して java/design を作った。master にいる）==="
new_env s4
maint_branch java java.md "java の資産"
consumer
git switch -q java && git switch -q master || exit 1
echo "  手元のローカルブランチ: [$(git branch --format='%(refname:short)' | tr '\n' ' ')]"
verif_enter_repo "$CUR/maint"
git push -q origin --delete java || exit 1
git branch -q -D java
verif_cd "$CUR"
maint_branch java/design design.md "java/design の資産"
verif_enter_repo "$CUR/consumer"
echo "  --- 前:"; state java/design
launcher java/design
echo "  手元のローカルブランチ: [$(git branch --format='%(refname:short)' | tr '\n' ' ')]"
echo "  リモート追跡ブランチ: [$(git branch -r --format='%(refname:short)' | tr '\n' ' ')]"

echo
echo "=== 場面4b: 場面4 の後、手元のローカルブランチ java に戻ってから同じ手順 ==="
git switch -q java || exit 1
echo "  --- 前:"; state java/design
launcher java/design

echo
echo "=== 参考: 旧版の形（switch does/not/exist の後に reset --hard origin/feature。別の名前）==="
CUR="$ROOT/s2"
verif_enter_repo "$CUR/consumer"
git reset -q --hard origin/master
rm -f extra.md
git switch -q master 2>/dev/null
echo "  --- 前:"; state feature
git switch "does/not/exist" 2>&1 | sed 's/^/    switch: /'
echo "    switch の終了コード: ${PIPESTATUS[0]}"
git reset --hard "origin/feature" 2>&1 | sed 's/^/    reset: /'
echo "    reset の終了コード: ${PIPESTATUS[0]}"
echo "  --- 後:"; state feature
