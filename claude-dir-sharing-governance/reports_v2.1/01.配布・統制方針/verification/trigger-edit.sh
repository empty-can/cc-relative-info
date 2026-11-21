#!/usr/bin/env bash
# Edit ツール単独（Read を許可しない）で Edit が通るか、通ったときに条件付きロードが
# 発火するかを、モデルごとに測る。先に trigger-setup.sh で足場を作っておくこと。
#
# 事前の Read 無しで Edit が通るかはモデルで決まる（CLI の版では決まらない）ので、
# モデル名を引数で渡す。
# usage: bash trigger-edit.sh [モデル名...]   （既定: claude-haiku-4-5 claude-haiku-5-5）
set -uo pipefail

cd "$(dirname "$0")/trigprobe" || exit 1
[ -f sub/target.probefile ] || { echo "足場がありません。trigger-setup.sh を先に実行してください" >&2; exit 1; }
# 足場が独立した git リポジトリであることを確かめる（親のリポジトリを操作しないため）
[ -d .git ] || { echo "足場が独立したリポジトリではありません" >&2; exit 1; }

[ "$#" -gt 0 ] || set -- claude-haiku-4-5 claude-haiku-5-5

ASK=$'\n\nそのうえで、以下を「ラベル=値」の形で1行ずつ出力してください。**追加でファイルを読んではいけません。**\n- Edit が成功したかを `EDIT=OK` / `EDIT=FAIL`（失敗ならエラー本文も 1 行で）\n- いま文脈にある RULEPROBE- で始まる合言葉があれば `RULE=<合言葉>`、無ければ `RULE=NONE`\n- SUBCLAUDE- で始まる合言葉があれば `CMD=<合言葉>`、無ければ `CMD=NONE`\n- Skill ツールで `subskill` を起動し、返った合言葉を `SKILL=<合言葉>`。起動できなければ `SKILL=FAIL`'

for MODEL in "$@"; do
  git checkout -q -- sub/target.probefile
  echo "================ model=$MODEL / Edit ツール（Read を許可しない） ================"
  claude --model "$MODEL" --allowedTools "Edit" "Skill" \
    -p 'まず Edit ツールで sub/target.probefile の "alpha beta gamma" を "alpha beta gamma delta" に置換してください。Read ツールは使えません。'"$ASK" 2>&1
  echo
  echo "--- ファイルの現在の内容（$MODEL）:"; cat sub/target.probefile
  echo
done
git checkout -q -- sub/target.probefile
