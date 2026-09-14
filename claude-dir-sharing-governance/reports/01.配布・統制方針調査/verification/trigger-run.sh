#!/usr/bin/env bash
# 先行操作の種類ごとに 1 セッションずつ起動し、3 資産の発火を判定する。
# 合言葉を「読みに行く」ことを防ぐため、先行操作用のツールと Skill だけを許可する。
set -uo pipefail

cd "$(dirname "$0")/trigprobe"

ASK=$'\n\nそのうえで、以下を「ラベル=値」の形で1行ずつ出力してください。**追加でファイルを読んではいけません。**\n- いま文脈にある RULEPROBE- で始まる合言葉があれば `RULE=<合言葉>`、無ければ `RULE=NONE`\n- SUBCLAUDE- で始まる合言葉があれば `CMD=<合言葉>`、無ければ `CMD=NONE`\n- Skill ツールで `subskill` を起動し、返った合言葉を `SKILL=<合言葉>`。起動できなければ `SKILL=FAIL`'

run() {
  local label="$1" tools="$2" pre="$3"
  echo "================ $label ================"
  claude --model haiku --allowedTools $tools -p "${pre}${ASK}" 2>&1 | tail -8
  echo
}

run "先行操作なし（対照）"   '"Skill"'        '何も先行操作をしないでください。'
run "Read ツール"            '"Read" "Skill"' 'まず Read ツールで sub/target.probefile を読んでください。'
run "Bash で cat"            '"Bash" "Skill"' 'まず Bash ツールで `cat sub/target.probefile` を実行してください。'
run "Grep ツール"            '"Grep" "Skill"' 'まず Grep ツールで sub/ 配下から "beta" を content モードで検索してください。'
