#!/usr/bin/env bash
# Edit ツール単独での発火を測る。
# 作業ディレクトリ配下のファイルなので Edit は事前 Read を要求しないはず。
# Read を許可せず Edit だけを許可し、Edit 自体が成立するかも同時に確認する。
set -uo pipefail

cd "$(dirname "$0")/trigprobe"
git checkout -q -- sub/target.probefile 2>/dev/null || true

ASK=$'\n\nそのうえで、以下を「ラベル=値」の形で1行ずつ出力してください。**追加でファイルを読んではいけません。**\n- Edit が成功したかを `EDIT=OK` / `EDIT=FAIL`（失敗ならエラー本文も 1 行で）\n- いま文脈にある RULEPROBE- で始まる合言葉があれば `RULE=<合言葉>`、無ければ `RULE=NONE`\n- SUBCLAUDE- で始まる合言葉があれば `CMD=<合言葉>`、無ければ `CMD=NONE`\n- Skill ツールで `subskill` を起動し、返った合言葉を `SKILL=<合言葉>`。起動できなければ `SKILL=FAIL`'

echo "================ Edit ツール（Read 不許可） ================"
claude --model haiku --allowedTools "Edit" "Skill" \
  -p 'まず Edit ツールで sub/target.probefile の "alpha beta gamma" を "alpha beta gamma delta" に置換してください。Read ツールは使えません。'"$ASK" 2>&1 | tail -10

echo
echo "ファイルの現在の内容:"; cat sub/target.probefile
git checkout -q -- sub/target.probefile 2>/dev/null || true
