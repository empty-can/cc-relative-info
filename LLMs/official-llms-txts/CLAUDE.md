# LLMs/official-llms-txts/CLAUDE.md

各公式サイトからダウンロードした `llms.txt` 等を格納するフォルダ。

## llms.txt と llms-full.txt について

[公式仕様（llms-txt-official/nbs/index.qmd）](../llms-txt-official/nbs/index.qmd) に基づく。

- **`llms.txt`**: サイト名（H1）・概要（blockquote）・ページリスト（URL＋1行説明）で構成された軽量なインデックスファイル。コンテキスト消費を抑えたい場合や「どのページがあるか」を把握したいときに参照する（約 100〜150 行）
- **`llms-full.txt`**: `llms.txt` にリストされた各 URL の全文を展開・結合した完全版。`llms_txt2ctx` ツールで生成される。特定機能の詳細仕様・設定値・コード例を検索したいときに参照する（数万行になる場合あり）

## サブフォルダ

| フォルダ | サイト | 内容 |
|---|---|---|
| `code.claude.com/docs/` | Claude Code 公式ドキュメント | Claude Code の設定・機能・SDK・hooks・skills・MCP 連携等 |
| `modelcontextprotocol.io/` | MCP 公式ドキュメント | Model Context Protocol の仕様・クライアント/サーバー実装・認証等 |

## llms.txt 以外のファイル

### `code.claude.com/docs/en/claude_code_docs_map.md`

Claude Code 全ドキュメントページの見出し構造を階層的にまとめたマップファイル。GitHub Actions で自動生成（最終更新日時がファイル内に記載）。`llms.txt` の各リンクに対応するページの **内部見出し構成** を事前に把握できるため、`llms-full.txt` から目当てのセクションを探す前の絞り込みに有効。

セクション構成: Getting started / Core concepts / Use Claude Code / Platforms and integrations / Agents and parallel work / Tools and plugins / Automation / Troubleshooting / Setup and access / Deployment 他。
