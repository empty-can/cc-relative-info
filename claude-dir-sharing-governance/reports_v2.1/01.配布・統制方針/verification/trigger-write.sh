#!/usr/bin/env bash
# Write ツール単独（新規作成。Read を許可しない）での発火を測る。
# 先に trigger-setup.sh で足場を作っておくこと。
# usage: bash trigger-write.sh [モデル名（既定 haiku）]
set -uo pipefail

cd "$(dirname "$0")/trigprobe" || exit 1
[ -f sub/target.probefile ] || { echo "足場がありません。trigger-setup.sh を先に実行してください" >&2; exit 1; }

MODEL="${1:-haiku}"
trap 'rm -f sub/new.probefile' EXIT

ASK=$'\n\nそのうえで、以下を「ラベル=値」の形で1行ずつ出力してください。**追加でファイルを読んではいけません。**\n- いま文脈にある RULEPROBE- で始まる合言葉があれば `RULE=<合言葉>`、無ければ `RULE=NONE`\n- SUBCLAUDE- で始まる合言葉があれば `CMD=<合言葉>`、無ければ `CMD=NONE`\n- Skill ツールで `subskill` を起動し、返った合言葉を `SKILL=<合言葉>`。起動できなければ `SKILL=FAIL`'

echo "================ Write ツール（新規作成・Read を許可しない） ================"
claude --model "$MODEL" --allowedTools "Write" "Skill" \
  -p 'まず Write ツールで sub/new.probefile を新規作成し、内容は "x" の 1 行にしてください。'"$ASK" 2>&1
