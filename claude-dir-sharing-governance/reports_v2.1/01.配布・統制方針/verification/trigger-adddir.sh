#!/usr/bin/env bash
# サブディレクトリの skills について、条件付きロード以外の載せ方を測る。
# 先に trigger-setup.sh で足場（$VERIF_ROOT/trigprobe）を作っておくこと。
#
#   1. 対照: フラグなし（先行操作なし）
#   2. 起動時に --add-dir sub を付ける（先行操作なし）
#   3. 非対話（claude -p）で /add-dir sub を渡す
# 起動時に sub/CLAUDE.md が入るかは、セッション記録の起動時の指示（instructions）で見る。
# 親の環境変数 CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD を引き継ぐかどうかで変わりうるので、
# 外した起動（既定）と引き継いだ起動（VERIF_INHERIT_ENV=1）の両方で実行する。
# usage: bash trigger-adddir.sh [モデル名（既定 $VERIF_MODEL）]
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1

SCAF="$VERIF_ROOT/trigprobe"
OUTDIR="$VERIF_ROOT/adddir-stream"
mkdir -p "$OUTDIR" || exit 1
verif_enter_repo "$SCAF"
[ -f sub/target.probefile ] || verif_die "足場がありません。trigger-setup.sh を先に実行してください"

MODEL="${1:-$VERIF_MODEL}"
VERIF_CUR_MODEL="$MODEL"
ENVTAG=$([ "${VERIF_INHERIT_ENV:-0}" = 1 ] && echo inherit || echo strip)
ASK='何も先行操作をしないでください。**ファイルを読んではいけません。** Skill ツールで `subskill` を起動し、返った合言葉を `SKILL=<合言葉>` の形で 1 行出力してください。起動できなければ `SKILL=FAIL` と出力してください。続けて、いま文脈に SUBCLAUDE- で始まる合言葉があれば `CMD=<合言葉>`、無ければ `CMD=NONE` と出力してください。'

echo "================ 対照: フラグなし（$ENVTAG） ================"
verif_header "--tools Skill"
verif_claude_stream "$OUTDIR/ctrl-$ENVTAG.jsonl" --model "$MODEL" --tools "Skill" --allowedTools "Skill" -p "$ASK"
echo
echo "================ 起動時に --add-dir sub（$ENVTAG） ================"
verif_header "--tools Skill ／ --add-dir sub"
verif_claude_stream "$OUTDIR/adddir-$ENVTAG.jsonl" --model "$MODEL" --add-dir sub --tools "Skill" --allowedTools "Skill" -p "$ASK"
echo
echo "================ 非対話で /add-dir sub（$ENVTAG） ================"
# Git Bash は先頭が / の引数を Windows のパスへ書き換えるので、この呼び出しだけ変換を止める
verif_header "--tools Skill ／ -p \"/add-dir sub\"（MSYS_NO_PATHCONV=1）"
MSYS_NO_PATHCONV=1 verif_claude --model "$MODEL" --tools "Skill" --allowedTools "Skill" -p "/add-dir sub" 2>&1
rc=$?
echo "  ---- claude の終了コード: $rc"
