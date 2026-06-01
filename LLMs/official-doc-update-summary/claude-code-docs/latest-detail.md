---
対象期間: 2026年05月31日 〜 2026年06月02日
作成日: 2026-06-02
---

# Claude Code 公式ドキュメント更新サマリ - 詳細版

<!-- light:summary:start -->
> 今回の更新は新着情報（週間ダイジェスト）2 件分で、Week 21・Week 22 で告知された主要機能と多数の小規模改善が反映されています。リファレンス／ガイドページ自体の新規追加・大幅更新はありません。
>
> 主要なものを以下に挙げます。
>
> 1. Claude Opus 4.8 が Max / Team Premium / Enterprise pay-as-you-go / Anthropic API の新しいデフォルトモデルに
> 2. 動的ワークフロー（Dynamic workflows、research preview）で多数のサブエージェントをスクリプトからオーケストレーション
> 3. security-guidance プラグインが Claude のコード変更を脆弱性観点でレビューし同一セッション内で修正
> 4. Fast モードが Opus 4.8 に対応（$10 / $50 per MTok）
> 5. Auto モードが Pro プランと Sonnet 4.6 に対応
<!-- light:summary:end -->

## ハイライト

<!-- light:highlight-list:start -->
1. [**Claude Opus 4.8 リリース**](#1-claude-opus-48-リリース):  
  Max / Team Premium / Enterprise pay-as-you-go / Anthropic API の新しいデフォルトモデル。デフォルトで high effort、最難タスクには `/effort xhigh`。v2.1.154 以降が必要。
2. [**動的ワークフロー**](#2-動的ワークフロー):  
  Claude がタスク用に書き起こすオーケストレーションスクリプトを、多数のサブエージェントでバックグラウンド実行する research preview 機能。`/workflows` で管理。
3. [**security-guidance プラグイン**](#3-security-guidance-プラグイン):  
  Claude のコード変更を脆弱性観点でレビューし同一セッション内で修正するプラグイン。編集時の高速パターンチェック・ターン終了時のモデルレビュー・コミット／プッシュ時の詳細レビューの 3 段構え。
4. [**Opus 4.8 での Fast モード**](#4-opus-48-での-fast-モード):  
  Fast モードのデフォルトが Opus 4.8（$10 / $50 per MTok、標準の 2 倍の料金で約 2.5 倍の速度）に。Opus 4.6 の Fast モードは非推奨化。
5. [**Pro プランでの Auto モード**](#5-pro-プランでの-auto-モード):  
  Auto モードが Pro プランでも利用可能になり Sonnet 4.6 に対応。パーミッションプロンプトをバックグラウンドの安全性チェックに置き換える。
<!-- light:highlight-list:end -->

## 1. Claude Opus 4.8 リリース

Opus 4.8 が Max / Team Premium / Enterprise pay-as-you-go / Anthropic API の各プランで新しいデフォルトモデルになりました。デフォルトの effort は high で、より難しいタスクには `/effort xhigh` を指定します。利用には v2.1.154 以降が必要です。

モデル名を直接指定（`/model claude-opus-4-8`）するか、モデルピッカーから選択して切り替えます。

- [モデル設定 - Claude Code Docs (日本語)](https://code.claude.com/docs/ja/model-config)
- [Model configuration - Claude Code Docs (English)](https://code.claude.com/docs/en/model-config)

## 2. 動的ワークフロー

動的ワークフローは、Claude がタスクに合わせて書き起こすオーケストレーションスクリプトで、バックグラウンドで多数のサブエージェントにまたがって実行されます。1 つの会話では調整しきれない大規模タスク（コードベース全体の監査、大規模マイグレーション、クロスチェックが必要な調査）に向いています。

プロンプトに「workflow」という語を含めて依頼し、実行は `/workflows` で管理します。research preview として提供されています。

- [動的ワークフローで複数のサブエージェントを大規模にオーケストレーションする - Claude Code Docs (日本語)](https://code.claude.com/docs/ja/workflows)
- [Orchestrate subagents at scale with dynamic workflows - Claude Code Docs (English)](https://code.claude.com/docs/en/workflows)

## 3. security-guidance プラグイン

security-guidance プラグインは、Claude のコード変更を脆弱性の観点でレビューし、同一セッション内で修正します。各編集時に高速なパターンチェック、各ターン終了時にモデルによるレビュー、コミットまたはプッシュ時により深いエージェント的レビューを実行します。プロジェクト固有のルールは `.claude/claude-security-guidance.md` に記述できます。

公式 Anthropic マーケットプレイスから `/plugin install security-guidance@claude-plugins-official` でインストールし、`/reload-plugins` で現在のセッションに反映します。

- [Claude がコードを書く際にセキュリティ問題を検出する - Claude Code Docs (日本語)](https://code.claude.com/docs/ja/security-guidance)
- [Catch security issues as Claude writes code - Claude Code Docs (English)](https://code.claude.com/docs/en/security-guidance)

## 4. Opus 4.8 での Fast モード

Fast モードのデフォルトが Opus 4.8 になり、$10 / $50 per MTok（標準の 2 倍の料金で約 2.5 倍の速度）で利用できます。Opus 4.7 と 4.6 は $30 / $150 のまま据え置きで、Opus 4.6 の Fast モードは非推奨となりました。

`/fast` でトグルします。

- [高速モードで応答を高速化する - Claude Code Docs (日本語)](https://code.claude.com/docs/ja/fast-mode)
- [Speed up responses with fast mode - Claude Code Docs (English)](https://code.claude.com/docs/en/fast-mode)

## 5. Pro プランでの Auto モード

Auto モードが Pro プランでも利用可能になり、Opus に加えて Sonnet 4.6 をサポートします。パーミッションプロンプトをバックグラウンドの安全性チェックに置き換え、ルーチンな操作は中断せずに実行し、破壊的・不審な操作はブロックして提示します。

Claude Code を更新後、Shift+Tab でモードを循環させると、アカウントが要件を満たした時点で auto モードが表示されます。

- [パーミッションモードを選択する - Claude Code Docs (日本語)](https://code.claude.com/docs/ja/permission-modes)
- [Choose a permission mode - Claude Code Docs (English)](https://code.claude.com/docs/en/permission-modes)

## 新規追加されたページ

<!-- light:new-pages:start -->
*(リファレンス／ガイドの新規追加ページはありません)*
<!-- light:new-pages:end -->

## 大幅に更新されたページ

<!-- light:updated-pages:start -->
*(大幅に更新されたページはありません)*
<!-- light:updated-pages:end -->

## 軽微な更新

<!-- light:minor-updates:start -->
*(軽微な更新はありません)*
<!-- light:minor-updates:end -->

## 新着情報

<!-- light:whats-new:start -->
- [**2026年05月18日～22日(Week 21)**](#2026年05月18日22日week-21) ([日本語](https://code.claude.com/docs/ja/whats-new/2026-w21) / [English](https://code.claude.com/docs/en/whats-new/2026-w21)):  
  Pro プランでの Auto モード対応を目玉に、`/usage` のカテゴリ別内訳、新しい `/code-review` コマンド、バックグラウンドセッションの `/resume` 表示など。
- [**2026年05月25日～29日(Week 22)**](#2026年05月25日29日week-22) ([日本語](https://code.claude.com/docs/ja/whats-new/2026-w22) / [English](https://code.claude.com/docs/en/whats-new/2026-w22)):  
  Claude Opus 4.8 リリースを目玉に、動的ワークフロー、security-guidance プラグイン、Opus 4.8 での Fast モードなど 4 機能。
<!-- light:whats-new:end -->

## 2026年05月18日～22日(Week 21)

Week 21（リリース v2.1.143 → v2.1.149）の目玉は Pro プランでの Auto モード対応です。Auto モードが Pro アカウントで動作するようになり、Opus に加えて Sonnet 4.6 をサポートします。パーミッションプロンプトをバックグラウンドの安全性チェックに置き換え、ルーチンな操作は中断せず、破壊的・不審な操作はブロックします。

その他の改善: `/usage` がスキル・サブエージェント・プラグイン・個別 MCP サーバごとにプラン上限の消費内訳を表示するようになりました。「Extra usage」が「usage credits」に、`/extra-usage` が `/usage-credits` に改称されました（旧名も引き続き有効）。新しい `/code-review` コマンドが指定した effort レベル（例 `/code-review high`）で正確性バグを報告し、`--comment` で GitHub PR にインラインコメントを投稿します（`/simplify` はクリーンアップ専用レビューとして存続）。バックグラウンドセッションが `bg` 印付きで `/resume` に表示され、`claude agents` で `Ctrl+T` ピン留めしたセッションはアイドル時も維持されます。`claude agents --json` でライブセッションを JSON 出力できます。Windows の Bedrock / Vertex / Foundry ユーザーで PowerShell ツールがデフォルト有効化されました（`CLAUDE_CODE_USE_POWERSHELL_TOOL=0` でオプトアウト）。ほかに `worktree.bgIsolation: "none"` 設定の追加、GFM タスクリストのチェックボックス描画、ステータスライン JSON への GitHub リポジトリ／PR 情報追加などがあります。

- [Week 21・2026年05月18日〜22日 - Claude Code Docs (日本語)](https://code.claude.com/docs/ja/whats-new/2026-w21)
- [Week 21 · May 18–22, 2026 - Claude Code Docs (English)](https://code.claude.com/docs/en/whats-new/2026-w21)

## 2026年05月25日～29日(Week 22)

Week 22（リリース v2.1.150 → v2.1.157）では 4 つの機能が追加されました。Claude Opus 4.8 が複数プランの新デフォルトモデルに、動的ワークフロー（research preview）が多数のサブエージェントをスクリプトからオーケストレーション、security-guidance プラグインが Claude のコード変更を脆弱性観点でレビュー、Fast モードが Opus 4.8 に対応（$10 / $50 per MTok）しました。

その他の改善: `claude agents` でシェルコマンドを `!` で前置するとアタッチ／デタッチ可能なバックグラウンドジョブとして実行できます（`claude --bg --exec 'pytest -x'` も同様）。`.claude/skills` 配下のプラグインがマーケットプレイス不要で自動ロードされ、`claude plugin init <name>` で新規プラグインを雛形生成できます。新しい `/reload-skills` コマンドで再起動なしにスキルディレクトリを再スキャンでき、`SessionStart` フックが `reloadSkills: true` を返すと同一セッション内でスキルが利用可能になります。スキル／コマンドが frontmatter で `disallowed-tools` を指定してモデルからツールを除外できます。新しい `MessageDisplay` フックイベントで表示テキストを変換・非表示にできます。プライマリモデルが見つからない場合、リクエストごとに失敗する代わりに残りのセッションで `--fallback-model` へ自動切替します。Vim モードの NORMAL で `/` が逆方向履歴検索を開きます。ストリーミングツール実行が常時有効化され、`claude mcp list` / `claude mcp get` は未承認 `.mcp.json` サーバを保留中として表示します。

- [Week 22・2026年05月25日〜29日 - Claude Code Docs (日本語)](https://code.claude.com/docs/ja/whats-new/2026-w22)
- [Week 22 · May 25–29, 2026 - Claude Code Docs (English)](https://code.claude.com/docs/en/whats-new/2026-w22)

## 関連リンク

- (初版のため、前回サマリはありません)

<!--
base_commit: 21ff319
head_commit: d4a9a8aaebd53fd9593d3c9cba8cb7e60b0e36a4
generated_at_full: 2026-06-02T01:36:15+09:00
-->
