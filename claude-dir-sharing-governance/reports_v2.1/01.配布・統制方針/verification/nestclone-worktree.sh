#!/usr/bin/env bash
# 作業リポジトリの linked worktree から起動したとき、入れ子クローン .claude/ の資産が
# どこまでロードされるかを測る。作業リポジトリは .claude/ を gitignore しているので、
# 新しい worktree には .claude/ が作られない。
# 先に nestclone-setup.sh で足場を作っておくこと。
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/nestclone/work" || exit 1
[ -d .claude/.git ] || { echo "足場がありません。nestclone-setup.sh を先に実行してください" >&2; exit 1; }

WT="$HERE/nestclone/wt"
git worktree remove --force "$WT" >/dev/null 2>&1
git branch -q -D wt-probe >/dev/null 2>&1
git worktree add -q -b wt-probe "$WT" || exit 1
trap 'cd "$HERE/nestclone/work" && git worktree remove --force "$WT" >/dev/null 2>&1; git branch -q -D wt-probe >/dev/null 2>&1' EXIT

cd "$WT" || exit 1
echo "=== worktree の中身（.claude/ があるか）==="
ls -a
echo

read -r -d '' PROMPT <<'EOF' || true
次の4項目を順に実行し、結果だけを「ラベル=値」の形で1行ずつ出力してください。説明文は不要です。

1. あなたのコンテキストに NESTCLONE-CM で始まる合言葉があれば `CM=<その合言葉>` を出力。無ければ `CM=NONE`。
2. NESTCLONE-RU で始まる合言葉があれば `RU=<その合言葉>` を出力。無ければ `RU=NONE`。
3. Bash ツールで `printenv NESTPROBE_ENV` を実行し、`EV=<出力そのまま>` を出力。何も出力されなければ `EV=NONE`。
4. Skill ツールで skill 名 `probeskill` を起動し、返ってきた合言葉を `SK=<合言葉>` の形で出力。起動できなければ `SK=FAIL`。
EOF

echo "=== linked worktree のルートから起動 ==="
claude --model haiku --allowedTools "Bash" "Skill" -p "$PROMPT"
echo
echo "----- 終了コード: $? -----"
