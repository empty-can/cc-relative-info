#!/usr/bin/env bash
# D/F コンフリクトを避ける命名（親も leaf トークンで終える: java/_base・java/design）で作り直し、
# master を先に進めてから多段 rebase（rebase.updateRefs）→ メンバー側の切替 → git pull --ff-only の
# 失敗までを通す。先に nestclone-setup.sh と nestclone-branch.sh を実行しておくこと。
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1

BASE="$VERIF_ROOT/nestclone"
verif_enter_repo "$BASE/shared"
git switch -q master || verif_die "master へ切り替えられない"
git branch -q -D java 2>/dev/null
git push -q origin --delete java 2>/dev/null

echo "=== 先に D/F コンフリクトの再現を明示記録 ==="
git branch java-df-test master >/dev/null 2>&1
git branch "java-df-test/child" master 2>&1 | sed 's/^/    /'
echo "    終了コード: ${PIPESTATUS[0]}"
git branch -q -D java-df-test

echo
echo "=== 命名を java/_base ・ java/design に変えて作成（master の現在から）==="
git switch -qc java/_base master || verif_die "java/_base を作れない"
mkdir -p rules
cat > rules/java-rule.md <<'EOF'
---
description: java 系リポジトリ共通の rule。
---
合言葉 **NESTCLONE-JV7706**。
EOF
git add -A && git commit -qm "java 系共通の rule"
git switch -qc java/design java/_base || verif_die "java/design を作れない"
cat > rules/design-rule.md <<'EOF'
---
description: 設計作業限定の rule。
---
合言葉 **NESTCLONE-DS7707**。
EOF
git add -A && git commit -qm "設計作業固有の rule"
git push -q origin "java/_base" "java/design"; echo "    push の終了コード: $?（0 なら D/F コンフリクトなし）"

echo
echo "=== master を先に進めてから、多段 rebase で伝播 ==="
git switch -q master
printf '\n追記: 合言葉 **NESTCLONE-M2B-7710**。\n' >> CLAUDE.md
git add -A && git commit -qm "master に追記（branch2 の多段伝播の起点）" && git push -q origin master
echo "    master の先頭: $(git log --oneline -1)"
echo "    rebase 前: java/_base は master を先祖に持つか: $(git merge-base --is-ancestor master java/_base && echo YES || echo NO)"
git switch -q java/design
git -c rebase.updateRefs=true rebase master 2>&1 | sed 's/^/    /'
echo "    rebase の終了コード: ${PIPESTATUS[0]}"
echo "    java/_base  の先頭: $(git log --oneline -1 java/_base)"
echo "    java/design の先頭: $(git log --oneline -1 java/design)"
echo "    rebase 後: java/_base は master を先祖に持つか: $(git merge-base --is-ancestor master java/_base && echo YES || echo NO)"
echo "    rebase 後: java/design は master を先祖に持つか: $(git merge-base --is-ancestor master java/design && echo YES || echo NO)"
git push -q --force origin "java/_base" "java/design"; echo "    push --force の終了コード: $?"

echo
echo "=== rebase 後のブランチグラフ ==="
git log --oneline --graph --all --decorate | head -20

echo
echo "=== 消費側: fetch → switch → reset --hard ==="
verif_enter_repo "$BASE/work/.claude"
echo "    切替前: ブランチ=$(git rev-parse --abbrev-ref HEAD) rules=[$(ls rules | tr '\n' ' ')]"
git fetch -q --all --prune; echo "    fetch の終了コード: $?"
git switch -q "java/design" 2>&1 | sed 's/^/    switch: /'; echo "    switch の終了コード: ${PIPESTATUS[0]}"
git reset -q --hard "origin/java/design" 2>&1 | sed 's/^/    reset: /'; echo "    reset の終了コード: ${PIPESTATUS[0]}"
echo "    切替後: ブランチ=$(git rev-parse --abbrev-ref HEAD) rules=[$(ls rules | tr '\n' ' ')]"
echo "    CLAUDE.md に master の追記（M2B）が届いたか: $(grep -c 'NESTCLONE-M2B-7710' CLAUDE.md) 件"
echo "    git status: [$(git status --short | tr '\n' ' ')]"

echo
echo "=== 参考: 同じ状況で git pull --ff-only を試す（メンテナーが amend して force-push）==="
verif_enter_repo "$BASE/shared"
git switch -q java/design
printf '\n追記2\n' >> rules/design-rule.md; git add -A; git commit -q --amend --no-edit
git push -q --force origin "java/design"
verif_enter_repo "$BASE/work/.claude"
git pull --ff-only 2>&1 | sed 's/^/    /'
echo "    終了コード: ${PIPESTATUS[0]}"
