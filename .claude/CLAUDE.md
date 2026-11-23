# .claude/CLAUDE.md

`.claude/` 配下のファイルを Claude が読み書きする際に追加ロードされるガイド。リポジトリ全体の性質・ブランチ運用ルールはルート `CLAUDE.md` 参照。

## `.claude/` 内部構造

```
.claude/
├── CLAUDE.md               # 本ファイル（.claude/ 配下作業時の追加ガイド）
├── settings.json           # 共有設定（permissions + UserPromptSubmit・SessionStart・SubagentStart hook）
├── settings.local.json     # 個人設定 ※gitignore 想定
├── agents/                 # code-reviewer.md / doc-summary-reviewer.md / cross-review-*.md（クロスレビューの担当 6 体）
├── hooks/                  # pre-task-reminder.sh / subagent-start-rules.py（SubagentStart の hook。全部のサブエージェントに共通の決まりを足す）
├── output-styles/          # code-review.md
├── rule-assets/            # rule と hook が読む資産（subagent-common-rules.md・md-self-check/checklist.md）。rule としては読み込まれない
├── rules/                  # path-scoped rule 4 種 ＋ 常時ロードの rule 1 種
├── scripts/                # resolve-activity-dir.sh / statusline.ps1 / notify-bot-branch.sh / doc-summary bot の 3 本（run-doc-summary.ps1 など）
├── skills/                 # 11 Skill
├── templates/              # inter-claude-communication / skill-request
├── workspace/              # 一時作業用（skill-request の作業フォルダ等）
└── reports/                # 流用元での過去調査レポート（design-base-kit / analyze-claude-code-doc-repos）
```

## path-scoped rule の自動ロード連鎖（最重要）

`.claude/rules/*.md` は frontmatter `paths:` でマッチしたファイルを Claude が読むときに自動ロードされる。**触るファイルの種類によってロードされる rule が変わる**ため、ファイル編集前にどの rule が来るかを意識する。

| Rule | 自動ロード条件 |
|---|---|
| `agent-permission-runtime.md` | `**/.claude/agents/*.md` / `**/作業計画書*.md` / `**/v3_作業計画書*.md` / `**/.claude/skills/*/SKILL.md` を読み書きするとき。sub-agent / background Agent 起動前の permission 事前列挙 8 種別チェックリスト（Write/Edit/Bash/PowerShell/MCP/WebFetch/Agent/Read-deny）と検出ベース復旧手順を規定 |
| `coding-standards.md` | `**/*.{js,ts,jsx,tsx,py,go,rs,java,rb,kt,swift,c,cpp,cs}` を編集するとき。命名規則・コメント方針・エラー処理・テスト方針 |
| `md-self-check.md` | `**/*.md` を読み書きするとき（ほぼ常時）。`.md` を執筆・修正したら、完了の報告の前に `.claude/rule-assets/md-self-check/checklist.md` を Read で読んでセルフチェックする（機械的な直しは 1 回の見直し） |
| `skill-creation-guide.md` | `**/.claude/skills/*/SKILL.md` を読み書きするとき。Skill の責務 3 層分離（README.md / SKILL.md / スクリプト）、SKILL.md 記述原則、allowed-tools 絞り込み方針、セルフレビュー観点 |

> **常時ロードの rule**: `chunked-generation.md` は `paths:` を持たず、セッションの起動時に必ずロードされる（サブエージェントにも入る）。1 回の Write・Edit で大量の文章やコードを生成しない（章・節、関数・ファイルごとに分けて書く）、サブエージェントに持たせる量を絞る、大きいファイルを丸ごと読まない、を規定する。`Prompt is too long` などの API のエラーを避けるため。

> **重複ロード**: `.claude/skills/*/SKILL.md` は `agent-permission-runtime.md` と `skill-creation-guide.md` の両方がマッチし得る。同時にロードされる前提で読む。

## Skill 一覧と起動方法

| Skill | 起動方法 | 内容 |
|---|---|---|
| `5-whys` | description トリガで自動起動可（モデル発動型） | 体系的な root cause 分析。Why Chain → 根本原因 → 対策の 5 フェーズ |
| `commit-and-pr` | `/commit-and-pr`（`disable-model-invocation: true`） | ステージング差分を単一コミット → push → `gh pr create` まで一気通貫 |
| `orchestrate` | `/orchestrate`（`disable-model-invocation: true`） | パターン A 並列調査 / B 段階的処理 / C 役割分担。子エージェントの結果統合にメイン会話の文脈が要るため、subagent ではなく Skill としてメインセッションで実行する設計（公式も「メイン会話の文脈で動く再利用可能ワークフローは Skill」を推奨）。**子エージェントの入れ子起動は既定 3 階層まで可**（`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`） |
| `pre-compact` | `/pre-compact` | `/compact` 実行前の事前準備。メモリ最新化 → 未コミット確認 → 継続ポイント収集 → `/compact <指示>` コメント案を提示。ステップ 1・3 は完全 silent 出力禁止 |
| `read-prompt-file` | `/read-prompt-file` | ルート CLAUDE.md「ブランチ運用ルール」で決定される活動フォルダ配下の `.claude/work/prompt.txt` を読み込む |
| `request-new-skill` | `/request-new-skill <概要>` | 新規 Skill 作成依頼書を `.claude/workspace/skill-request/<kebab-case>/` に配置 |
| `review-skill-request` | `/review-skill-request [フォルダ名]` | 記入済み依頼書をレビューし、`skill-cc-response.md` に確認事項・指摘・提案・既存 Skill 調査結果を書き込む |
| `generate-llms-txt` | `/generate-llms-txt [--target <path_or_url>] [--base-url <url>] [--output <dir>] [--extract-sigs]` | ローカルリポジトリまたは GitHub URL から `llms.txt` / `llms-full.txt` を自動生成。ドキュメント抽出（Type A）＋ソースシグネチャ抽出（Type C）に対応。blockquote・description は LLM が自動生成 |
| `update-official-doc-summary` | `/update-official-doc-summary [--from <commit>]`（`disable-model-invocation: true`） | Claude Code 公式ドキュメント（`llms.txt` / `llms-full.txt`）の更新差分を人間向け changelog / リリースノート風 Markdown として生成。詳細版（LLM 生成）+ ライト版（`derive_light.py` で機械抽出、ハイライト/新規追加/大幅更新の見出しを詳細版アンカーへ自動リンク化）の 2 ファイル方式。出力先 `LLMs/official-doc-update-summary/claude-code-docs/`、旧版は `archives/<YYYY-MM-DD>/` へ退避 |
| `check-model` | `/check-model [作業内容の説明]`（モデル発動型。`UserPromptSubmit` の hook の案内からも呼ばれる） | 現セッションのモデルが作業内容に対して過剰・不足でないかを評価し、不適合なら推奨モデルへの切替を提案する |
| `cross-review` | `/cross-review <対象の文書のパス>` で始め、`/cross-review <台帳のパス>` で再開（`disable-model-invocation: true`） | 文書のクロスレビューを、構成の確認から 1.0 版（作業指示者の判断）まで段階 0〜6 で進める。メインのセッションが主担当になり、レビュー・反映・差分の点検・定型の作業は担当の 6 体（`agents/cross-review-*.md`）に任せ、止まる所で作業指示者に伺う。進行は台帳に残し、圧縮・再起動の後も再開できる |

**Skill 追加は二段階フロー**: `/request-new-skill` → ユーザーが `skill-request-form.md` 記入 → `/review-skill-request` → 確認事項クリアで実装着手。

## Sub-agent と output-style

- `agents/code-reviewer.md`（sonnet 指定）: `git diff HEAD` → ファイル精査 → 重大度順で出力。出力は `output-styles/code-review.md` のフォーマット（`[CRITICAL]`/`[IMPORTANT]`/`[SUGGESTION]`/`[POSITIVE]` ラベル）に従う
- `agents/cross-review-*.md`（6 体。skill `cross-review` の進行からだけ起動する）: `logic-reviewer`（論理整合性。opus）・`practicality-reviewer`（実用性。足場でスクリプトを動かす。sonnet）・`reader-reviewer`（作業指示者+人間読み手。構成の確認と仕上げの回。opus）・`reviser`（反映。1 つの文書に 1 体。opus）・`diff-checker`（差分の点検。opus）・`clerk`（定型の作業。haiku）。effort は全部 high。本文は最初に読むファイルの案内だけで、決まりは `skills/cross-review/references/` にある。frontmatter に hook（PreToolUse 2 本・PostToolUse 1 本）を持ち、`Agent` は持たない

> **subagent の `tools` に引数スコープは書けない**（2026-08-29 修正）。`tools` が受け付けるのは**厳密なツール名**か **`mcp__<server>` / `mcp__<server>__*`** だけで、`Bash(git status:*)` のような書き方は「Unrecognized」として**無言で破棄**される（全エントリが解決不能な場合のみ起動拒否。部分不一致はエラーにならない）。`code-reviewer.md` は以前この書き方をしており、**Bash を一切持たない状態で起動していた**。引数レベルで絞りたい場合は `tools` ではなく (1) `settings.json` の `permissions.deny` / `permissions.ask`、(2) `PreToolUse` hook を使う（ただし前者はセッション全体に効き、後者は **plugin 経由の subagent では `hooks` が無視される**）。

## permissions 運用方針

`settings.json`（共有）に追加してよい / しないアクションが `rules/agent-permission-runtime.md` §2.2 で定義されている。要点:

- **追加してよい**: 読み取り系 Bash（`git show:*` / `wc:*` 等）、Write/Edit（作業ディレクトリ配下）、MCP 読み取り系、参照頻度高い WebFetch ドメイン
- **追加しない**（明示確認方針）: 書き込み系 Bash（`git push` / `git reset` / `git commit` / `rm` 等）
- **個人検証用の限定 allow** は `settings.local.json`（gitignore 想定）に追加

sub-agent / background Agent 起動を含む作業の着手前には **8 種別の permission 事前列挙**（Write / Edit / Bash / PowerShell / MCP / WebFetch / Agent / Read-deny 該当）を実施する。詳細は `rules/agent-permission-runtime.md` §1。

## クロスレビュー運用

skill `cross-review`（`/cross-review`）で進める。メインのセッションが主担当として段階 0（準備）〜6（作業指示者の判断・1.0 版）を進め、担当の 6 体（`agents/cross-review-*.md`）を起動する。版の進み方・上限・止まる所は `skills/cross-review/SKILL.md` が正（段階ごとの詳細は `references/段階ごとの手順.md`、クロスレビューに固有の決まりは `references/rules.md`、報告書・依頼文の雛型は `templates/`）。

- 担当のコマンドと書き込み先は、定義の frontmatter の hook（`skills/cross-review/scripts/hook_*.py`）が止める。hook の設定は、主担当が段階 0 で `.claude/workspace/cross-review-hook.json`（未追跡）に置く。無い・壊れている・雛型のままだと、担当は全部止まる
- `.md` の反復セルフチェックは rule `md-self-check.md` とチェックリスト `rule-assets/md-self-check/checklist.md` による（クロスレビューの外でも効く）

## settings.json の hook（UserPromptSubmit・SessionStart・SubagentStart）と個人通知 hook

`settings.json`（共有）の `UserPromptSubmit` hook は `bash .claude/hooks/pre-task-reminder.sh` を実行し、メインのセッションで作業指示者がプロンプトを送るたびに、モデルの妥当性（skill `check-model`）と `/compact` の要否（skill `pre-compact`）の確認を促す文を足す（skill が無ければその分を出さない）。`SessionStart` hook は `bash .claude/scripts/notify-bot-branch.sh` を実行し、doc-summary-bot ブランチに未確定の自動生成サマリ（`feature/LLMs` へ未マージの bot コミット）が残っていれば通知する（OS 中立コマンドのみを使う方針）。`settings.json`（共有）の `SubagentStart` hook は `python -I -X utf8 ${CLAUDE_PROJECT_DIR}/.claude/hooks/subagent-start-rules.py` を実行し、全部の種類のサブエージェントの起動時に `.claude/rule-assets/subagent-common-rules.md` の全文を文脈の先頭に足す（再開しても二重には入らない。ファイルが無い・9,000 字を超えるときは何も足さない）。この hook は上の方針の例外で `python` を要する（`python` で起動できない環境では hook が失敗する）。`git status --short` を実行する SessionStart hook と、Notification / TaskCompleted / PostToolUseFailure / PermissionRequest / Stop の音声・効果音 hook は `settings.local.json` に個人用として配置されており、Windows の `SoundPlayer` + `SAPI.SpVoice` を使う。

## 流用元由来の参照に関する注意

`.claude/` 配下には流用元 `base-dev-kit-for-cc` の歴史的文脈が残っている。本リポジトリでは解決しない参照例:

- `rules/agent-permission-runtime.md` §4 の F02-001 backlog 参照（`research-for-local-RAG-for-cc/improvements/F02-001_...`）
- `reports/design-base-kit/` 配下の調査 A〜G および計画書（`base-kit-構成プラン.md`）
- `skills/review-skill-request/SKILL.md` の `C:\workspace\claude-doc-repositories\anthropics\claude-plugins-official\plugins\` パス

> **⚠ `reports/design-base-kit/` は 2026-04 時点の調査記録であり、公式仕様の現状とは一致しない**。特に調査G / `base-kit-構成プラン.md` が結論の根拠に置く「Subagents cannot spawn other subagents」は**公式が撤回済み**（既定でメイン会話の 3 階層下まで入れ子起動可。`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`）。時点記録として本文は書き換えないので、**設計判断の根拠として再利用しないこと**。現行の運用ルールは `rules/agent-permission-runtime.md` が正。

これらは流用元での運用経緯の記録であり、削除せず保持している。**本リポジトリで運用ルールを改訂する場合は、これらの記述を本リポジトリの実態に合わせて書き換える**（特にブランチ運用ルールは既に書き換え済み）。
