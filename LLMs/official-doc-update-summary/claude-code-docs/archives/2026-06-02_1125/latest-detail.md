---
対象期間: 2026年06月02日 〜 2026年06月02日
作成日: 2026-06-02
---

# Claude Code 公式ドキュメント更新サマリ - 詳細版

<!-- light:summary:start -->
> 今回の更新はリファレンスページ 1 件の新規追加が中心で、MCP サーバー接続用のクイックスタートページが新設されました。既存ページの大幅更新や新着情報（週間ダイジェスト）はありません。
>
> 主要なものを以下に挙げます。
>
> 1. MCP サーバー接続用のクイックスタートページ「MCP サーバーに接続する」が新設
<!-- light:summary:end -->

## ハイライト

<!-- light:highlight-list:start -->
1. [**MCP サーバー接続クイックスタートの新設**](#1-mcp-サーバー接続クイックスタートの新設):  
  MCP サーバーの追加・接続確認・設定ファイルの所在確認までを最短手順で案内する入門ページ。包括的な `mcp` ページとは別に、初学者向けの導線として MCP セクションに新設された。
<!-- light:highlight-list:end -->

## 1. MCP サーバー接続クイックスタートの新設

新しいクイックスタートページ「MCP サーバーに接続する」（`mcp-quickstart`）が追加されました。MCP サーバーを Claude Code に追加し、接続を検証し、ディスク上の設定ファイルの所在を確認するまでの最短手順を扱う入門ページです。既存の包括的な `mcp`（MCP 経由でツールに接続する）ページが網羅的な解説であるのに対し、本ページは最初の 1 台を動かすことに絞った導線になっています。

ページは「サーバーの追加と確認」「サーバーの保存場所（ディスク上の設定の探し方）」「サーバースコープの変更（全プロジェクトでの利用・チームでの共有）」「追加例（ローカルサーバーの追加・サインインが必要なサーバーへの接続）」「`.mcp.json` の直接編集」「他のサーフェスからの接続」「トラブルシューティング」といった節で構成されます。あわせてドキュメントの章立ても再編され、これまで「Tools and plugins」にまとめられていた MCP・Skills・Plugins が、それぞれ独立したトップレベルセクションへ分割されました。新設の `mcp-quickstart` はこの MCP セクション内に、包括版の `mcp` ページと並んで配置されています。

- [MCP サーバーに接続する - Claude Code Docs (日本語)](https://code.claude.com/docs/ja/mcp-quickstart)
- [Connect to MCP servers - Claude Code Docs (English)](https://code.claude.com/docs/en/mcp-quickstart)

## 新規追加されたページ

<!-- light:new-pages:start -->
- [**MCP サーバーに接続する**](#1-mcp-サーバーに接続する) ([日本語](https://code.claude.com/docs/ja/mcp-quickstart) / [English](https://code.claude.com/docs/en/mcp-quickstart)):  
  MCP サーバーの追加から接続確認、スコープ変更、`.mcp.json` の直接編集までを段階的に解説する入門ページ。
<!-- light:new-pages:end -->

## 1. MCP サーバーに接続する

「MCP サーバーに接続する」（`mcp-quickstart`）は、MCP サーバーを Claude Code に追加して接続を確認し、設定ファイルがディスク上のどこに保存されるかを把握するまでを順を追って解説する新規ページです。

節構成は「始める前に」「サーバーの追加と確認」「サーバーの保存場所（ディスク上の設定の探し方）」「サーバースコープの変更（全プロジェクトでの利用／チームでの共有）」「MCP サーバーの追加例（ローカルサーバーの追加／サインインが必要なサーバーへの接続）」「`.mcp.json` の直接編集」「他のサーフェスからの接続」「トラブルシューティング」「次のステップ」となっており、初めて MCP を導入するユーザーが一通りの流れを追えるようになっています。

- [MCP サーバーに接続する - Claude Code Docs (日本語)](https://code.claude.com/docs/ja/mcp-quickstart)
- [Connect to MCP servers - Claude Code Docs (English)](https://code.claude.com/docs/en/mcp-quickstart)

## 大幅に更新されたページ

<!-- light:updated-pages:start -->
*(大幅に更新されたページはありません)*
<!-- light:updated-pages:end -->

## 軽微な更新

<!-- light:minor-updates:start -->
- [日本語](https://code.claude.com/docs/ja/hooks-guide) / [English](https://code.claude.com/docs/en/hooks-guide):  
  フックのガイドページのタイトルが「Automate workflows with hooks」から「Automate actions with hooks」へ変更されました（内容は同一で表現の調整）。
- [日本語](https://code.claude.com/docs/ja/changelog) / [English](https://code.claude.com/docs/en/changelog):  
  v2.1.159（2026年05月31日）が追記されました。内部インフラの改善のみで、ユーザー向けの変更はありません。
- [日本語](https://code.claude.com/docs/ja/goal) / [English](https://code.claude.com/docs/en/goal):  
  `/goal` ページの見出しが「Compare to other autonomous workflows」から「Compare ways to keep a session running」へ改称されました。
- [日本語](https://code.claude.com/docs/ja/interactive-mode) / [English](https://code.claude.com/docs/en/interactive-mode):  
  インタラクティブモードのリファレンスに、プラグインの有効化・無効化操作の項目が追加されました。
- [日本語](https://code.claude.com/docs/ja/troubleshooting) / [English](https://code.claude.com/docs/en/troubleshooting):  
  トラブルシューティングページに、バックグラウンドサービスが応答しないケースと、macOS でバックグラウンドセッションがデスクトップ・書類・ダウンロードフォルダを読めないケースの 2 項目が追加されました。
<!-- light:minor-updates:end -->

## 新着情報

<!-- light:whats-new:start -->
*(今回の対象期間に新着情報（週間ダイジェスト）の更新はありません)*
<!-- light:whats-new:end -->

## 関連リンク

- 前回サマリ(ライト版): [./archives/2026-06-02/latest.md](./archives/2026-06-02/latest.md)
- 前回サマリ(詳細版): [./archives/2026-06-02/latest-detail.md](./archives/2026-06-02/latest-detail.md)

<!--
base_commit: d4a9a8aaebd53fd9593d3c9cba8cb7e60b0e36a4
head_commit: 2e5333166f191bf5c6e336edbf92daeda50feebd
generated_at_full: 2026-06-02T11:25:52+09:00
-->
