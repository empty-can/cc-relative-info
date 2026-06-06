---
対象期間: 2026年06月05日 〜 2026年06月06日
作成日: 2026-06-06
---

# Claude Code 公式ドキュメント更新サマリ

> 今回の更新は新規ページの追加・週間ダイジェスト（新着情報）はなく、既存リファレンスへの機能追記と挙動の明確化が中心です。クラウドプロバイダー横断のモデルエイリアス解決の見直し、起動バージョン管理の強化に加え、フック・プラグイン・MCP・Agent SDK・監視まわりの細かな改善が広く入りました。
>
> 主要なものを以下に挙げます。
>
> 1. モデルエイリアス（`opus` / `sonnet` 等）が「最新版」ではなく組み込みデフォルトに解決される旨へ各プロバイダーの記述を更新
> 2. バージョン範囲外での起動を拒否する管理設定 `requiredMinimumVersion` / `requiredMaximumVersion` を追加
> 3. Stop / SubagentStop フックが会話を継続したままフィードバックを渡せる `additionalContext` に対応
> 4. `claude -p` 起動のバックグラウンドタスクを終了後約 5 秒で自動停止
> 5. `/plugin` のサブコマンド対応（`/plugin list` 等）

## ハイライト

1. [**モデルエイリアス解決の仕様変更**](./latest-detail.md#1-モデルエイリアス解決の仕様変更):  
  `opus` / `sonnet` などのエイリアスが「最新版」ではなく「Claude Code 組み込みのデフォルト」に解決される旨へ、Bedrock・Vertex AI・Foundry・Claude Platform on AWS とエラー／モデル設定の記述が一斉更新された。AWS では `opus` が Opus 4.7 に解決されると明記。
2. [**バージョン範囲を強制する管理設定の追加**](./latest-detail.md#2-バージョン範囲を強制する管理設定の追加):  
  `requiredMinimumVersion` / `requiredMaximumVersion` が追加され、実行中バージョンが許可範囲外なら Claude Code が起動を拒否する。ダウングレードのみ抑止する `minimumVersion` より強い。
3. [**Stop・SubagentStop フックの additionalContext 対応**](./latest-detail.md#3-stopsubagentstop-フックの-additionalcontext-対応):  
  Stop / SubagentStop フックが `hookSpecificOutput.additionalContext` を返せるようになり、フックエラー扱いにせず会話を継続したまま Claude にフィードバックを渡せる。
4. [**ヘッドレス実行終了時のバックグラウンドタスク自動停止**](./latest-detail.md#4-ヘッドレス実行終了時のバックグラウンドタスク自動停止):  
  `claude -p` が起動したバックグラウンド Bash タスクは、最終結果の返却・stdin クローズから約 5 秒後に終了するようになった。終了しないタスクが実行を無期限に保持する問題が解消。
5. [**/plugin サブコマンドの追加**](./latest-detail.md#5-plugin-サブコマンドの追加):  
  `/plugin` がメニューを開かず `list` / `install` / `enable` / `disable` を直接実行できるようになり、`/plugin list`（`--enabled` / `--disabled` フィルタ付き）でインストール済みプラグインを一覧できる。

## 新規追加されたページ

*(新規追加されたページはありません)*

## 大幅に更新されたページ

- [**フックリファレンス**](./latest-detail.md#1-フックリファレンスの更新) ([日本語](https://code.claude.com/docs/ja/hooks) / [English](https://code.claude.com/docs/en/hooks)):  
  共通フィールド `if` の Bash マッチング挙動が表で詳細化され、`prompt` フックのエスケープ構文や Stop / SubagentStop の `additionalContext` を含む複数のフック仕様の追記がまとまった。
- [**SDK のサブエージェント**](./latest-detail.md#2-sdk-のサブエージェント定義再開の刷新) ([日本語](https://code.claude.com/docs/ja/agent-sdk/subagents) / [English](https://code.claude.com/docs/en/agent-sdk/subagents)):  
  サブエージェントの定義表に `initialPrompt` が追加され、再開（resume）手順とコード例が Python・TypeScript 双方で刷新された。

## 軽微な更新

- [日本語](https://code.claude.com/docs/ja/commands) / [English](https://code.claude.com/docs/en/commands):  
  スラッシュコマンド表の説明が複数更新されました。`/keybindings` は「キーボードショートカット設定ファイルを開く」、`/reload-plugins` は `--force` を受け付け（再読み込みで MCP ツール構成が変わりプロンプトキャッシュが無効化される場合は警告してスキップ。プロンプトキャッシュのページにも同旨が追記）、`/remote-env` は「クラウドエージェントの既定環境を選ぶ」、`/tasks` は「バックグラウンドで動作中のすべてを表示・管理」と表現が改められています。
- [日本語](https://code.claude.com/docs/ja/env-vars) / [English](https://code.claude.com/docs/en/env-vars):  
  環境変数の記述を更新。`CLAUDE_CODE_FORK_SUBAGENT` は `0` で無効化（サーバー側の段階的ロールアウトを上書き）できる旨を追記（サブエージェントのページにも同旨の説明を追加）、`CLAUDE_CODE_SESSION_ID` は `--resume <session-id>` で再開 ID を受け取る旨を追記。`CLAUDE_CODE_TMPDIR` はサンドボックス化された Bash のみ短い代替 `$TMPDIR` を受け取り非サンドボックスのコマンドはシェルの `$TMPDIR` をそのまま継承する点、`MCP_TOOL_TIMEOUT` は 1000 未満の扱い（env 変数は 1 秒に切り上げ、サーバー個別フィールドは無視）を明確化。新規に `CLAUDE_CODE_SYNC_SKILLS_INSTALL_TIMEOUT_MS`（セッション途中のスキル再同期のタイムアウト、既定 30000ms）が追加されました。
- [日本語](https://code.claude.com/docs/ja/mcp) / [English](https://code.claude.com/docs/en/mcp):  
  `claude mcp add` の `--` 区切りの説明が「オプション順序」から「サーバー引数を `--` で区切る」へ刷新され、`--env` の直後にサーバー名を置くと別の `KEY=value` と誤読されるため間に他のオプションを挟む注意が追記。サーバー個別 `timeout` が 1000 未満のとき無視されて `MCP_TOOL_TIMEOUT` にフォールバックする（v2.1.162 より前は 1 秒に切り上げ）旨、Microsoft 365・Gmail・Google Calendar など一部 Anthropic ホスト型コネクタはローカル OAuth 非対応で claude.ai 側で接続する案内（v2.1.162 から）も追加されました。
- [日本語](https://code.claude.com/docs/ja/monitoring-usage) / [English](https://code.claude.com/docs/en/monitoring-usage):  
  OpenTelemetry の監視まわりに追記。新しいイベント「API refusal event」（`claude_code.api_refusal`）が追加され、API が `stop_reason: "refusal"` を返したとき（HTTP エラーではなく正常レスポンスとして届くため `api_error` が発火しない）に拒否頻度を追跡できます。`claude_code.tool` スパンに `tool_use_id` / `gen_ai.tool.call.id`、MCP 接続イベントにプラグイン由来を示す `is_plugin` / `plugin_id_hash` / `plugin.name`、スキルイベントに `skill.kind` が追加されました。
- [日本語](https://code.claude.com/docs/ja/tools-reference) / [English](https://code.claude.com/docs/en/tools-reference):  
  WebFetch の挙動説明に、ビルトインの事前承認済みドキュメントドメインは初回でもプロンプトなしにフェッチできる旨と、`deny` / `ask` / `allow` の明示的な `WebFetch(domain:...)` ルールが事前承認セットより優先される旨が追記。LSP ツールの機能一覧は「ファイル内のシンボル列挙」と「ワークスペース全体でのシンボル名検索」に分けて記載されました。
- [日本語](https://code.claude.com/docs/ja/vs-code) / [English](https://code.claude.com/docs/en/vs-code):  
  VS Code 拡張のアンインストール時に拡張データも削除する手順が、macOS / Linux / Windows 別のパスに分けて明記されました（Linux のパスが `~/.config/Code/User/globalStorage/...` に修正）。
- [日本語](https://code.claude.com/docs/ja/agent-sdk/python) / [English](https://code.claude.com/docs/en/agent-sdk/python):  
  Python SDK リファレンスの `ResultMessage` に、`subtype`（`"success"` / `"error_*"` の各種別）と、エラー時の診断用フィールド `is_error` / `api_error_status` / `result` / `errors` の挙動説明が追加されました。
- [日本語](https://code.claude.com/docs/ja/settings) / [English](https://code.claude.com/docs/en/settings):  
  既定のコミット属性表記が変更され、従来の「🤖 Generated with [Claude Code]...」行が削除されて `Co-Authored-By` 行のみになり、trailer のモデル名はセッションのアクティブモデルを反映する旨が追記されました。
- [日本語](https://code.claude.com/docs/ja/skills) / [English](https://code.claude.com/docs/en/skills):  
  スキルのコマンド本文で、数字や `ARGUMENTS`・宣言済み引数名の前にリテラルの `$`（例: `$1.00`）を表示するためのバックスラッシュエスケープ構文 `\$` が追記されました。
- [日本語](https://code.claude.com/docs/ja/hooks-guide) / [English](https://code.claude.com/docs/en/hooks-guide):  
  フック自動化ガイドの `if` フィルタ説明にも、パターンの形状と Bash コマンドに応じてフックが起動するかどうかを示すマッチング表が追加されました。
- [日本語](https://code.claude.com/docs/ja/agent-view) / [English](https://code.claude.com/docs/en/agent-view):  
  `claude agents --json` の出力で、セッションが `waiting` のとき `waitingFor` が「`permission prompt`」「`input needed`」のように何で止まっているかを示す旨が追記されました。
- [日本語](https://code.claude.com/docs/ja/deep-links) / [English](https://code.claude.com/docs/en/deep-links):  
  外部リンクからセッションを起動した際の表示が、入力欄上のバナーから入力欄下の警告行（`Prompt from an external link`、送信・クリアまで表示）に変更されました。1,000 文字超のプロンプトでは文字数も表示されます。起動セッションのウェルカムヘッダーは選択したパスのみを示す簡潔な記述に改められています。
- [日本語](https://code.claude.com/docs/ja/interactive-mode) / [English](https://code.claude.com/docs/en/interactive-mode):  
  `/btw` の回答オーバーレイに `c` キーが追加され、回答を生の Markdown としてクリップボードにコピーできるようになりました（端末の折り返しを含むマウス選択の代わりに使う想定）。
- [日本語](https://code.claude.com/docs/ja/memory) / [English](https://code.claude.com/docs/en/memory):  
  `/init` が既存の `AGENTS.md` に加えて、他ツールの設定として `.cursorrules` / `.devin/rules/` / `.windsurfrules` も読み込む旨が追記されました。
- [日本語](https://code.claude.com/docs/ja/troubleshoot-install) / [English](https://code.claude.com/docs/en/troubleshoot-install):  
  接続確認コマンドについて、PowerShell では `curl` が `Invoke-WebRequest` のエイリアスで `-sI` を受け付けないため `curl.exe -sI` を使う、という注記が追加されました。
- [日本語](https://code.claude.com/docs/ja/setup) / [English](https://code.claude.com/docs/en/setup):  
  初回起動時の案内文が、「ウェルカム画面にセッション情報・最近の会話・最新情報が表示される」から「バージョン・現在のモデル・作業ディレクトリがプロンプト上部に表示される」という記述に改められました。
- [日本語](https://code.claude.com/docs/ja/changelog) / [English](https://code.claude.com/docs/en/changelog):  
  Changelog ページのタイトルが索引上で「Changelog」から「Claude Code changelog」に変更され、v2.1.163・v2.1.165 のリリースエントリが追加されました（本サマリで扱った各機能を含む多数の修正・改善）。

## 新着情報

*(今回の対象期間に新着情報（週間ダイジェスト）の更新はありません)*

## 関連リンク

- 前回サマリ(ライト版): [./archives/2026-06-05/latest.md](./archives/2026-06-05/latest.md)
- 前回サマリ(詳細版): [./archives/2026-06-05/latest-detail.md](./archives/2026-06-05/latest-detail.md)

<!--
base_commit: 1e3e2b137e7caf8898440f8f3e9733bb21fc7fdf
head_commit: e5de99c411b81e86652a5d7f00210938b6465bf3
generated_at_full: 2026-06-06T13:09:17+09:00
-->
