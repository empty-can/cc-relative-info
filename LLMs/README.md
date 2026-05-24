# LLMs

LLM 関連情報収集を行うフォルダ。主眼は `llms.txt` 標準の活用。

## 目的

1. Claude Code の利用に有用な各種公式団体の公式ドキュメントの `llms.txt` を定期的に取り込む
2. `llms.txt` の存在しないドキュメント・リポジトリの `llms.txt` を作成する仕組みを構築する

## llms.txt とは

Jeremy Howard（Answer.AI）が 2024-09-03 に提唱した、Web サイトが LLM 向けの情報を提供するための標準ファイル仕様。

### 背景

LLM はコンテキストウィンドウの制約から Web サイト全体を処理できない。HTML・広告・JS が混在するページを LLM が扱いやすいプレーンテキストに変換することは困難かつ不正確。そこで、サイトの `/llms.txt` に LLM 向け要約・リンク集を置くことで、推論時（inference time）に必要な情報への素早いアクセスを実現する。

### ファイル仕様（フォーマット）

`/llms.txt` は Markdown 形式で、以下のセクションを順番通りに記述する:

| セクション | 必須 | 内容 |
|---|---|---|
| H1 | **必須** | プロジェクト/サイト名 |
| ブロック引用 | 任意 | プロジェクトの簡潔な要約 |
| テキストセクション | 任意 | 詳細説明（見出しなし） |
| H2 区切りファイルリスト | 任意 | `[名称](URL): 説明` の箇条書き。`## Optional` セクションは短いコンテキストが必要な場合にスキップ可 |

```markdown
# Title

> Optional description goes here

Optional details go here

## Section name

- [Link title](https://link_url): Optional link details

## Optional

- [Link title](https://link_url)
```

### 既存標準との関係

- **robots.txt**: 自動ツールのサイトアクセス可否を示す（用途が異なる）
- **sitemap.xml**: 人間向け全ページ一覧（LLM コンテキスト超過・外部リンク欠如の問題あり）
- **llms.txt**: LLM 向けに厳選されたキュレーション情報、主に推論時（inference）に使用

## 公式リポジトリ（サブモジュール）

```
LLMs/
└── llms-txt-official/   ← AnswerDotAI/llms-txt の git submodule
```

- **GitHub**: https://github.com/AnswerDotAI/llms-txt
- **公式サイト**: https://llmstxt.org/
- **ライセンス**: Apache-2.0
- **Python パッケージ**: `llms-txt`（`pip install llms-txt`）

サブモジュールを最新化する場合（リポジトリルートから実行）:
```bash
git submodule update --remote LLMs/llms-txt-official
```

## 関連ツール

| ツール | 内容 |
|---|---|
| [`llms_txt2ctx`](https://llmstxt.org/intro.html#cli) | `llms.txt` をパースして LLM コンテキストファイルを生成する CLI / Python モジュール |
| [`llms_txt2html`](https://github.com/AnswerDotAI/llms-txt) | llms.txt を HTML に変換（v0.0.6 で追加） |

## llms.txt ディレクトリサービス

公開されている `llms.txt` を探す際の参考:

- [llmstxt.site](https://llmstxt.site/)
- [directory.llmstxt.cloud](https://directory.llmstxt.cloud/)

## フォルダ構成

```
LLMs/
├── CLAUDE.md
├── README.md
├── llms-txt-official/          # llms.txt 仕様公式リポジトリ（git submodule）
├── official-llms-txts/         # 各公式サイトからダウンロードした llms.txt 等
│   ├── CLAUDE.md               # フォルダ構成・参照ガイド（Claude Code 向け）
│   ├── code.claude.com/        # Claude Code 公式ドキュメント
│   └── modelcontextprotocol.io/# MCP 公式ドキュメント
└── scripts/
    ├── dl_llms.sh              # official-llms-txts へのダウンロードスクリプト
    └── download_list.csv       # ダウンロード対象一覧
```

## 現状

- `llms-txt-official` サブモジュール追加済み
- `official-llms-txts/` に Claude Code・MCP の公式 llms.txt / llms-full.txt を取得済み
- `scripts/dl_llms.sh` で手動更新可能（実行: `bash LLMs/scripts/dl_llms.sh`）
- 自動更新（GitHub Actions）・llms.txt 生成仕組みは未整備
