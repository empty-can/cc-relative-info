#!/usr/bin/env bash
# 案C-1 実形状の検証足場を作る。
#   作業リポジトリ（git 管理）の .claude/ が「別リポジトリのクローン」であり、
#   かつ作業リポ側では .gitignore 対象、という状態で資産がロードされるかを測る。
set -euo pipefail

T="$(dirname "$0")/nestclone"
rm -rf "$T"; mkdir -p "$T"; cd "$T"

# ---- 共有 .claude リポジトリ（メンテナー側）----
git init -q --bare shared.git
git clone -q shared.git shared
cd shared
git config user.email m@example.com
git config user.name m

mkdir -p rules skills/probeskill agents

cat > CLAUDE.md <<'EOF'
# 共有 .claude の CLAUDE.md（検証用）

このファイルがロードされている場合、合言葉 **NESTCLONE-CM7701** を知っていることになる。
EOF

cat > rules/plain-rule.md <<'EOF'
---
description: paths を持たない rule。入れ子クローン配下でも無条件ロードされるかを測る。
---

# paths なし rule（検証用）

このルールがロードされている場合、合言葉 **NESTCLONE-RU7702** を知っていることになる。
EOF

cat > settings.json <<'EOF'
{
  "env": {
    "NESTPROBE_ENV": "NESTCLONE-EV7703"
  }
}
EOF

cat > skills/probeskill/SKILL.md <<'EOF'
---
name: probeskill
description: 入れ子クローン配下の skill がロードされるかを測る検証用 skill。
---

# probeskill（検証用）

この skill がロードされて起動できた場合、合言葉 **NESTCLONE-SK7704** を返すこと。
EOF

cat > agents/probeagent.md <<'EOF'
---
name: probeagent
description: 入れ子クローン配下の subagent が認識されるかを測る検証用エージェント。
tools: Read
model: haiku
---

起動されたら合言葉 NESTCLONE-AG7705 だけを返す。
EOF

git add -A
git commit -qm "共有 .claude 資産の初版"
BR=$(git rev-parse --abbrev-ref HEAD)
git push -q origin "$BR"
cd ..

# ---- 作業リポジトリ（消費側）----
mkdir work
cd work
git init -q
git config user.email w@example.com
git config user.name w
printf '.claude/\n' > .gitignore
printf 'work repo\n' > README.md
git add -A
git commit -qm "作業リポジトリ初期化（.claude/ は gitignore）"

git clone -q ../shared.git .claude

echo "=== 作業リポジトリの git status（.claude/ が無視されているか）==="
git status --short
echo "(上が空なら .claude/ は完全に無視されている)"
echo
echo "=== .claude の中身 ==="
ls -a .claude
echo
echo "=== .claude が独立リポジトリか ==="
git -C .claude rev-parse --abbrev-ref HEAD
echo
echo "WORKDIR=$(pwd)"
