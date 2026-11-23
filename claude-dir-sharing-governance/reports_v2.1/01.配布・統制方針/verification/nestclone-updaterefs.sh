#!/usr/bin/env bash
# rebase.updateRefs が「中間ブランチも一括で更新する」ことを実際に働かせて確認する。
# あわせて、pull --ff-only が失敗した状態から reset --hard で復旧できること、
# 中間ブランチをローカルに持たないクローンで rebase したとき、origin の中間ブランチがどうなるかを見る。
# 先に nestclone-setup.sh・nestclone-branch.sh・nestclone-branch2.sh を実行しておくこと。
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1

BASE="$VERIF_ROOT/nestclone"
verif_enter_repo "$BASE/shared"

git switch -q master || verif_die "master へ切り替えられない"
printf '\n追記3: 合言葉 **NESTCLONE-M3-7709**。\n' >> CLAUDE.md
git add -A && git commit -qm "master にさらに追記（多段伝播の起点）" && git push -q origin master

echo "=== rebase 前（java/_base と java/design は古い master の上）==="
git log --oneline --graph --all --decorate | head -12
echo "    java/_base が master を先祖に持つ: $(git merge-base --is-ancestor master java/_base && echo YES || echo NO)"

echo
echo "=== git -c rebase.updateRefs=true rebase master（java/design で1回だけ実行）==="
git switch -q java/design
git -c rebase.updateRefs=true rebase master 2>&1 | sed 's/^/    /'
echo "    rebase の終了コード: ${PIPESTATUS[0]}"

echo
echo "=== rebase 後：中間ブランチ java/_base も一緒に動いたか ==="
git log --oneline --graph --all --decorate | head -12
echo "    java/_base が master を先祖に持つ: $(git merge-base --is-ancestor master java/_base && echo YES || echo NO)"
echo "    java/design が java/_base を先祖に持つ: $(git merge-base --is-ancestor java/_base java/design && echo YES || echo NO)"

git push -q --force origin master "java/_base" "java/design"; echo "    push --force の終了コード: $?"

echo
echo "=== 消費側: pull --ff-only 失敗 → reset --hard で復旧できるか ==="
verif_enter_repo "$BASE/work/.claude"
printf '{ "env": { "PERSONAL": "KEEPME" } }\n' > settings.local.json
echo "    消費側のブランチ: $(git rev-parse --abbrev-ref HEAD) ／ settings.local.json の状態: [$(git status --porcelain --ignored -- settings.local.json)]"
git fetch -q --all --prune; echo "    fetch の終了コード: $?"
echo "    pull --ff-only:"
git pull --ff-only 2>&1 | sed 's/^/        /'
echo "        終了コード=${PIPESTATUS[0]}"
echo "        消費側の先頭: $(git log --oneline -1)"
git reset --hard "origin/$(git rev-parse --abbrev-ref HEAD)" 2>&1 | sed 's/^/        reset: /'
echo "        reset の終了コード=${PIPESTATUS[0]}"
echo "    reset --hard 後の先頭: $(git log --oneline -1) ／ origin と一致: $([ "$(git rev-parse HEAD)" = "$(git rev-parse '@{u}')" ] && echo はい || echo いいえ)"
echo "    master の追記3 が届いたか: $(grep -c 'NESTCLONE-M3-7709' CLAUDE.md) 件"
echo "    settings.local.json: $([ -f settings.local.json ] && echo '残存' || echo '★消えた★')（switch は挟んでいない。reset だけ）"
rm -f settings.local.json

echo
echo "=== 参考: ローカルに中間ブランチ java/_base を持たないクローンで rebase した場合 ==="
verif_cd "$BASE"
if [ -e "$BASE/maint2" ]; then verif_under_root "$BASE/maint2" && rm -rf "$BASE/maint2"; fi
git clone -q shared.git maint2 2>/dev/null || verif_die "clone に失敗"
verif_enter_repo "$BASE/maint2"
git config user.email m2@example.com; git config user.name m2
git switch -q --track origin/java/design 2>/dev/null || git switch -q "java/design"
echo "    ローカルブランチ: [$(git branch --format='%(refname:short)' | tr '\n' ' ')]"
verif_enter_repo "$BASE/shared"
git switch -q master
printf '\n追記4\n' >> CLAUDE.md; git add -A; git commit -qm "master 追記4"; git push -q origin master
verif_enter_repo "$BASE/maint2"
git fetch -q --all
git -c rebase.updateRefs=true rebase origin/master 2>&1 | sed 's/^/    /'
echo "    rebase の終了コード: ${PIPESTATUS[0]}"
echo "    ローカルブランチ: [$(git branch --format='%(refname:short)' | tr '\n' ' ')]"
echo "    ローカルの java/design は origin/master を先祖に持つ: $(git merge-base --is-ancestor origin/master java/design && echo YES || echo NO)"
echo "    origin/java/_base は origin/master を先祖に持つ: $(git merge-base --is-ancestor origin/master origin/java/_base && echo YES || echo NO)"
echo "    （push はしていない。origin/java/_base は、このクローンの rebase では動かない）"
