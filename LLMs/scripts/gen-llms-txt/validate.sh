#!/usr/bin/env bash
# llms.txt が llms_txt2ctx で正常に展開できるかを確認する。
# 使用例: bash validate.sh llms.txt
# 成功: "OK: <ファイル名>" を表示して exit 0
# 失敗: エラー内容を表示して exit 1

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage: $(basename "$0") <llms.txt>" >&2
    exit 1
fi

TARGET="$1"

if [ ! -f "$TARGET" ]; then
    echo "ERROR: File not found: $TARGET" >&2
    exit 1
fi

if ! command -v llms_txt2ctx &>/dev/null; then
    echo "ERROR: llms_txt2ctx not found. Install with: pip install llm-ctx" >&2
    exit 1
fi

if PYTHONUTF8=1 llms_txt2ctx "$TARGET" > /dev/null 2>&1; then
    echo "OK: $TARGET"
else
    echo "FAIL: $TARGET"
    PYTHONUTF8=1 llms_txt2ctx "$TARGET" 2>&1 || true
    exit 1
fi
