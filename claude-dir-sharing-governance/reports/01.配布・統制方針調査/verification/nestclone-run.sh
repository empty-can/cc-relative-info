#!/usr/bin/env bash
# 入れ子クローン .claude/ から各資産がロードされるかを 1 セッションで測る。
set -uo pipefail

cd "$(dirname "$0")/nestclone/work"

read -r -d '' PROMPT <<'EOF' || true
次の4項目を順に実行し、結果だけを「ラベル=値」の形で1行ずつ出力してください。説明文は不要です。

1. あなたのコンテキストに NESTCLONE-CM で始まる合言葉があれば `CM=<その合言葉>` を出力。無ければ `CM=NONE`。
2. NESTCLONE-RU で始まる合言葉があれば `RU=<その合言葉>` を出力。無ければ `RU=NONE`。
3. Bash ツールで `printenv NESTPROBE_ENV` を実行し、`EV=<出力そのまま>` を出力。実行できなければ `EV=FAIL`。
4. Skill ツールで skill 名 `probeskill` を起動し、返ってきた合言葉を `SK=<合言葉>` の形で出力。起動できなければ `SK=FAIL`。
EOF

claude --model haiku --allowedTools "Bash" "Skill" -p "$PROMPT"
echo
echo "----- 終了コード: $? -----"
