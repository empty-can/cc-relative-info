---
対象期間: 2026年06月02日 〜 2026年06月05日
作成日: 2026-06-05
---

# Claude Code 公式ドキュメント更新サマリ

> 今回の更新は既存ページへの小規模な追記が中心で、新規ページの追加・既存ページの大幅な書き換え・新着情報（週間ダイジェスト）はありません。クラウドプロバイダーでの auto mode 有効化、fast mode とプロンプトキャッシュのコスト、コンテキスト管理、動的ワークフローへの入力など、運用面の細かな改善がまとまっています。
>
> 主要なものを以下に挙げます。
>
> 1. クラウドプロバイダー（Bedrock・Vertex AI・Foundry）での auto mode 有効化手順が追記
> 2. fast mode 有効化時にプロンプトキャッシュが一度無効化されるコストの解説が追加
> 3. コンテキストが埋まる前に取れる能動的な対処（`/compact` 集中・`/clear`・サブエージェント委譲）が整理
> 4. 保存済みワークフローへ実行時に入力を渡す `args` の解説が追加

## ハイライト

1. [**クラウドプロバイダーでの auto mode 有効化**](./latest-detail.md#1-クラウドプロバイダーでの-auto-mode-有効化):  
  Bedrock・Vertex AI・Foundry では環境変数 `CLAUDE_CODE_ENABLE_AUTO_MODE=1` を設定するまで auto mode が `Shift+Tab` サイクルに現れない。対応は v2.1.158 以降・Opus 4.7/4.8 のみ。
2. [**fast mode 有効化時のプロンプトキャッシュのコスト**](./latest-detail.md#2-fast-mode-有効化時のプロンプトキャッシュのコスト):  
  fast mode を有効化すると会話履歴全体がキャッシュ未ヒットで読み直され、その分が fast mode 料金で課金される。コストは会話ごとに一度のみで、以降のオン・オフ切り替えはキャッシュを保持する。
3. [**コンテキストが埋まる前に取れる対処**](./latest-detail.md#3-コンテキストが埋まる前に取れる対処):  
  自動コンパクション任せにせず、指示付き `/compact`・`/clear`・サブエージェントへの読み込み委譲で能動的にコンテキストを管理する方法が整理された。
4. [**保存済みワークフローへの入力受け渡し**](./latest-detail.md#4-保存済みワークフローへの入力受け渡し):  
  保存済み動的ワークフローが `args` パラメータで実行時入力を受け取れるようになり、スクリプトを編集せずに問い・対象パス・設定を渡せる。

## 新規追加されたページ

*(新規追加されたページはありません)*

## 大幅に更新されたページ

*(大幅に更新されたページはありません)*

## 軽微な更新

- [日本語](https://code.claude.com/docs/ja/agent-sdk/typescript) / [English](https://code.claude.com/docs/en/agent-sdk/typescript):  
  TypeScript Agent SDK リファレンスに、新しいメッセージ型 `SDKCommandsChangedMessage` が追加されました。サブディレクトリへ移動してスキルが検出されるなど、セッション途中で利用可能なコマンド集合が変化したときに発行され、`commands` 配列が更新後の全リストになります。初期化時のスナップショットを返す `supportedCommands()` の再呼び出しでは反映されない点が補足されています。
- [日本語](https://code.claude.com/docs/ja/agent-sdk/hooks) / [English](https://code.claude.com/docs/en/agent-sdk/hooks):  
  フックのレシピ見出しが「Filter with regex matchers」から「Filter with multi-tool matchers」へ改称され、複数ツールマッチャーで 1 つのコールバックを共有する例が示されました。パイプ区切りの完全一致リスト（`Write|Edit|Delete`）・正規表現（`^mcp__`）・マッチャー省略（全ツール対象）の 3 つのスコープを使い分けられます。
- [日本語](https://code.claude.com/docs/ja/troubleshooting) / [English](https://code.claude.com/docs/en/troubleshooting):  
  トラブルシューティングに、VS Code・Cursor・Devin Desktop の統合ターミナルで文字が箱・かすれ・誤ったグリフとして描画されるケースが追加されました。多くはターミナルの GPU レンダラーが原因で、`/terminal-setup` の実行（`terminal.integrated.gpuAcceleration` を `"off"` に設定）で対処できます。
- [日本語](https://code.claude.com/docs/ja/changelog) / [English](https://code.claude.com/docs/en/changelog):  
  Changelog ページのタイトルが索引上で「Changelog」から「Claude Code changelog」に変更されました（表記の明確化のみで内容に変更はありません）。

## 新着情報

*(今回の対象期間に新着情報（週間ダイジェスト）の更新はありません)*

## 関連リンク

- 前回サマリ(ライト版): [./archives/2026-06-02_1125/latest.md](./archives/2026-06-02_1125/latest.md)
- 前回サマリ(詳細版): [./archives/2026-06-02_1125/latest-detail.md](./archives/2026-06-02_1125/latest-detail.md)

<!--
base_commit: 2e5333166f191bf5c6e336edbf92daeda50feebd
head_commit: 1e3e2b137e7caf8898440f8f3e9733bb21fc7fdf
generated_at_full: 2026-06-05T22:16:14+09:00
-->
