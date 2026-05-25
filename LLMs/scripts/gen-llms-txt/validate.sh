#!/usr/bin/env bash
# llms.txt が llms_txt2ctx で正常に展開できるかを確認する。
# セクションごとに先頭 MAX_SAMPLE_PER_SECTION 件をサンプリングして検証するため、
# 大規模リポジトリ（数千リンク）でもタイムアウトしない。
#
# 使用例: bash validate.sh llms.txt
# 成功: "OK: <file>" または "OK (sampled N/M links): <file>" を表示して exit 0
# 失敗: エラー内容を表示して exit 1

set -euo pipefail

# 1 セクションあたりの最大サンプル数（運用しながら調整）
MAX_SAMPLE_PER_SECTION=10

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

# セクションごとに先頭 MAX_SAMPLE_PER_SECTION 件だけ残したサンプルファイルを生成
tmpfile=$(mktemp)
trap 'rm -f "$tmpfile"' EXIT

awk -v max="$MAX_SAMPLE_PER_SECTION" '
    /^## / { sec_count = 0 }
    /^\- \[/ {
        sec_count++
        if (sec_count > max) { next }
    }
    { print }
' "$TARGET" > "$tmpfile"

total_links=$(grep -cE '^\- \[' "$TARGET") || total_links=0
sampled_links=$(grep -cE '^\- \[' "$tmpfile") || sampled_links=0

if PYTHONUTF8=1 llms_txt2ctx "$tmpfile" > /dev/null 2>&1; then
    if [ "$sampled_links" -eq "$total_links" ]; then
        echo "OK: $TARGET"
    else
        echo "OK (sampled ${sampled_links}/${total_links} links): $TARGET"
    fi
else
    echo "FAIL: $TARGET"
    PYTHONUTF8=1 llms_txt2ctx "$tmpfile" 2>&1 || true
    exit 1
fi
