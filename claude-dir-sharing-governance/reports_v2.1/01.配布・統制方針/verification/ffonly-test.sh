#!/usr/bin/env bash
# リモートが rebase + force-push した後、消費側の各コマンドがどう振る舞うかの実測。
set -uo pipefail

T="$(dirname "$0")/ffonly"
rm -rf "$T"; mkdir -p "$T"; cd "$T" || exit 1

git init -q --bare remote.git

git clone -q remote.git maintainer
cd maintainer || exit 1
git config user.email m@example.com; git config user.name m
echo base > base.txt && git add . && git commit -qm "c1: base"
git push -q origin main 2>/dev/null || git push -q origin master
BR=$(git rev-parse --abbrev-ref HEAD)
echo rule1 > rule1.txt && git add . && git commit -qm "c2: rule1"
git push -q origin "$BR"
cd .. || exit 1

git clone -q remote.git consumer
cd consumer || exit 1
echo "消費側の初期状態: $(git log --oneline -1)"
cd .. || exit 1

# メンテナーが履歴を書き換えて force-push（rebase 相当）
cd maintainer || exit 1
git commit -q --amend -m "c2: rule1 (修正後)"
git push -q --force origin "$BR"
echo "メンテナー側の新しい先頭: $(git log --oneline -1)"
cd .. || exit 1

echo
echo "=== 試験1: git pull --ff-only ==="
cd consumer || exit 1
git pull --ff-only 2>&1 | sed 's/^/    /'
echo "    -> 終了コード: ${PIPESTATUS[0]:-?}"
echo "    消費側の現在: $(git log --oneline -1)"
cd .. || exit 1

echo
echo "=== 試験2: git fetch + git reset --hard origin/<branch> ==="
cd consumer || exit 1
git fetch -q --all --prune
git reset --hard "origin/$BR" 2>&1 | sed 's/^/    /'
echo "    -> 終了コード: $?"
echo "    消費側の現在: $(git log --oneline -1)"
cd .. || exit 1

echo
echo "=== 試験3: 参考 — detached HEAD で origin を直接チェックアウト ==="
git clone -q remote.git consumer2
cd consumer2 || exit 1
git fetch -q --all --prune
git checkout -q --detach "origin/$BR" 2>&1 | sed 's/^/    /'
echo "    -> 終了コード: $?"
echo "    消費側の現在: $(git log --oneline -1) / HEAD=$(git rev-parse --abbrev-ref HEAD)"
