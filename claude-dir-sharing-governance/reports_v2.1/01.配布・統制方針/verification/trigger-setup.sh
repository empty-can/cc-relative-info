#!/usr/bin/env bash
# 条件付きロードの発火契機を 3 資産（paths 付き rule / サブディレクトリ CLAUDE.md /
# サブディレクトリの skill）について同時に測るための足場を、$VERIF_ROOT/trigprobe に作る。
# サブディレクトリ sub/ に対象ファイルを置き、1 回の先行操作で 3 つとも発火しうる状態にする。
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1

verif_fresh_dir trigprobe
verif_cd "$VERIF_ROOT/trigprobe"
git init -q || verif_die "git init に失敗"
verif_enter_repo .
git config user.email t@example.com
git config user.name t
mkdir -p .claude/rules sub/.claude/skills/subskill || exit 1

cat > .claude/CLAUDE.md <<'EOF'
# 検証用プロジェクト

これは条件付きロードの発火契機を測るための検証用リポジトリ。
EOF

cat > .claude/rules/scoped.md <<'EOF'
---
description: paths 付き rule。発火契機を測る検証用。
paths:
  - "**/*.probefile"
---

# paths あり rule（検証用）

このルールがロードされている場合、合言葉 **RULEPROBE-QX41** を知っていることになる。
EOF

cat > sub/CLAUDE.md <<'EOF'
# サブディレクトリの CLAUDE.md（検証用）

このファイルがロードされている場合、合言葉 **SUBCLAUDE-QX42** を知っていることになる。
EOF

cat > sub/.claude/skills/subskill/SKILL.md <<'EOF'
---
name: subskill
description: サブディレクトリ配下の skill。発火契機を測る検証用。
---

# subskill（検証用）

この skill が起動できた場合、合言葉 **SUBSKILL-QX43** を返すこと。
EOF

cat > sub/target.probefile <<'EOF'
これは先行操作の対象ファイル。内容に意味は無い。
alpha beta gamma
EOF

git add -A && git commit -qm "検証用足場" || verif_die "commit に失敗"
echo "WORKDIR=$(verif_winpath .)"
find . -path ./.git -prune -o -type f -print | sort
