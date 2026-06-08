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

- **`llms-txt-official-repos/`**: llms.txt エコシステムの AnswerDotAI 公式リポジトリを submodule で管理するフォルダ。詳細・ツール間の関係は同フォルダの `README.md` / `CLAUDE.md` 参照
- **`official-llms-txts/`**: ダウンロード済みの公式 llms.txt 等。参照時は同フォルダの `CLAUDE.md`（ナビゲーションファイル）を先に読むと効率的
- **`scripts/dl_llms.sh`**: `official-llms-txts/` への定期ダウンロードスクリプト。実行: `bash LLMs/scripts/dl_llms.sh`（リポジトリルートから）。`scripts/download_list.tsv` でダウンロード対象を管理
- **`scripts/gen-llms-txt/gen_llms.sh`**: `targets.txt` を読み、clone → `gen_llms_full.py` → `validate.sh` を一括実行するバッチエントリ。実行: `bash LLMs/scripts/gen-llms-txt/gen_llms.sh`（リポジトリルートから）。生成物の blockquote / description プレースホルダは未補完で残るため、補完が要る場合は `/generate-llms-txt` Skill を併用する
- WebFetch で `llms.txt` を取得する場合、参照頻度の高いドメインは `.claude/settings.json` の allow リストに既登録あり（`code.claude.com` / `docs.claude.com` / `github.com/anthropics`）。他ドメインは個別に追加する
- **公式ドキュメント更新サマリ（正は専用リポジトリ B `empty-can/LLMs`）**: Claude Code / MCP 公式ドキュメントの更新差分サマリ（人間向け changelog）の生成・日次自動公開は、専用リポジトリ B（`empty-can/LLMs`、`C:\cc-workspace\LLMs`）で正式運用中。**本リポジトリ（A）配下の `official-doc-update-summary/` ・ `/update-official-doc-summary` Skill ・ `doc-summary-reviewer` Agent ・ `run-doc-summary.ps1` 等は当面フォールバックとして残置するが、自動実行は停止済み**（スケジューラ `CC-DocSummaryBot` は B の `run-doc-summary.ps1` を指し、SessionStart notify も B 側 `.claude/settings.json` のみ。A の SessionStart notify は撤去済み）。移行設計は `LLMs/work/publish-migration/migration-plan.md`、A 側フォールバックパイプラインの運用手順は `.claude/scripts/README-doc-summary-bot.md` 参照
