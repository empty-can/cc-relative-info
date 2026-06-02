---
対象期間: 2026年05月31日 〜 2026年06月02日
作成日: 2026-06-02
---

# Claude Code 公式ドキュメント更新サマリ

> 今回の更新は新着情報（週間ダイジェスト）2 件分で、Week 21・Week 22 で告知された主要機能と多数の小規模改善が反映されています。リファレンス／ガイドページ自体の新規追加・大幅更新はありません。
>
> 主要なものを以下に挙げます。
>
> 1. Claude Opus 4.8 が Max / Team Premium / Enterprise pay-as-you-go / Anthropic API の新しいデフォルトモデルに
> 2. 動的ワークフロー（Dynamic workflows、research preview）で多数のサブエージェントをスクリプトからオーケストレーション
> 3. security-guidance プラグインが Claude のコード変更を脆弱性観点でレビューし同一セッション内で修正
> 4. Fast モードが Opus 4.8 に対応（$10 / $50 per MTok）
> 5. Auto モードが Pro プランと Sonnet 4.6 に対応

## ハイライト

1. [**Claude Opus 4.8 リリース**](./latest-detail.md#1-claude-opus-48-リリース):  
  Max / Team Premium / Enterprise pay-as-you-go / Anthropic API の新しいデフォルトモデル。デフォルトで high effort、最難タスクには `/effort xhigh`。v2.1.154 以降が必要。
2. [**動的ワークフロー**](./latest-detail.md#2-動的ワークフロー):  
  Claude がタスク用に書き起こすオーケストレーションスクリプトを、多数のサブエージェントでバックグラウンド実行する research preview 機能。`/workflows` で管理。
3. [**security-guidance プラグイン**](./latest-detail.md#3-security-guidance-プラグイン):  
  Claude のコード変更を脆弱性観点でレビューし同一セッション内で修正するプラグイン。編集時の高速パターンチェック・ターン終了時のモデルレビュー・コミット／プッシュ時の詳細レビューの 3 段構え。
4. [**Opus 4.8 での Fast モード**](./latest-detail.md#4-opus-48-での-fast-モード):  
  Fast モードのデフォルトが Opus 4.8（$10 / $50 per MTok、標準の 2 倍の料金で約 2.5 倍の速度）に。Opus 4.6 の Fast モードは非推奨化。
5. [**Pro プランでの Auto モード**](./latest-detail.md#5-pro-プランでの-auto-モード):  
  Auto モードが Pro プランでも利用可能になり Sonnet 4.6 に対応。パーミッションプロンプトをバックグラウンドの安全性チェックに置き換える。

## 新規追加されたページ

*(リファレンス／ガイドの新規追加ページはありません)*

## 大幅に更新されたページ

*(大幅に更新されたページはありません)*

## 軽微な更新

*(軽微な更新はありません)*

## 新着情報

- [**2026年05月18日～22日(Week 21)**](./latest-detail.md#2026年05月18日22日week-21) ([日本語](https://code.claude.com/docs/ja/whats-new/2026-w21) / [English](https://code.claude.com/docs/en/whats-new/2026-w21)):  
  Pro プランでの Auto モード対応を目玉に、`/usage` のカテゴリ別内訳、新しい `/code-review` コマンド、バックグラウンドセッションの `/resume` 表示など。
- [**2026年05月25日～29日(Week 22)**](./latest-detail.md#2026年05月25日29日week-22) ([日本語](https://code.claude.com/docs/ja/whats-new/2026-w22) / [English](https://code.claude.com/docs/en/whats-new/2026-w22)):  
  Claude Opus 4.8 リリースを目玉に、動的ワークフロー、security-guidance プラグイン、Opus 4.8 での Fast モードなど 4 機能。

## 関連リンク

- (初版のため、前回サマリはありません)

<!--
base_commit: 21ff319
head_commit: d4a9a8aaebd53fd9593d3c9cba8cb7e60b0e36a4
generated_at_full: 2026-06-02T01:36:15+09:00
-->
