#!/usr/bin/env bash
# Bash コマンドの形ごとに、条件付きロードの発火を測る（trigger-run.sh の補測）。
# 先に trigger-setup.sh で足場を作っておくこと。
#
# 測る形: head（1 ファイル）/ grep（1 ファイル）/ パイプ付き / 複数ファイル
# 判定: 合言葉の出力と Skill ツールの起動成否。モデルが実行したツール呼び出しも
#       stream-json から抜き出して表示し、指示した 1 コマンド以外で合言葉のファイルを
#       読んでいないことを確かめられるようにする。
# usage: bash trigger-bash-forms.sh [モデル名（既定 haiku）]
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE/trigprobe" || exit 1
[ -f sub/target.probefile ] || { echo "足場がありません。trigger-setup.sh を先に実行してください" >&2; exit 1; }

MODEL="${1:-haiku}"

# 複数ファイルの形で使う 2 つ目のファイル（未追跡のまま置き、最後に消す）
printf 'delta epsilon\n' > sub/other.probefile
trap 'rm -f sub/other.probefile' EXIT

ASK=$'\n\n実行する Bash コマンドは上の 1 つだけです。ほかのコマンドを実行してはいけません。そのうえで、以下を「ラベル=値」の形で1行ずつ出力してください。**追加でファイルを読んではいけません。**\n- いま文脈にある RULEPROBE- で始まる合言葉があれば `RULE=<合言葉>`、無ければ `RULE=NONE`\n- SUBCLAUDE- で始まる合言葉があれば `CMD=<合言葉>`、無ければ `CMD=NONE`\n- Skill ツールで `subskill` を起動し、返った合言葉を `SKILL=<合言葉>`。起動できなければ `SKILL=FAIL`'

run() {
  local label="$1" cmd="$2"
  echo "================ $label: $cmd ================"
  claude --model "$MODEL" --allowedTools "Bash" "Skill" \
    --output-format stream-json --verbose \
    -p "まず Bash ツールで \`$cmd\` を実行してください。${ASK}" 2>&1 \
    | python -I -X utf8 "$HERE/trigger-bash-forms-show.py"
  echo
}

run "head（1 ファイル）"  'head -1 sub/target.probefile'
run "grep（1 ファイル）"  'grep beta sub/target.probefile'
run "パイプ付き"          'cat sub/target.probefile | head -1'
run "複数ファイル"        'cat sub/target.probefile sub/other.probefile'
