#!/usr/bin/env bash
# rebase.updateRefs が「中間ブランチも一括で更新する」ことを実際に働かせて確認する。
# あわせて、pull --ff-only が失敗した状態から reset --hard で復旧できることを確認する。
set -uo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)/nestclone"
cd "$BASE/shared"

git switch -q master
printf '\n追記3: 合言葉 **NESTCLONE-M3-7709**。\n' >> CLAUDE.md
git add -A && git commit -qm "master にさらに追記（多段伝播の起点）"
git push -q origin master

echo "=== rebase 前（java/_base と java/design は古い master の上）==="
git log --oneline --graph --all --decorate | head -12

echo
echo "=== git -c rebase.updateRefs=true rebase master（java/design で1回だけ実行）==="
git switch -q java/design
git -c rebase.updateRefs=true rebase master 2>&1 | sed 's/^/    /'

echo
echo "=== rebase 後：中間ブランチ java/_base も一緒に動いたか ==="
git log --oneline --graph --all --decorate | head -12
echo "    java/_base が master を先祖に持つ: $(git merge-base --is-ancestor master java/_base && echo YES || echo NO)"
echo "    java/design が java/_base を先祖に持つ: $(git merge-base --is-ancestor java/_base java/design && echo YES || echo NO)"

git push -q --force origin master "java/_base" "java/design"

echo
echo "=== 消費側: pull --ff-only 失敗 → reset --hard で復旧できるか ==="
cd "$BASE/work/.claude"
git fetch -q --all --prune
echo "    pull --ff-only:"
git pull --ff-only >/dev/null 2>&1; echo "        終了コード=$?"
echo "        消費側の先頭: $(git log --oneline -1)"
git reset -q --hard "origin/$(git rev-parse --abbrev-ref HEAD)"
echo "    reset --hard 後の先頭: $(git log --oneline -1)"
echo "    master の追記3 が届いたか: $(grep -c 'NESTCLONE-M3-7709' CLAUDE.md) 件"
echo "    settings.local.json: $([ -f settings.local.json ] && echo '残存' || echo '★消えた★')"

echo
echo "=== 参考: ローカルに全ブランチを持たない場合 updateRefs はどうなるか ==="
cd "$BASE"
rm -rf maint2 && git clone -q shared.git maint2 && cd maint2
git switch -q --track origin/java/design 2>/dev/null || git switch -q "java/design"
echo "    ローカルブランチ: [$(git branch --format='%(refname:short)' | tr '\n' ' ')]"
cd "$BASE/shared"; git switch -q master
printf '\n追記4\n' >> CLAUDE.md; git add -A; git commit -qm "master 追記4"; git push -q origin master
cd "$BASE/maint2"; git fetch -q --all
git -c rebase.updateRefs=true rebase origin/master 2>&1 | sed 's/^/    /'
echo "    ローカルに java/_base が無い状態での結果 → java/_base は更新され得ない（ローカル参照が無いため）"
echo "    ローカルブランチ: [$(git branch --format='%(refname:short)' | tr '\n' ' ')]"
