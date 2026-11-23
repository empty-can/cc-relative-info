#!/usr/bin/env bash
# リモートの履歴が書き換えられて force-push された後、消費側の各コマンドがどう振る舞うかの実測。
# 書き換えは commit --amend で行う（fast-forward できなくなる点で rebase と同じ。多段の rebase は
# nestclone-updaterefs.sh が測る）。足場は $VERIF_ROOT/ffonly。
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1

verif_fresh_dir ffonly
verif_cd "$VERIF_ROOT/ffonly"
git init -q --bare remote.git || exit 1

git clone -q remote.git maintainer 2>/dev/null || exit 1
verif_enter_repo maintainer
git config user.email m@example.com; git config user.name m
echo base > base.txt && git add . && git commit -qm "c1: base" || exit 1
BR=$(git rev-parse --abbrev-ref HEAD)
git push -q origin "$BR" || exit 1
echo rule1 > rule1.txt && git add . && git commit -qm "c2: rule1" || exit 1
git push -q origin "$BR" || exit 1
cd .. || exit 1

git clone -q remote.git consumer || exit 1
verif_enter_repo consumer
echo "消費側の初期状態: $(git log --oneline -1)"
cd .. || exit 1

# メンテナーが履歴を書き換えて force-push
verif_enter_repo maintainer
git commit -q --amend -m "c2: rule1 (修正後)" || exit 1
git push -q --force origin "$BR" || exit 1
echo "メンテナー側の新しい先頭: $(git log --oneline -1)"
cd .. || exit 1

echo
echo "=== 試験1: git pull --ff-only ==="
verif_enter_repo consumer
git pull --ff-only 2>&1 | sed 's/^/    /'
echo "    -> 終了コード: ${PIPESTATUS[0]}"
echo "    消費側の現在: $(git log --oneline -1)"
cd .. || exit 1

echo
echo "=== 試験2: git fetch + git reset --hard origin/<branch> ==="
verif_enter_repo consumer
git fetch -q --all --prune 2>&1 | sed 's/^/    /'
echo "    -> fetch の終了コード: ${PIPESTATUS[0]}"
git reset --hard "origin/$BR" 2>&1 | sed 's/^/    /'
echo "    -> reset の終了コード: ${PIPESTATUS[0]}"
echo "    消費側の現在: $(git log --oneline -1)"
echo "    origin/$BR と一致: $([ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$BR")" ] && echo はい || echo いいえ)"
cd .. || exit 1

echo
echo "=== 試験3: 参考 — detached HEAD で origin を直接チェックアウト ==="
git clone -q remote.git consumer2 || exit 1
verif_enter_repo consumer2
git fetch -q --all --prune
git checkout -q --detach "origin/$BR" 2>&1 | sed 's/^/    /'
echo "    -> 終了コード: ${PIPESTATUS[0]}"
echo "    消費側の現在: $(git log --oneline -1) / HEAD=$(git rev-parse --abbrev-ref HEAD)"
