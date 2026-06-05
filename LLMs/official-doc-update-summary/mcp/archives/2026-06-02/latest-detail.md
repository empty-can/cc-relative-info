---
対象期間: 2026年05月29日 〜 2026年06月02日
作成日: 2026-06-02
---

# MCP 公式ドキュメント更新サマリ - 詳細版

<!-- light:summary:start -->
> 今回の更新はリファレンスページの新規追加・大幅更新は無く、既存ページの本文改修が中心です。Tool Header Parameters（SEP-2243）と Tasks 拡張（SEP-2663）の仕様の厳格化・整理が主な変更で、ほかにクライアント対応の拡大とワーキンググループ運営情報の更新があります。
>
> 主要なものを以下に挙げます。
>
> 1. SEP-2243（HTTP ヘッダ標準化）: `x-mcp-header` の制約厳格化（RFC 9110 トークン準拠・`number` 型禁止→integer 限定・ネスト許可・base64 センチネル衝突回避 ほか）
> 2. SEP-2663（Tasks 拡張）: 後方互換性の表形式整理（`2025-11-25` ↔ `2026-06-30`）とエラーコード `-32003` の追加
<!-- light:summary:end -->

## ハイライト

<!-- light:highlight-list:start -->
1. [**SEP-2243 HTTP ヘッダ標準化**](#1-sep-2243-http-ヘッダ標準化):  
  Streamable HTTP transport のツールヘッダパラメータ（`x-mcp-header`）の制約が厳格化。RFC 9110 トークン構文準拠・制御文字禁止・`number` 型禁止（integer 限定）・任意ネスト許可・base64 センチネル衝突回避などが追加された。
2. [**SEP-2663 Tasks 拡張**](#2-sep-2663-tasks-拡張):  
  エラーコード `-32003`（Missing Required Client Capability）の追加と、後方互換性記述の表形式整理（`2025-11-25` の実験的 tasks と `2026-06-30` の本拡張の挙動マトリクス化）。
<!-- light:highlight-list:end -->

## 1. SEP-2243 HTTP ヘッダ標準化

Streamable HTTP transport におけるツールヘッダパラメータ（`x-mcp-header`）の仕様が厳格化されました。値の制約が「ASCII 文字（空白と `:` を除く）」から RFC 9110 のフィールド名トークン構文（`1*tchar`）準拠に変わり、制御文字（CR `\r` / LF `\n`）が明示的に禁止されました。適用可能な型からは `number` が除外され integer・string・boolean に限定され（integer は JavaScript の安全範囲 −2^53+1〜2^53−1）、さらに `inputSchema` 内のトップレベルに限らず任意のネスト階層のプロパティへ適用できるようになりました。reject 義務は Streamable HTTP transport を使うクライアントに限定され、stdio など他の transport は `x-mcp-header` アノテーションを無視してよいことが明記されました。

加えて値エンコーディングでは `number`→`integer` へ表記が変更され、base64 センチネル（`=?base64?...?=`）が大文字小文字を区別する旨と、プレーン ASCII 値がセンチネルパターンに一致してしまう場合も base64 エンコードする衝突回避ルールが追加されました。ヘッダ値とボディ値の整数は文字列ではなく数値として比較すべき（`42.0` と `42` は等価）、`inputSchema` 未取得・キャッシュ失効時はカスタムヘッダを送らず必要に応じて `tools/list` 後にリトライする、中間装置はミラーされたヘッダで方針判断する際に `MCP-Protocol-Version` を検証すべき、といった Implementation Note も追加されています。

- [SEP-2243: HTTP Header Standardization for Streamable HTTP Transport - MCP Docs](https://modelcontextprotocol.io/seps/2243-http-standardization)

## 2. SEP-2663 Tasks 拡張

Tasks 拡張の仕様が更新されました。新たにエラーコード `-32003`（Missing Required Client Capability）が追加され、必要なクライアント能力を宣言していないクライアントが `subscriptions/listen` でのタスク通知購読や `tasks/get`・`tasks/update`・`tasks/cancel` を要求した場合に、サーバーがこのエラーを返すことが規定されました。

また後方互換性の記述が表形式に整理され、`2025-11-25`（実験的 tasks）と `2026-06-30`（本拡張）の各プロトコルバージョンにおける、レガシー能力（`tasks.*`）と新能力（`io.modelcontextprotocol/tasks`）の挙動が一覧化されました。`tasks/result` の削除、`CallToolRequest` の `task` パラメータ廃止、レガシー能力宣言から `io.modelcontextprotocol/tasks` への移行義務などが、バージョン×能力の組み合わせごとに明確化されています。

- [SEP-2663: Tasks Extension - MCP Docs](https://modelcontextprotocol.io/seps/2663-tasks-extension)

## 新規追加されたページ

<!-- light:new-pages:start -->
*(リファレンスページの新規追加はありません)*
<!-- light:new-pages:end -->

## 大幅に更新されたページ

<!-- light:updated-pages:start -->
*(大幅に更新されたページはありません)*
<!-- light:updated-pages:end -->

## 軽微な更新

<!-- light:minor-updates:start -->
- [MCP Apps](https://modelcontextprotocol.io/extensions/apps/overview) / [Extension Support Matrix](https://modelcontextprotocol.io/extensions/client-matrix):  
  サポートクライアントに Archestra.AI を追加（Extension Support Matrix にも対応状況を追記）。
- [Skills Over MCP Charter](https://modelcontextprotocol.io/community/skills-over-mcp/charter) / [Tool Annotations Charter](https://modelcontextprotocol.io/community/tool-annotations/charter):  
  ワーキンググループ／インタレストグループの membership 更新（参加者の追加）。
<!-- light:minor-updates:end -->

## 関連リンク

- (初版のため、前回サマリはありません)

<!--
base_commit: 534cac6
head_commit: 5eba50e20508f9a33b6e9ca4dff9f48b8afb601b
generated_at_full: 2026-06-02T03:11:18+09:00
-->
