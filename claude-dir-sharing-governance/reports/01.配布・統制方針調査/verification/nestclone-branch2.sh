#!/usr/bin/env bash
# 再検証: D/F コンフリクトを避ける命名（親も leaf トークンで終える）で
# 多段 rebase → 消費側切替 → reset --hard の保護まで通す。
set -uo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)/nestclone"
cd "$BASE/shared"
git switch -q master
git branch -q -D java 2>/dev/null

echo "=== 先に D/F コンフリクトの再現を明示記録 ==="
git branch java-df-test master >/dev/null 2>&1
git branch "java-df-test/child" master 2>&1 | sed 's/^/    /'
git branch -q -D java-df-test

echo
echo "=== 命名を java/_base ・ java/design に変えて作成 ==="
git switch -qc java/_base master
mkdir -p rules
cat > rules/java-rule.md <<'EOF'
---
description: java 系リポジトリ共通の rule。
---
合言葉 **NESTCLONE-JV7706**。
EOF
git add -A && git commit -qm "java 系共通の rule"

git switch -qc java/design java/_base
cat > rules/design-rule.md <<'EOF'
---
description: 設計作業限定の rule。
---
合言葉 **NESTCLONE-DS7707**。
EOF
git add -A && git commit -qm "設計作業固有の rule"
git push -q origin "java/_base" "java/design" && echo "    push 成功（D/F コンフリクトなし）"

echo
echo "=== master を更新して多段 rebase で伝播 ==="
git switch -q master
git log --oneline -1
git switch -q java/design
git -c rebase.updateRefs=true rebase master 2>&1 | sed 's/^/    /'
echo "    java/_base  の先頭: $(git log --oneline -1 java/_base)"
echo "    java/design の先頭: $(git log --oneline -1 java/design)"
echo "    java/_base は master を先祖に持つか: $(git merge-base --is-ancestor master java/_base && echo YES || echo NO)"
echo "    java/design は master を先祖に持つか: $(git merge-base --is-ancestor master java/design && echo YES || echo NO)"
git push -q --force origin "java/_base" "java/design"

echo
echo "=== rebase 後のブランチグラフ（一直線なら反映漏れなし）==="
git log --oneline --graph --all --decorate | head -20

echo
echo "=== 消費側: fetch → switch → reset --hard ==="
cd "$BASE/work/.claude"
echo "    切替前: ブランチ=$(git rev-parse --abbrev-ref HEAD) rules=[$(ls rules | tr '\n' ' ')]"
git fetch -q --all --prune
git switch -q "java/design" && git reset -q --hard "origin/java/design"
echo "    切替後: ブランチ=$(git rev-parse --abbrev-ref HEAD) rules=[$(ls rules | tr '\n' ' ')]"
echo "    settings.local.json: $([ -f settings.local.json ] && cat settings.local.json || echo '★消えた★')"
echo "    CLAUDE.md に master の追記が届いたか: $(grep -c 'NESTCLONE-M2-7708' CLAUDE.md) 件"
echo "    git status: [$(git status --short | tr '\n' ' ')]"

echo
echo "=== 参考: 同じ状況で git pull --ff-only を試す ==="
cd "$BASE/shared"; git switch -q java/design
printf '\n追記2\n' >> rules/design-rule.md; git add -A; git commit -q --amend --no-edit
git push -q --force origin "java/design"
cd "$BASE/work/.claude"
git pull --ff-only 2>&1 | sed 's/^/    /'
echo "    終了コード: ${PIPESTATUS[0]}"
