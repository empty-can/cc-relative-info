# LLMs/official-llms-txts/CLAUDE.md

公式が提供する `llms.txt` / `llms-full.txt` 等のダウンロード済みファイルを格納するフォルダ。
各サイトのサブフォルダに整理されており、**Claude Code の利用や MCP の調査で参照頻度が高い**。

## フォルダ・ファイル構成

```
official-llms-txts/
├── CLAUDE.md                              # 本ファイル（ナビゲーション）
│
├── code.claude.com/
│   └── docs/
│       ├── llms.txt                       # Claude Code 公式ドキュメント 目次（軽量・全リンク一覧）
│       ├── llms-full.txt                  # Claude Code 公式ドキュメント 全文（重い・詳細検索向き）
│       └── en/
│           └── claude_code_docs_map.md    # ドキュメント探索の起点インデックス
│
└── modelcontextprotocol.io/
    ├── llms.txt                           # MCP 公式ドキュメント 目次（軽量）
    └── llms-full.txt                      # MCP 公式ドキュメント 全文（重い・詳細検索向き）
```

> ファイルの更新: `bash LLMs/scripts/dl_llms.sh`（リポジトリルートから実行）

## 何を知りたいときにどのファイルを参照するか

### Claude Code について調べたい

| 知りたいこと | 参照先 |
|---|---|
| 「〜の機能はあるか？」「〜を設定するドキュメントはどこか？」など存在確認・一覧 | `code.claude.com/docs/llms.txt` |
| 特定機能の詳細仕様・設定値・コード例 | `code.claude.com/docs/llms-full.txt` |
| ドキュメント構成を把握してから調べたい | `code.claude.com/docs/en/claude_code_docs_map.md` |

**使い分けのポイント**: `llms.txt` は全ページのリンクと 1 行要約のみ（軽量）。まず `llms.txt` でページを特定し、必要なら `llms-full.txt` で本文を当たるのが効率的。

### MCP（Model Context Protocol）について調べたい

| 知りたいこと | 参照先 |
|---|---|
| 対応クライアント/サーバーの一覧・概要確認 | `modelcontextprotocol.io/llms.txt` |
| トランスポート仕様・認証・ツール定義の詳細 | `modelcontextprotocol.io/llms-full.txt` |

## 更新頻度・鮮度について

- これらのファイルは `LLMs/scripts/dl_llms.sh` によって手動または定期実行でダウンロードされる
- 最終更新日はファイルのタイムスタンプを確認すること
- GitHub Actions による自動更新は未設定（計画中）
