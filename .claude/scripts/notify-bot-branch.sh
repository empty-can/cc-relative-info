#!/usr/bin/env bash
# SessionStart 通知スクリプト。
# doc-summary-bot ブランチに「人手レビュー前の未確定な自動生成サマリ」が
# 残っていれば、その旨をセッション開始時に知らせる。
#
# 出力なし = 未確定生成なし（通常時はノイズを出さない）。
# bash 前提（UserPromptSubmit hook と同条件）・OS 中立。
# 異常系（生成失敗で push 抑止 / push 失敗 / レビュー打ち切り）で bot ローカルに
# 残ったコミットは、いずれも「BASE へ未マージ」状態として本スクリプトが検出する。
set -euo pipefail

BOT="work/LLMs/doc-summary-bot"
BASE="feature/LLMs"

# bot ブランチがローカルに無ければ何もしない
git rev-parse --verify --quiet "refs/heads/$BOT" >/dev/null 2>&1 || exit 0

# BASE に未マージの bot コミット数（= 未確定生成の主指標）
unmerged=$(git rev-list --count "$BASE..$BOT" 2>/dev/null || echo 0)

# 未 push 数（origin 追跡ブランチがある場合のみ補足表示）
unpushed=""
if git rev-parse --verify --quiet "refs/remotes/origin/$BOT" >/dev/null 2>&1; then
  n=$(git rev-list --count "origin/$BOT..$BOT" 2>/dev/null || echo 0)
  [ "$n" -gt 0 ] && unpushed=" / 未 push: ${n} 件"
fi

if [ "$unmerged" -gt 0 ]; then
  echo "⚠ doc-summary-bot に未確定の自動生成サマリがあります（${BASE} へ未マージ: ${unmerged} 件${unpushed}）。"
  echo "  確認: git log --oneline ${BASE}..${BOT}  /  反映: 人手レビュー後に bot→${BASE}→develop へマージ"
fi
