#!/bin/bash
# LLMs/scripts/dl_llms.sh
#
# download_list.csv に定義された URL から llms.txt 等を取得し、
# LLMs/official-llms-txts/ 配下の指定フォルダに保存する。
#
# 実行方法（リポジトリルートから）:
#   bash LLMs/scripts/dl_llms.sh
#
# 注意: CSV の DL先フォルダ列は LLMs/official-llms-txts/ からの相対パス。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CSV_FILE="${SCRIPT_DIR}/download_list.csv"
OUTPUT_BASE="${SCRIPT_DIR}/../official-llms-txts"

# CSV の相対パス解決のため出力ベースに cd
cd "$OUTPUT_BASE" || { echo "ERROR: cannot cd to $OUTPUT_BASE"; exit 1; }

# ヘッダ行をスキップして読み込み
tail -n +2 "$CSV_FILE" | while IFS=',' read -r url filename folder overwrite_flag
do
    # 空行スキップ
    [ -z "$url" ] && continue

    echo "----------------------------------------"
    echo "Downloading: $url"

    # 保存先フォルダ作成
    mkdir -p "$folder"

    # 保存先ファイルパス
    filepath="$folder/$filename"

    # 上書きフラグを小文字化
    flag=$(echo "$overwrite_flag" | tr '[:upper:]' '[:lower:]')

    # TRUE または 1 の場合
    if [[ "$flag" == "true" || "$flag" == "1" ]]; then

        echo "Overwrite mode: ENABLED"

        # 強制上書きダウンロード
        curl -L -f "$url" -o "$filepath"

    else

        echo "Overwrite mode: DISABLED"

        # 既存ファイルが存在する場合
        if [ -e "$filepath" ]; then

            # archive フォルダ作成
            archive_dir="$folder/archive"
            mkdir -p "$archive_dir"

            # タイムスタンプ生成
            timestamp=$(date +"%Y%m%d_%H%M")

            # ファイル名と拡張子分離
            base="${filename%.*}"
            ext="${filename##*.}"

            # 拡張子なし対応
            if [ "$base" = "$ext" ]; then
                archive_name="${base}_${timestamp}"
            else
                archive_name="${base}_${timestamp}.${ext}"
            fi

            archive_path="$archive_dir/$archive_name"

            echo "Existing file found."
            echo "Move to archive:"
            echo "  $filepath"
            echo "  -> $archive_path"

            # archiveへ移動
            mv "$filepath" "$archive_path"
        fi

        # ダウンロード
        curl -L -f "$url" -o "$filepath"

    fi

    # 実行結果確認
    if [ $? -eq 0 ]; then
        echo "Success: $filepath"
    else
        echo "Failed: $url"
    fi

done
