# LLMs/CLAUDE.md

`LLMs/` 配下のファイルを Claude が読み書きする際に追加ロードされるガイド。フォルダの目的・現状の概略は `README.md` 参照。

## このフォルダの目標

1. **`llms.txt` の定期取り込み**: Claude Code の利用に有用な各種公式団体の公式ドキュメント（Anthropic / Claude Code / MCP 公式団体 等）が公開する `llms.txt` を本フォルダ配下に保存・更新する
2. **`llms.txt` の生成**: `llms.txt` が存在しないドキュメント・リポジトリについて、`llms.txt` を作成する仕組みを構築する

## 運用方針（未整備項目）

- 取り込み対象の一覧（どの公式団体・どのドキュメント）は未定
- 更新頻度・取り込みトリガ（定期 cron / 手動 / hook 等）は未定
- 保存パス命名規則は未定
- 生成スクリプト・テンプレートは未作成
- 仕組み構築の進捗に応じて、本ファイルに手順を追記する

## 関連

- **`llms-txt-official/`**: AnswerDotAI/llms-txt の git submodule（本フォルダ直下 `LLMs/llms-txt-official`）。llms.txt 仕様の公式実装・CLI ツール・仕様書（`nbs/index.qmd`）を含む。更新: `git submodule update --remote LLMs/llms-txt-official`（リポジトリルートから実行）
- WebFetch で `llms.txt` を取得する場合、参照頻度の高いドメインは `.claude/settings.json` の allow リストに既登録あり（`code.claude.com` / `docs.claude.com` / `github.com/anthropics`）。他ドメインは個別に追加する
- 取り込み・生成スクリプトを実装する場合は、汎用 `.claude/scripts/` ではなく本フォルダ配下に配置する案を第一に検討する（用途がこのフォルダに閉じるため）
