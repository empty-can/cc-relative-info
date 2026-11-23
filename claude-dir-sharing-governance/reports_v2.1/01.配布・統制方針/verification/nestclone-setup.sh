#!/usr/bin/env bash
# 案C-1 実形状の検証足場を $VERIF_ROOT/<名前> に作る。
#   作業リポジトリ（git 管理）の .claude/ が「別リポジトリのクローン」であり、
#   かつ作業リポ側では .gitignore 対象、という状態で資産がロードされるかを測る。
#
# usage: bash nestclone-setup.sh [deny|nodeny]
#   deny  （既定）足場 $VERIF_ROOT/nestclone。共有リポの settings.json に
#          permissions.deny ["Bash(./denyprobe.sh)"] を書く
#   nodeny       足場 $VERIF_ROOT/nestclone-nodeny。deny を書かない（deny の対照）
#
# 作業リポジトリには、実行されると denyprobe.out を作る ./denyprobe.sh を commit しておく
# （linked worktree にも入るように）。サブディレクトリ sub/ にも同じものを置く
# （サブディレクトリから起動したときに、同じ文字列 ./denyprobe.sh で呼べるように）。
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1

MODE="${1:-deny}"
case "$MODE" in
  deny)   NAME=nestclone ;;
  nodeny) NAME=nestclone-nodeny ;;
  *) verif_die "引数は deny か nodeny" ;;
esac

verif_fresh_dir "$NAME"
verif_cd "$VERIF_ROOT/$NAME"

# ---- 共有 .claude リポジトリ（メンテナー側）----
# 後段（nestclone-branch.sh・nestclone-branch2.sh・nestclone-updaterefs.sh）は master を決め打ちにしている。
# init.defaultBranch が master 以外の端末でも同じ名前になるよう、初期ブランチを master に固定する。
git init -q --bare -b master shared.git || verif_die "init に失敗"
git clone -q shared.git shared 2>/dev/null || verif_die "clone に失敗"
verif_enter_repo shared
git symbolic-ref HEAD refs/heads/master || verif_die "初期ブランチを master にできない"
git config user.email m@example.com
git config user.name m
mkdir -p rules skills/probeskill agents || exit 1

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

if [ "$MODE" = deny ]; then
cat > settings.json <<'EOF'
{
  "env": {
    "NESTPROBE_ENV": "NESTCLONE-EV7703"
  },
  "permissions": {
    "deny": ["Bash(./denyprobe.sh)"]
  }
}
EOF
else
cat > settings.json <<'EOF'
{
  "env": {
    "NESTPROBE_ENV": "NESTCLONE-EV7703"
  }
}
EOF
fi

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

git add -A && git commit -qm "共有 .claude 資産の初版" || verif_die "commit に失敗"
BR=$(git rev-parse --abbrev-ref HEAD)
git push -q origin "$BR" || verif_die "push に失敗"
cd .. || exit 1

# ---- 作業リポジトリ（消費側）----
mkdir work || exit 1
verif_cd work
git init -q -b master || verif_die "init に失敗"
verif_enter_repo .
git config user.email w@example.com
git config user.name w
printf '.claude/\ndenyprobe.out\n' > .gitignore
printf 'work repo\n' > README.md
mkdir -p sub || exit 1
cat > denyprobe.sh <<'EOF'
#!/usr/bin/env bash
# 実行されたら、起動したディレクトリに denyprobe.out を作る（deny が効いたかの判定用）
echo "DENYPROBE-RAN $(date +%s)" > denyprobe.out
echo "DENYPROBE-RAN"
EOF
chmod +x denyprobe.sh
cp denyprobe.sh sub/denyprobe.sh
printf 'サブディレクトリ\n' > sub/README.md
git add -A
git update-index --chmod=+x denyprobe.sh sub/denyprobe.sh
git commit -qm "作業リポジトリ初期化（.claude/ は gitignore）" || verif_die "commit に失敗"

git clone -q ../shared.git .claude 2>/dev/null || verif_die ".claude の clone に失敗"

echo "=== 足場: $(verif_winpath .)（mode=$MODE）==="
echo "=== 作業リポジトリの git status --short（.claude/ が無視されているか）==="
git status --short
echo "(上が空なら .claude/ は完全に無視されている)"
echo
echo "=== .claude の中身 ==="
ls -a .claude
echo
echo "=== .claude が独立リポジトリか ==="
( verif_enter_repo .claude && echo "  .claude のブランチ: $(git rev-parse --abbrev-ref HEAD) ／ git-dir: $(git rev-parse --git-dir)" )
echo
echo "=== .claude/settings.json ==="
cat .claude/settings.json
