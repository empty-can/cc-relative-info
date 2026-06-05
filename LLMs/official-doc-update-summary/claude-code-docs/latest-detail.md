---
対象期間: 2026年06月02日 〜 2026年06月05日
作成日: 2026-06-05
---

# Claude Code 公式ドキュメント更新サマリ - 詳細版

<!-- light:summary:start -->
> 今回の更新は既存ページへの小規模な追記が中心で、新規ページの追加・既存ページの大幅な書き換え・新着情報（週間ダイジェスト）はありません。クラウドプロバイダーでの auto mode 有効化、fast mode とプロンプトキャッシュのコスト、コンテキスト管理、動的ワークフローへの入力など、運用面の細かな改善がまとまっています。
>
> 主要なものを以下に挙げます。
>
> 1. クラウドプロバイダー（Bedrock・Vertex AI・Foundry）での auto mode 有効化手順が追記
> 2. fast mode 有効化時にプロンプトキャッシュが一度無効化されるコストの解説が追加
> 3. コンテキストが埋まる前に取れる能動的な対処（`/compact` 集中・`/clear`・サブエージェント委譲）が整理
> 4. 保存済みワークフローへ実行時に入力を渡す `args` の解説が追加
<!-- light:summary:end -->

## ハイライト

<!-- light:highlight-list:start -->
1. [**クラウドプロバイダーでの auto mode 有効化**](#1-クラウドプロバイダーでの-auto-mode-有効化):  
  Bedrock・Vertex AI・Foundry では環境変数 `CLAUDE_CODE_ENABLE_AUTO_MODE=1` を設定するまで auto mode が `Shift+Tab` サイクルに現れない。対応は v2.1.158 以降・Opus 4.7/4.8 のみ。
2. [**fast mode 有効化時のプロンプトキャッシュのコスト**](#2-fast-mode-有効化時のプロンプトキャッシュのコスト):  
  fast mode を有効化すると会話履歴全体がキャッシュ未ヒットで読み直され、その分が fast mode 料金で課金される。コストは会話ごとに一度のみで、以降のオン・オフ切り替えはキャッシュを保持する。
3. [**コンテキストが埋まる前に取れる対処**](#3-コンテキストが埋まる前に取れる対処):  
  自動コンパクション任せにせず、指示付き `/compact`・`/clear`・サブエージェントへの読み込み委譲で能動的にコンテキストを管理する方法が整理された。
4. [**保存済みワークフローへの入力受け渡し**](#4-保存済みワークフローへの入力受け渡し):  
  保存済み動的ワークフローが `args` パラメータで実行時入力を受け取れるようになり、スクリプトを編集せずに問い・対象パス・設定を渡せる。
<!-- light:highlight-list:end -->

## 1. クラウドプロバイダーでの auto mode 有効化

Amazon Bedrock・Google Cloud Vertex AI・Microsoft Foundry では、環境変数 `CLAUDE_CODE_ENABLE_AUTO_MODE` を `1` に設定するまで auto mode が `Shift+Tab` の切り替えサイクルに現れません。この変数は Claude Code v2.1.158 以降で機能し、これらのプロバイダーでサポートされるのは Claude Opus 4.7 と Opus 4.8 のみです。

開発者単位で有効化する場合は、`~\.claude\settings.json` の `env` ブロックに `"CLAUDE_CODE_ENABLE_AUTO_MODE": "1"` を追加します。権限モードの選択ページの auto mode 解説に、この有効化手順が追記されました。

- [権限モードを選ぶ - Claude Code Docs (日本語)](https://code.claude.com/docs/ja/permission-modes)
- [Choose a permission mode - Claude Code Docs (English)](https://code.claude.com/docs/en/permission-modes)

## 2. fast mode 有効化時のプロンプトキャッシュのコスト

fast mode を有効化するとキャッシュキーの一部となるリクエストヘッダーが付くため、その直後のリクエストは会話履歴全体をキャッシュヒットなしで読み直します。このキャッシュ未ヒット分の入力トークンは fast mode 料金で課金されるため、セッション開始時に有効化する方が、長いセッションの途中で有効化するよりコストが小さくなります。なお、非 Opus モデルから fast mode を有効化するとモデル切り替えも発生し、それ自体が新しいキャッシュを開始します。

このコストは会話ごとに一度だけ発生します。最初の fast mode ターン以降は同じヘッダーが送られ続け、キャッシュキーに含まれない速度設定だけが変わります。そのため fast mode のオフ切り替え・レート制限後の標準速度への自動フォールバック・再度のオン切り替えはいずれもキャッシュを保持します（`/clear` と `/compact` はこの時点でキャッシュを作り直すためリセットされます）。なお、切り替えをまたいでヘッダーを保持する挙動には Claude Code v2.1.86 以降が必要です。

- [Claude Code のプロンプトキャッシュの仕組み - Claude Code Docs (日本語)](https://code.claude.com/docs/ja/prompt-caching)
- [How Claude Code uses prompt caching - Claude Code Docs (English)](https://code.claude.com/docs/en/prompt-caching)

## 3. コンテキストが埋まる前に取れる対処

コンテキストウィンドウを探るページに、コンテキストが上限に近づいたときの能動的な対処をまとめた節が追加されました。Claude Code は上限に近づくと自動でコンパクションを行うため、コンテキストウィンドウが一杯になってもセッションは終了しませんが、自動処理が走る前に手を打つこともできます。

具体的には、長い新規タスクを始める前に `/compact focus on the auth bug fix` のように指示付きでコンパクションして残す内容を自分で選ぶ方法、無関係な作業へ移る際に `/clear` でクリアする方法、大きなファイル読み込みをサブエージェントに委譲して本体のコンテキストを消費しない方法が挙げられています。会話を縮めるのではなくより大きなウィンドウが必要な場合は、Opus 4.6 以降と Sonnet 4.6 が 100 万トークンのコンテキストウィンドウに対応している点も案内されています。

- [コンテキストウィンドウを探る - Claude Code Docs (日本語)](https://code.claude.com/docs/ja/context-window)
- [Explore the context window - Claude Code Docs (English)](https://code.claude.com/docs/en/context-window)

## 4. 保存済みワークフローへの入力受け渡し

動的ワークフローのページに、保存済みワークフローへ実行時に入力を渡す方法が追加されました。保存済みワークフローは `args` パラメータを通じて入力を受け取れ、スクリプト側は `args` という名前のグローバル変数として読み取ります。実行のたびにスクリプトを編集する代わりに、リサーチの問い・対象パスのリスト・設定オブジェクトなどを起動時に渡せます。

例えば「`Run /triage-issues on issues 1024, 1025, and 1030`」のように指示すると、Claude はそのリストを構造化データとして渡すため、スクリプトは `args` に対して配列・オブジェクトのメソッドを解析なしで直接呼び出せます。`args` を省略した場合、スクリプト内のグローバル変数は `undefined` になります。

- [動的ワークフローでサブエージェントを大規模にオーケストレーションする - Claude Code Docs (日本語)](https://code.claude.com/docs/ja/workflows)
- [Orchestrate subagents at scale with dynamic workflows - Claude Code Docs (English)](https://code.claude.com/docs/en/workflows)

## 新規追加されたページ

<!-- light:new-pages:start -->
*(新規追加されたページはありません)*
<!-- light:new-pages:end -->

## 大幅に更新されたページ

<!-- light:updated-pages:start -->
*(大幅に更新されたページはありません)*
<!-- light:updated-pages:end -->

## 軽微な更新

<!-- light:minor-updates:start -->
- [日本語](https://code.claude.com/docs/ja/agent-sdk/typescript) / [English](https://code.claude.com/docs/en/agent-sdk/typescript):  
  TypeScript Agent SDK リファレンスに、新しいメッセージ型 `SDKCommandsChangedMessage` が追加されました。サブディレクトリへ移動してスキルが検出されるなど、セッション途中で利用可能なコマンド集合が変化したときに発行され、`commands` 配列が更新後の全リストになります。初期化時のスナップショットを返す `supportedCommands()` の再呼び出しでは反映されない点が補足されています。
- [日本語](https://code.claude.com/docs/ja/agent-sdk/hooks) / [English](https://code.claude.com/docs/en/agent-sdk/hooks):  
  フックのレシピ見出しが「Filter with regex matchers」から「Filter with multi-tool matchers」へ改称され、複数ツールマッチャーで 1 つのコールバックを共有する例が示されました。パイプ区切りの完全一致リスト（`Write|Edit|Delete`）・正規表現（`^mcp__`）・マッチャー省略（全ツール対象）の 3 つのスコープを使い分けられます。
- [日本語](https://code.claude.com/docs/ja/troubleshooting) / [English](https://code.claude.com/docs/en/troubleshooting):  
  トラブルシューティングに、VS Code・Cursor・Devin Desktop の統合ターミナルで文字が箱・かすれ・誤ったグリフとして描画されるケースが追加されました。多くはターミナルの GPU レンダラーが原因で、`/terminal-setup` の実行（`terminal.integrated.gpuAcceleration` を `"off"` に設定）で対処できます。
- [日本語](https://code.claude.com/docs/ja/changelog) / [English](https://code.claude.com/docs/en/changelog):  
  Changelog ページのタイトルが索引上で「Changelog」から「Claude Code changelog」に変更されました（表記の明確化のみで内容に変更はありません）。
<!-- light:minor-updates:end -->

## 新着情報

<!-- light:whats-new:start -->
*(今回の対象期間に新着情報（週間ダイジェスト）の更新はありません)*
<!-- light:whats-new:end -->

## 関連リンク

- 前回サマリ(ライト版): [./archives/2026-06-02_1125/latest.md](./archives/2026-06-02_1125/latest.md)
- 前回サマリ(詳細版): [./archives/2026-06-02_1125/latest-detail.md](./archives/2026-06-02_1125/latest-detail.md)

<!--
base_commit: 2e5333166f191bf5c6e336edbf92daeda50feebd
head_commit: 1e3e2b137e7caf8898440f8f3e9733bb21fc7fdf
generated_at_full: 2026-06-05T22:16:14+09:00
-->
