# .claude/CLAUDE.md

`.claude/` 配下のファイルを Claude が読み書きする際に追加ロードされるガイド。リポジトリ全体の性質・ブランチ運用ルールはルート `CLAUDE.md` 参照。

## `.claude/` 内部構造

```
.claude/
├── CLAUDE.md               # 本ファイル（.claude/ 配下作業時の追加ガイド）
├── settings.json           # 共有設定（permissions + SessionStart hook）
├── settings.local.json     # 個人設定 ※gitignore 想定
├── agents/                 # code-reviewer.md
├── output-styles/          # code-review.md
├── rules/                  # path-scoped rule 4 種
├── scripts/                # resolve-activity-dir.sh / statusline.ps1
├── skills/                 # 7 Skill
├── templates/              # cross-review / inter-claude-communication / skill-request
├── workspace/              # 一時作業用（skill-request の作業フォルダ等）
└── reports/                # 流用元での過去調査レポート（design-base-kit / analyze-claude-code-doc-repos）
```

## path-scoped rule の自動ロード連鎖（最重要）

`.claude/rules/*.md` は frontmatter `paths:` でマッチしたファイルを Claude が読むときに自動ロードされる。**触るファイルの種類によってロードされる rule が変わる**ため、ファイル編集前にどの rule が来るかを意識する。

| Rule | 自動ロード条件 |
|---|---|
| `agent-permission-runtime.md` | `**/.claude/agents/*.md` / `**/作業計画書*.md` / `**/v3_作業計画書*.md` / `**/.claude/skills/*/SKILL.md` を読み書きするとき。sub-agent / background Agent 起動前の permission 事前列挙 8 種別チェックリスト（Write/Edit/Bash/PowerShell/MCP/WebFetch/Agent/Read-deny）と検出ベース復旧手順を規定 |
| `cross-review-runtime.md` | `**/レビュー/**/*.md` / `.claude/templates/cross-review/*.md` を読み書きするとき。レビューア・レビューイ・作業指示者の 3 ロール × 0.8/0.9/1.0 版フロー、セルフレビュー上限、レビューア確認セクション仕様、判断依頼サマリ運用を規定（v3.0α 暫定運用中） |
| `coding-standards.md` | `**/*.{js,ts,jsx,tsx,py,go,rs,java,rb,kt,swift,c,cpp,cs}` を編集するとき。命名規則・コメント方針・エラー処理・テスト方針 |
| `skill-creation-guide.md` | `**/.claude/skills/*/SKILL.md` を読み書きするとき。Skill の責務 3 層分離（README.md / SKILL.md / スクリプト）、SKILL.md 記述原則、allowed-tools 絞り込み方針、セルフレビュー観点 |

> **重複ロード**: `.claude/skills/*/SKILL.md` は `agent-permission-runtime.md` と `skill-creation-guide.md` の両方がマッチし得る。同時にロードされる前提で読む。

## Skill 一覧と起動方法

| Skill | 起動方法 | 内容 |
|---|---|---|
| `5-whys` | description トリガで自動起動可（モデル発動型） | 体系的な root cause 分析。Why Chain → 根本原因 → 対策の 5 フェーズ |
| `commit-and-pr` | `/commit-and-pr`（`disable-model-invocation: true`） | ステージング差分を単一コミット → push → `gh pr create` まで一気通貫 |
| `orchestrate` | `/orchestrate`（`disable-model-invocation: true`） | パターン A 並列調査 / B 段階的処理 / C 役割分担。**Subagents cannot spawn other subagents** の仕様制約があるため、Skill としてメインセッションで実行する設計 |
| `pre-compact` | `/pre-compact` | `/compact` 実行前の事前準備。メモリ最新化 → 未コミット確認 → 継続ポイント収集 → `/compact <指示>` コメント案を提示。ステップ 1・3 は完全 silent 出力禁止 |
| `read-prompt-file` | `/read-prompt-file` | ルート CLAUDE.md「ブランチ運用ルール」で決定される活動フォルダ配下の `.claude/work/prompt.txt` を読み込む |
| `request-new-skill` | `/request-new-skill <概要>` | 新規 Skill 作成依頼書を `.claude/workspace/skill-request/<kebab-case>/` に配置 |
| `review-skill-request` | `/review-skill-request [フォルダ名]` | 記入済み依頼書をレビューし、`skill-cc-response.md` に確認事項・指摘・提案・既存 Skill 調査結果を書き込む |

**Skill 追加は二段階フロー**: `/request-new-skill` → ユーザーが `skill-request-form.md` 記入 → `/review-skill-request` → 確認事項クリアで実装着手。

## Sub-agent と output-style

- `agents/code-reviewer.md`（sonnet 指定）: `git diff HEAD` → ファイル精査 → 重大度順で出力。出力は `output-styles/code-review.md` のフォーマット（`[CRITICAL]`/`[IMPORTANT]`/`[SUGGESTION]`/`[POSITIVE]` ラベル）に従う

## permissions 運用方針

`settings.json`（共有）に追加してよい / しないアクションが `rules/agent-permission-runtime.md` §2.2 で定義されている。要点:

- **追加してよい**: 読み取り系 Bash（`git show:*` / `wc:*` 等）、Write/Edit（作業ディレクトリ配下）、MCP 読み取り系、参照頻度高い WebFetch ドメイン
- **追加しない**（明示確認方針）: 書き込み系 Bash（`git push` / `git reset` / `git commit` / `rm` 等）
- **個人検証用の限定 allow** は `settings.local.json`（gitignore 想定）に追加

sub-agent / background Agent 起動を含む作業の着手前には **8 種別の permission 事前列挙**（Write / Edit / Bash / PowerShell / MCP / WebFetch / Agent / Read-deny 該当）を実施する。詳細は `rules/agent-permission-runtime.md` §1。

## クロスレビュー運用

`templates/cross-review/` に 3 テンプレ（論理整合性 / 実用性 / 作業指示者レビュー）。バージョン進行は `0.8`（レビュアー Round 1）→ `0.9`（レビューイ Round 2 ＋ レビューア Round 3）→ `1.0`（作業指示者）。**0.9 版は「レビューア最終所見・修正案反映まで」を含む**（Round 2 で立ち止まらない）。レビュー報告書を書き始めると `cross-review-runtime.md` が自動ロードされるので、その時点で詳細仕様（セルフレビュー上限・確認セクション仕様・件数表運用等）に従う。

## settings.json の SessionStart hook と個人通知 hook

`settings.json` の `SessionStart` hook が `git status --short` を実行する（OS 中立コマンドのみを使う方針）。Notification / TaskCompleted / PostToolUseFailure / PermissionRequest / Stop の音声・効果音 hook は `settings.local.json` に個人用として配置されており、Windows の `SoundPlayer` + `SAPI.SpVoice` を使う。

## 流用元由来の参照に関する注意

`.claude/` 配下には流用元 `base-dev-kit-for-cc` の歴史的文脈が残っている。本リポジトリでは解決しない参照例:

- `rules/agent-permission-runtime.md` §4 の F02-001 backlog 参照（`research-for-local-RAG-for-cc/improvements/F02-001_...`）
- `rules/cross-review-runtime.md` 末尾の `research-for-local-RAG-for-cc/ドキュメント執筆ガイドライン.md`
- `templates/cross-review/README.md` の `research-for-xxx/CLAUDE.md` 表記
- `reports/design-base-kit/` 配下の調査 A〜G および計画書（`base-kit-構成プラン.md`）
- `skills/review-skill-request/SKILL.md` の `C:\workspace\claude-doc-repositories\anthropics\claude-plugins-official\plugins\` パス

これらは流用元での運用経緯の記録であり、削除せず保持している。**本リポジトリで運用ルールを改訂する場合は、これらの記述を本リポジトリの実態に合わせて書き換える**（特にブランチ運用ルールは既に書き換え済み）。
