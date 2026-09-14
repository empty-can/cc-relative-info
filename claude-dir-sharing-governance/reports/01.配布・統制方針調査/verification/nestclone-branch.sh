#!/usr/bin/env bash
# 案C-1 の運用動作を測る。
#   (1) 親ブランチ(master)から子ブランチ(java)を作り、子だけの資産を足す
#   (2) 親を更新 → 子を rebase で追従（rebase.updateRefs の多段も確認）
#   (3) 消費側が fetch → switch → reset --hard で切り替わるか
#   (4) reset --hard が gitignore 済み settings.local.json を保護するか
set -uo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)/nestclone"
cd "$BASE/shared"

# 共有リポ側で settings.local.json を ignore（消費側の個人設定を守るための前提）
printf 'settings.local.json\n' > .gitignore
git add .gitignore && git commit -qm "個人設定 settings.local.json を ignore"
git push -q origin master

# 子ブランチ java と孫ブランチ java/design
git switch -qc java
mkdir -p rules
cat > rules/java-rule.md <<'EOF'
---
description: java ブランチ限定の rule。
---
このルールがロードされている場合、合言葉 **NESTCLONE-JV7706** を知っていることになる。
EOF
git add -A && git commit -qm "java ブランチ固有の rule"
git switch -qc java/design
cat > rules/design-rule.md <<'EOF'
---
description: java/design ブランチ限定の rule。
---
合言葉 **NESTCLONE-DS7707**。
EOF
git add -A && git commit -qm "java/design 固有の rule"
git push -q origin java java/design

echo "=== rebase 前のブランチグラフ ==="
git log --oneline --graph --all --decorate | head -20

# 親(master)を更新し、多段 rebase で伝播
git switch -q master
printf '\n追記: 合言葉 **NESTCLONE-M2-7708**。\n' >> CLAUDE.md
git add -A && git commit -qm "master にチーム共通の追記"
git push -q origin master

echo
echo "=== rebase.updateRefs による多段伝播 ==="
git switch -q java/design
git -c rebase.updateRefs=true rebase master 2>&1 | sed 's/^/    /'
echo "    java の先頭: $(git log --oneline -1 java)"
echo "    java/design の先頭: $(git log --oneline -1 java/design)"
git push -q --force origin java java/design

echo
echo "=== rebase 後のブランチグラフ（一直線＝全ブランチが master を取り込み済み）==="
git log --oneline --graph --all --decorate | head -20

# ---- 消費側 ----
cd "$BASE/work/.claude"
printf '{ "env": { "PERSONAL": "KEEPME" } }\n' > settings.local.json
echo
echo "=== 消費側: 切替前 ==="
echo "    ブランチ: $(git rev-parse --abbrev-ref HEAD) / rules: $(ls rules 2>/dev/null | tr '\n' ' ')"

git fetch -q --all --prune
git switch -q java/design
git reset -q --hard origin/java/design
echo "=== 消費側: fetch → switch → reset --hard 後 ==="
echo "    ブランチ: $(git rev-parse --abbrev-ref HEAD) / rules: $(ls rules | tr '\n' ' ')"
echo "    settings.local.json は残ったか: $([ -f settings.local.json ] && cat settings.local.json || echo '消えた')"
echo "    CLAUDE.md に master の追記が届いたか: $(grep -c 'NESTCLONE-M2-7708' CLAUDE.md) 件"
echo "    git status: [$(git status --short | tr '\n' ' ')]"
