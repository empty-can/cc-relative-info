#!/usr/bin/env bash
# C-1 の主張の検証:
#   ランチャーが `git switch <B>` の失敗を検査せずに `git reset --hard origin/<B>` を続けると、
#   「現在いるブランチ」が <B> の内容で上書きされてしまうのか。
set -uo pipefail

T="$(dirname "$0")/switchfail"
rm -rf "$T"; mkdir -p "$T"; cd "$T"

git init -q --bare remote.git
git clone -q remote.git repo
cd repo
git config user.email t@example.com; git config user.name t

echo "main の資産" > asset.txt
git add -A && git commit -qm "main 初版"
BR=$(git rev-parse --abbrev-ref HEAD)
git push -q origin "$BR"

git switch -qc other
echo "other の資産（main には存在してはいけない）" > asset.txt
git add -A && git commit -qm "other 版"
git push -q origin other
git switch -q "$BR"

echo "=== 初期状態 ==="
echo "  現在のブランチ: $(git rev-parse --abbrev-ref HEAD)"
echo "  asset.txt: $(cat asset.txt)"
echo "  $BR の先頭: $(git log --oneline -1 "$BR")"

echo
echo "=== ランチャーの Step 3 を模擬（switch は失敗させる）==="
git fetch -q --all --prune
# D/F コンフリクトや存在しないブランチなど、switch が失敗するケース
git switch "does/not/exist" 2>&1 | sed 's/^/    switch: /'
echo "    switch の終了コード: ${PIPESTATUS[0]}"
# ランチャーは終了コードを見ずに次へ進む
git reset --hard "origin/other" 2>&1 | sed 's/^/    reset: /'
echo "    reset の終了コード: $?"

echo
echo "=== 結果 ==="
echo "  現在のブランチ: $(git rev-parse --abbrev-ref HEAD)"
echo "  asset.txt: $(cat asset.txt)"
echo "  $BR の先頭: $(git log --oneline -1 "$BR")"
echo "  origin/$BR の先頭: $(git log --oneline -1 "origin/$BR")"
echo
if grep -q "other の資産" asset.txt; then
  echo "  ★ 再現した: ブランチ名は $BR のまま、中身が other で上書きされた"
else
  echo "  再現しなかった"
fi
