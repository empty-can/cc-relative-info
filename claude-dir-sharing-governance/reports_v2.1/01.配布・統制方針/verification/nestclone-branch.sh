#!/usr/bin/env bash
# ブランチ運用の一巡を、本紙の当初の命名（親 java・子 java/design）で試す。
# 途中の `git switch -c java/design` が D/F コンフリクトで失敗し、その後の手順（多段 rebase・
# メンバー側の切替）も失敗が連鎖する。**このスクリプトは D/F の失敗の記録であり、多段 rebase・
# メンバー側の切替・settings.local.json の保護は測れていない**（それぞれ nestclone-updaterefs.sh・
# nestclone-branch2.sh・nestclone-localfile.sh が測る）。
# 先に nestclone-setup.sh を実行しておくこと（run・worktree の後に実行する。足場を書き換えるため）。
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1

BASE="$VERIF_ROOT/nestclone"
verif_enter_repo "$BASE/shared"

# 共有リポ側で settings.local.json を ignore（消費側の個人設定を守るための前提）
printf 'settings.local.json\n' > .gitignore
git add .gitignore && git commit -qm "個人設定 settings.local.json を ignore" && git push -q origin master || verif_die "push に失敗"

# 子ブランチ java と孫ブランチ java/design
git switch -qc java || verif_die "java を作れない"
mkdir -p rules
cat > rules/java-rule.md <<'EOF'
---
description: java ブランチ限定の rule。
---
このルールがロードされている場合、合言葉 **NESTCLONE-JV7706** を知っていることになる。
EOF
git add -A && git commit -qm "java ブランチ固有の rule"
echo "=== git switch -c java/design（java がある状態で）==="
git switch -qc java/design 2>&1 | sed 's/^/    /'
echo "    終了コード: ${PIPESTATUS[0]}"
echo "    現在のブランチ: $(git rev-parse --abbrev-ref HEAD)"
cat > rules/design-rule.md <<'EOF'
---
description: java/design ブランチ限定の rule。
---
合言葉 **NESTCLONE-DS7707**。
EOF
git add -A && git commit -qm "java/design 固有の rule（java/design を作れなかったので、実際には java に積まれる）"
git push -q origin java java/design 2>&1 | sed 's/^/    push: /'
echo "    push の終了コード: ${PIPESTATUS[0]}"

echo "=== ブランチグラフ ==="
git log --oneline --graph --all --decorate | head -20

# master を更新
git switch -q master
printf '\n追記: 合言葉 **NESTCLONE-M2-7708**。\n' >> CLAUDE.md
git add -A && git commit -qm "master にチーム共通の追記" && git push -q origin master

echo
echo "=== rebase.updateRefs による多段伝播（java/design が無いので失敗するはず）==="
git switch -q java/design 2>&1 | sed 's/^/    switch: /'
echo "    switch の終了コード: ${PIPESTATUS[0]} ／ 現在のブランチ: $(git rev-parse --abbrev-ref HEAD)"

# ---- 消費側 ----
verif_enter_repo "$BASE/work/.claude"
printf '{ "env": { "PERSONAL": "KEEPME" } }\n' > settings.local.json
echo
echo "=== 消費側: 切替前 ==="
echo "    ブランチ: $(git rev-parse --abbrev-ref HEAD) / rules: $(ls rules 2>/dev/null | tr '\n' ' ')"
echo "    git status: [$(git status --short | tr '\n' ' ')]（消費側は .gitignore を含まないコミットにいる）"
git fetch -q --all --prune; echo "    fetch の終了コード: $?"
git switch -q java/design 2>&1 | sed 's/^/    switch: /'; echo "    switch の終了コード: ${PIPESTATUS[0]}"
git reset -q --hard origin/java/design 2>&1 | sed 's/^/    reset: /'; echo "    reset の終了コード: ${PIPESTATUS[0]}"
echo "=== 消費側: fetch → switch → reset --hard 後 ==="
echo "    ブランチ: $(git rev-parse --abbrev-ref HEAD) / rules: $(ls rules | tr '\n' ' ')"
echo "    settings.local.json: $([ -f settings.local.json ] && cat settings.local.json || echo '消えた')"
echo "    git status: [$(git status --short | tr '\n' ' ')]"
# 後続のスクリプトのために消費側を元へ戻す（個人ファイルは消す。localfile の測定は別の足場で行う）
rm -f settings.local.json
