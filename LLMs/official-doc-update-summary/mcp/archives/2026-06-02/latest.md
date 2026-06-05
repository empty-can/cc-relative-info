---
対象期間: 2026年05月29日 〜 2026年06月02日
作成日: 2026-06-02
---

# MCP 公式ドキュメント更新サマリ

> 今回の更新はリファレンスページの新規追加・大幅更新は無く、既存ページの本文改修が中心です。Tool Header Parameters（SEP-2243）と Tasks 拡張（SEP-2663）の仕様の厳格化・整理が主な変更で、ほかにクライアント対応の拡大とワーキンググループ運営情報の更新があります。
>
> 主要なものを以下に挙げます。
>
> 1. SEP-2243（HTTP ヘッダ標準化）: `x-mcp-header` の制約厳格化（RFC 9110 トークン準拠・`number` 型禁止→integer 限定・ネスト許可・base64 センチネル衝突回避 ほか）
> 2. SEP-2663（Tasks 拡張）: 後方互換性の表形式整理（`2025-11-25` ↔ `2026-06-30`）とエラーコード `-32003` の追加

## ハイライト

1. [**SEP-2243 HTTP ヘッダ標準化**](./latest-detail.md#1-sep-2243-http-ヘッダ標準化):  
  Streamable HTTP transport のツールヘッダパラメータ（`x-mcp-header`）の制約が厳格化。RFC 9110 トークン構文準拠・制御文字禁止・`number` 型禁止（integer 限定）・任意ネスト許可・base64 センチネル衝突回避などが追加された。
2. [**SEP-2663 Tasks 拡張**](./latest-detail.md#2-sep-2663-tasks-拡張):  
  エラーコード `-32003`（Missing Required Client Capability）の追加と、後方互換性記述の表形式整理（`2025-11-25` の実験的 tasks と `2026-06-30` の本拡張の挙動マトリクス化）。

## 新規追加されたページ

*(リファレンスページの新規追加はありません)*

## 大幅に更新されたページ

*(大幅に更新されたページはありません)*

## 軽微な更新

- [MCP Apps](https://modelcontextprotocol.io/extensions/apps/overview) / [Extension Support Matrix](https://modelcontextprotocol.io/extensions/client-matrix):  
  サポートクライアントに Archestra.AI を追加（Extension Support Matrix にも対応状況を追記）。
- [Skills Over MCP Charter](https://modelcontextprotocol.io/community/skills-over-mcp/charter) / [Tool Annotations Charter](https://modelcontextprotocol.io/community/tool-annotations/charter):  
  ワーキンググループ／インタレストグループの membership 更新（参加者の追加）。

## 関連リンク

- (初版のため、前回サマリはありません)

<!--
base_commit: 534cac6
head_commit: 5eba50e20508f9a33b6e9ca4dff9f48b8afb601b
generated_at_full: 2026-06-02T03:11:18+09:00
-->
