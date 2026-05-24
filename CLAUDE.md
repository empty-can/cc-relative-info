# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> `.claude/` 配下のファイルを扱う際の詳細（rule の自動ロード連鎖・Skill 一覧・permissions 運用・流用元由来の参照注意等）は `.claude/CLAUDE.md` に分離している。`.claude/` 配下のファイル読み書き時に追加ロードされる。

## このリポジトリの性質

リポジトリ名は `cc-relative-info`。リモート `https://github.com/empty-can/cc-relative-info.git`、初期コミットはまだ存在しない（`git log` は `fatal: ... no commits yet` を返す）。

ソースコードを伴う通常のプロジェクトではなく、**`.claude/` 配下の運用設定資産を別リポジトリ `base-dev-kit-for-cc` から純粋に流用した状態のリポジトリ**。よってビルド・テスト・lint コマンドは存在しない。本リポジトリでは現時点で 2 つのコンテンツ整備テーマ（`LLMs/` と `Extensions/`）に着手する方針。各テーマの詳細は各フォルダの `CLAUDE.md` / `README.md` 参照。

## ブランチ運用ルール（本リポジトリ固有）

`.claude/scripts/resolve-activity-dir.sh` が現在の git ブランチから活動フォルダを決定論的に解決する。**`/read-prompt-file` をはじめ複数の Skill がこの規約に依存する**:

- 現ブランチが `feature/<X>` または `feature/<X>/<sub-branch>...` → 活動フォルダは `<X>/`
  - `<X>` は **`feature/` 直下の先頭セグメントのみ** を採用する。深い階層（`/bar/baz` 等）は無視
  - 例: `feature/foo` → `foo/` / `feature/foo/bar` → `foo/` / `feature/foo/bar/baz` → `foo/`
- 現ブランチが `main`、または `feature/*` を先祖に持たないブランチ → 活動フォルダは `./`（リポジトリルート）
- 派生サブブランチ上にいる場合（先祖に `feature/<X>` が存在）も同様に `<X>/`

> 流用元リポジトリは `feature/<X>` → `research-for-<X>/` という規約で運用されていた。本リポジトリでは活動フォルダ名から `research-for-` プレフィックスを外し、テーマ名そのものを使う。

## トップレベル構造

```
.claude/        # 運用設定資産（流用元から流用）。内部構造・詳細は .claude/CLAUDE.md
Extensions/    # Claude Code 拡張（Skill/Rule/Plugin）のインデックス集約と既存確認の仕組み。詳細は Extensions/CLAUDE.md
LLMs/          # LLM 関連情報収集（llms.txt 定期取り込み・llms.txt 生成）。詳細は LLMs/CLAUDE.md
```

## このリポジトリで作業する際の注意

- `main` ブランチに **コミットは 1 件も無い**。git log 系の調査は空が返る前提で進める
- 新規ブランチ命名で活動フォルダを使い分けたい場合は `feature/<X>` の `<X>` を活動フォルダ名そのものとする（先頭セグメントのみが採用される）
- `.claude/workspace/` 配下を新規作成・編集する作業は `.claude/settings.local.json` で個別に allow されている。共有 `settings.json` には含めない
