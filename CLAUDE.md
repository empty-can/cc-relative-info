# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> `.claude/` 配下のファイルを扱う際の詳細（rule の自動ロード連鎖・Skill 一覧・permissions 運用・流用元由来の参照注意等）は `.claude/CLAUDE.md` に分離している。`.claude/` 配下のファイル読み書き時に追加ロードされる。

## このリポジトリの性質

リポジトリ名は `cc-relative-info`。リモート `https://github.com/empty-can/cc-relative-info.git`。`develop` ブランチに初回コミット済み。`main` ブランチにはまだコミットなし（`main` への git log 系の調査は空が返る）。

ソースコードを伴う通常のプロジェクトではなく、**`.claude/` 配下の運用設定資産を別リポジトリ `base-dev-kit-for-cc` から純粋に流用した状態のリポジトリ**。よってビルド・テスト・lint コマンドは存在しない。本リポジトリでは現時点で 2 つのコンテンツ整備テーマ（`LLMs/` と `Extensions/`）に着手する方針。各テーマの詳細は各フォルダの `CLAUDE.md` / `README.md` 参照。

## ブランチ運用ルール（本リポジトリ固有）

`.claude/scripts/resolve-activity-dir.sh` が現在の git ブランチから活動フォルダを決定論的に解決する。**`/read-prompt-file` をはじめ複数の Skill がこの規約に依存する**:

### マージルール

| 方向 | ルール |
|---|---|
| `feature/*` → `develop` | 唯一の merge 先。**main への直接マージ禁止** |
| `develop` → `main` | main へのマージは develop からのみ |
| `work/*` → `feature/<X>` | work ブランチの merge 先は作成元の feature ブランチ |

### ブランチ命名規則

| ブランチ種別 | 命名パターン | 用途 |
|---|---|---|
| コンテンツ整備 | `feature/<フォルダ名>` | `LLMs/` や `Extensions/` 配下の整備作業 |
| サブ活動 | `work/<フォルダ名>/<作業内容>` | feature ブランチ内のタスク単位の作業 |
| 統合 | `develop` | feature ブランチの合流先・気軽な最新断面取り込み |
| リリース | `main` | develop からのみマージ |

### 活動フォルダの解決

`.claude/scripts/resolve-activity-dir.sh` が現在の git ブランチから活動フォルダを決定論的に解決する。**`/read-prompt-file` をはじめ複数の Skill がこの規約に依存する**:

- `feature/<X>` または `work/<X>/...`（`feature/<X>` を先祖に持つ）→ 活動フォルダは `<X>/`
  - `<X>` は `feature/` 直下の先頭セグメントのみ採用。深い階層は無視
  - 例: `feature/LLMs` → `LLMs/` / `work/LLMs/some-task` → `LLMs/`
- `main` / `develop`、または `feature/*` を先祖に持たないブランチ → 活動フォルダは `./`

> 流用元リポジトリは `feature/<X>` → `research-for-<X>/` という規約で運用されていた。本リポジトリでは活動フォルダ名から `research-for-` プレフィックスを外し、テーマ名そのものを使う。

## トップレベル構造

```
.claude/        # 運用設定資産（流用元から流用）。内部構造・詳細は .claude/CLAUDE.md
Extensions/    # Claude Code 拡張（Skill/Rule/Plugin）のインデックス集約と既存確認の仕組み。詳細は Extensions/CLAUDE.md
LLMs/          # LLM 関連情報収集（llms.txt 定期取り込み・llms.txt 生成）。詳細は LLMs/CLAUDE.md
```

## このリポジトリで作業する際の注意

- `main` ブランチにはまだコミットなし。`main` に対する git log 系の調査は空が返る
- 新規 feature ブランチ命名時は `<X>` をフォルダ名そのものとする（`feature/LLMs` → `LLMs/` が活動フォルダ）
- `work/*` ブランチは必ず対応する `feature/<X>` から分岐させ、マージ先も同じ `feature/<X>` にする
- `.claude/workspace/` 配下を新規作成・編集する作業は `.claude/settings.local.json` で個別に allow されている。共有 `settings.json` には含めない
