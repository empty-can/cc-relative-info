---
対象期間: 2026年06月02日 〜 2026年06月05日
作成日: 2026-06-05
---

# MCP 公式ドキュメント更新サマリ - 詳細版

<!-- light:summary:start -->
> 今回の更新は新規ページ 1 件の追加が中心で、MCP 認可 Interest Group の設立憲章ページ「Authorization Charter」が新設されました。既存ページの大幅な書き換えはなく、その他は community（コミュニティ／ガバナンス）配下の charter ページ群の再配置と SEP 索引の整列が中心です。
>
> 主要なものを以下に挙げます。
>
> 1. MCP 認可 Interest Group の設立憲章ページ「Authorization Charter」が新設
<!-- light:summary:end -->

## ハイライト

<!-- light:highlight-list:start -->
1. [**MCP 認可 Interest Group 憲章の新設**](#1-mcp-認可-interest-group-憲章の新設):  
  OAuth 2.1 ベースの認可仕様の実運用課題を収集し、検証済みの問題を Working Group へ橋渡しするための Interest Group（IG）設立憲章。スコープ・体制・配下の認可 Working Group 一覧を定義する。
<!-- light:highlight-list:end -->

## 1. MCP 認可 Interest Group 憲章の新設

新しい憲章ページ「Authorization Charter」（`community/auth/charter`）が追加されました。これは MCP の **Authorization Interest Group（認可 IG）** の設立憲章で、MCP 実装者・ID プロバイダーベンダー・セキュリティ実務者が、MCP クライアント／サーバーを実運用する際に直面する認可上の課題を持ち寄る場として位置づけられています。IG はユースケースを収集し、現行の OAuth 2.1 ベース認可仕様のギャップを文書化し、検証済みで十分にスコープが定まった問題を、標準のグループ作成プロセスを通じて専用の Working Group（WG）へと橋渡しして対応する SEP を駆動します。

憲章では、In Scope（デプロイ経験レポート、エンタープライズ ID 連携、委譲・エージェント的アクセス、スコープ粒度、非 HTTP トランスポートの資格情報、クライアント登録、脅威モデリング入力 など）と Out of Scope（エンドユーザー認証、トランスポート層セキュリティ、サーバー ID／来歴、製品個別の設定手順 など）が明確に区切られています。ファシリテーターは Okta・Amazon・Anthropic の 3 名で、参加は誰でも可能（`#auth-ig` Discord チャンネルや GitHub Discussions）です。配下には Client Registration・Mix-up Protection・Profiles・Tool Scopes・Fine-Grained Authorization・Improve DevX といった認可 WG が一覧化されています（一部は Completed、Tool Scopes と Fine-Grained Authorization は Active）。

- [Authorization Charter - MCP Docs](https://modelcontextprotocol.io/community/auth/charter)

## 新規追加されたページ

<!-- light:new-pages:start -->
- [**Authorization Charter**](#1-authorization-charter) ([modelcontextprotocol.io](https://modelcontextprotocol.io/community/auth/charter)):  
  MCP 認可 Interest Group の設立憲章。認可の実運用課題の収集と Working Group へのインキュベーションを担う。
<!-- light:new-pages:end -->

## 1. Authorization Charter

「Authorization Charter」（`community/auth/charter`）は、MCP の認可 Interest Group を定義する新規ページです。Group Type（Interest Group）・Mission Statement・Scope（In Scope / Out of Scope / Related Groups）・Leadership・Membership・Operations・Working Group Incubation・Deliverables & Success Metrics・Changelog という節で構成されます。

IG の役割は問題のインキュベーション（問題提起から WG 提案まで）に限定され、WG の承認はコミュニティモデレーターとコアメンテナーに委ねられる点、認可拡張仕様が `modelcontextprotocol/ext-auth` リポジトリに集約される点、隔週のディスカッションコールで運用される点などが明記されています。Changelog には「2026-06-02 Initial charter」が記録されています。

- [Authorization Charter - MCP Docs](https://modelcontextprotocol.io/community/auth/charter)

## 大幅に更新されたページ

<!-- light:updated-pages:start -->
*(大幅に更新されたページはありません)*
<!-- light:updated-pages:end -->

## 軽微な更新

<!-- light:minor-updates:start -->
- [Working and Interest Groups（community / ガバナンス再編）](https://modelcontextprotocol.io/community/working-interest-groups):  
  `llms-full.txt` 上では community 配下の charter ページ群（registry / sdk / server-card など）の再配置、SEP 索引（`seps/index`）のエントリ整列、各 SEP の Status バッジ表記の調整といった再生成由来の差分が大きく出ていますが、新規の Authorization Charter を除き、ページ本文の実質的な内容変更はありません。
<!-- light:minor-updates:end -->

## 関連リンク

- 前回サマリ(ライト版): [./archives/2026-06-02/latest.md](./archives/2026-06-02/latest.md)
- 前回サマリ(詳細版): [./archives/2026-06-02/latest-detail.md](./archives/2026-06-02/latest-detail.md)

<!--
base_commit: 5eba50e20508f9a33b6e9ca4dff9f48b8afb601b
head_commit: a266740e84fc0b8638ba00bdb5d77781b4ce3ef8
generated_at_full: 2026-06-05T22:44:14+09:00
-->
