#!/usr/bin/env bash
# サブディレクトリの skills について、条件付きロード以外の載せ方を測る。
# 先に trigger-setup.sh で足場を作っておくこと。
#
#   1. 起動時に --add-dir <サブディレクトリ> を付ける（先行操作なし）
#   2. 非対話（claude -p）で /add-dir を渡す
# usage: bash trigger-adddir.sh [モデル名（既定 haiku）]
set -uo pipefail

cd "$(dirname "$0")/trigprobe" || exit 1
[ -f sub/target.probefile ] || { echo "足場がありません。trigger-setup.sh を先に実行してください" >&2; exit 1; }

MODEL="${1:-haiku}"
ASK='何も先行操作をしないでください。**ファイルを読んではいけません。** Skill ツールで `subskill` を起動し、返った合言葉を `SKILL=<合言葉>` の形で 1 行出力してください。起動できなければ `SKILL=FAIL` と出力してください。'

echo "================ 対照: フラグなし ================"
claude --model "$MODEL" --allowedTools "Skill" -p "$ASK" 2>&1
echo
echo "================ 起動時に --add-dir sub ================"
claude --model "$MODEL" --add-dir sub --allowedTools "Skill" -p "$ASK" 2>&1
echo
echo "================ 非対話で /add-dir sub ================"
# Git Bash は先頭が / の引数を Windows のパスへ書き換えるので、この呼び出しだけ変換を止める
MSYS_NO_PATHCONV=1 claude --model "$MODEL" --allowedTools "Skill" -p "/add-dir sub" 2>&1
