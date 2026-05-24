# Extensions/CLAUDE.md

`Extensions/` 配下のファイルを Claude が読み書きする際に追加ロードされるガイド。フォルダの目的・現状の概略は `README.md` 参照。

## このフォルダの目標

1. **インデックス集約**: GitHub 公開の Skill・Rule・Plugin（公式・サードパーティ問わず）について、サマリと独自観点からの評価を付与してインデックス化する
2. **既存確認の仕組み**: インデックスを元に、現在利用中 / 作成を検討中の Skill・Rule・Plugin が既に存在しているかを確認できる仕組みを構築する

## 既存 Skill 作成フローとの連携（想定）

`.claude/skills/review-skill-request/SKILL.md` 手順 4「既存 Skill・Plugin を調査する」は、現状 `claude-plugins-official` パスを直接参照する形になっている。本フォルダのインデックスが整備された後は、当該 Skill の手順を更新し、**本フォルダのインデックスを必ず確認する**形に変更する想定。

## 運用方針（未整備項目）

- インデックスのフォーマット（YAML / Markdown 表 / JSON 等）は未定
- 収集対象の範囲（Anthropic 公式 / 一定 Star 数以上のサードパーティ / 主要マーケットプレイス等）は未定
- 評価軸（独自観点）の定義は未定
- 既存確認スクリプトの実装は未着手
- 仕組み構築の進捗に応じて、本ファイルに運用ルールを追記する

## 関連

- `.claude/skills/review-skill-request/` — 新規 Skill 作成時の既存調査と連動予定
- `.claude/skills/request-new-skill/` — 上記の前段（依頼書作成フロー）
- `.claude/reports/analyze-claude-code-doc-repos/` — 流用元での Claude 関連リポジトリ走査レポート（インデックス対象の参考になる可能性あり）
