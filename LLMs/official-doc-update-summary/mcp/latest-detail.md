---
対象期間: 2026年06月05日 〜 2026年06月06日
作成日: 2026-06-06
---

# MCP 公式ドキュメント更新サマリ - 詳細版

<!-- light:summary:start -->
> 今回の対象期間は、ドキュメント本文の実質的な追加・改訂はなく、仕様（specification）への参照リンクのパス正規化が中心の軽微な更新のみです。新規ページの追加や既存ページの大幅な書き換えはありません。
>
> 主要なものを以下に挙げます。
>
> 1. 仕様参照リンクのパス正規化（`/specification/latest` への統一とサンプリング節の細分化）
<!-- light:summary:end -->

## ハイライト

<!-- light:highlight-list:start -->
1. [**仕様参照リンクのパス正規化**](#1-仕様参照リンクのパス正規化):  
  MCP Apps・MCP Tasks の本文から仕様を参照するリンクが `/specification` から `/specification/latest` に更新され、Architecture ページの Sampling 参照が `/specification/2025-11-25/client` から同 `client/sampling` サブページへ細分化された。リンク切れ防止と参照先の明確化を目的とした保守的な変更。
<!-- light:highlight-list:end -->

## 1. 仕様参照リンクのパス正規化

今回の対象期間における唯一の本文変更は、複数ページに含まれる MCP 仕様（specification）への参照リンクのパス調整です。

具体的には、**MCP Apps**（`extensions/apps/overview`）と **MCP Tasks**（`extensions/tasks/overview`）の「Client support」節にある「core MCP specification」へのリンクが、これまでの `/specification` から `/specification/latest` に更新されました。これは最新版仕様を指す正規パスへの統一であり、バージョン無指定リンクの曖昧さを解消します。

また、**Architecture**（`specification/2025-11-25/architecture/index`）の capability negotiation（能力ネゴシエーション）の説明にある Sampling への参照が、`/specification/2025-11-25/client` から同セクションの `client/sampling` サブページへと、より具体的なリンク先に修正されました。いずれも記述内容そのものの変更を伴わない、リンク保守を目的とした軽微な更新です。

- [MCP Apps - MCP Docs](https://modelcontextprotocol.io/extensions/apps/overview)
- [Architecture - MCP Docs](https://modelcontextprotocol.io/specification/2025-11-25/architecture/index)

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
- [MCP Apps](https://modelcontextprotocol.io/extensions/apps/overview):  
  「Client support」節の仕様参照リンクを `/specification` → `/specification/latest` に更新（本文の記述変更なし）。
- [MCP Tasks](https://modelcontextprotocol.io/extensions/tasks/overview):  
  「Client support」節の仕様参照リンクを `/specification` → `/specification/latest` に更新（本文の記述変更なし）。
- [Architecture](https://modelcontextprotocol.io/specification/2025-11-25/architecture/index):  
  能力ネゴシエーションの Sampling 参照を `/specification/2025-11-25/client` → `client/sampling` サブページへ修正（本文の記述変更なし）。
- community 配下の charter ページ群（File Uploads Charter / Inspector V2 Working Group Charter / Interceptors Charter / SDK Tiering System）:  
  `llms-full.txt` 上でこれらのページの収録順が入れ替わっていますが、各ページの本文内容に実質的な変更はありません（再生成由来の並び替え）。
<!-- light:minor-updates:end -->

## 関連リンク

- 前回サマリ(ライト版): [./archives/2026-06-05/latest.md](./archives/2026-06-05/latest.md)
- 前回サマリ(詳細版): [./archives/2026-06-05/latest-detail.md](./archives/2026-06-05/latest-detail.md)

<!--
base_commit: a266740e84fc0b8638ba00bdb5d77781b4ce3ef8
head_commit: e5de99c411b81e86652a5d7f00210938b6465bf3
generated_at_full: 2026-06-06T13:38:18+09:00
-->
