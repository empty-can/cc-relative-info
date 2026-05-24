# llms-txt-official-repos

llms.txt 仕様の提唱者 [AnswerDotAI](https://github.com/AnswerDotAI) が公開している、llms.txt エコシステムに関連するリポジトリを git submodule として管理するフォルダ。

## リポジトリ一覧

| サブフォルダ | リポジトリ | ⭐ | 概要 |
|---|---|---|---|
| `llms-txt/` | [AnswerDotAI/llms-txt](https://github.com/AnswerDotAI/llms-txt) | 2407 | `/llms.txt` ファイル仕様の公式定義・ツール群（`llms_txt2ctx` CLI 含む） |
| `llm-ctx/` | [AnswerDotAI/llm-ctx](https://github.com/AnswerDotAI/llm-ctx) | 23 | `llms.txt` → LLM XML コンテキストへの変換 CLI（`llms-txt` の軽量スタンドアロン版） |
| `pysymbol-llm/` | [AnswerDotAI/pysymbol-llm](https://github.com/AnswerDotAI/pysymbol-llm) | 7 | Python パッケージの公開シンボル＋docstring を Markdown で出力（llms.txt 入力生成向け） |
| `codesigs/` | [AnswerDotAI/codesigs](https://github.com/AnswerDotAI/codesigs) | 4 | Python/JS/TS/Rust/Go/Java 等 12 言語以上からコードシグネチャを抽出（llms.txt 入力生成向け） |
| `nbs2ctx/` | [AnswerDotAI/nbs2ctx](https://github.com/AnswerDotAI/nbs2ctx) | 5 | Jupyter ノートブックのディレクトリを LLM 用 XML コンテキストに変換（nbdev プロジェクト向け） |

## ツール間の関係

```
ソースコード（Python）  ──→ pysymbol-llm (pysym2md) ──┐
ソースコード（多言語）  ──→ codesigs                  ──┤
Jupyter notebooks       ──→ nbs2ctx (nbs_to_ctx)     ──┤──→ [手動編集] llms.txt ──→ llm-ctx / llms-txt
ドキュメント・その他    ──→ 手動作成                  ──┘                           (llms_txt2ctx)
                                                                                      ↓
                                                                              LLM 向け XML コンテキスト
```

- **llms.txt の生成**（入力ツール群）: ソースコードや文書の内容を抽出・整理して `llms.txt` を手動で書くときの素材を用意する
- **llms.txt の消費**（出力ツール群）: 完成した `llms.txt` を LLM が読める XML 形式に展開する

## `llms-txt` と `llm-ctx` の使い分け

両方とも CLI 名 `llms_txt2ctx` を提供するが、依存関係が異なる:

| | `llms-txt` (`llms_txt2ctx`) | `llm-ctx` (`llms_txt2ctx`) |
|---|---|---|
| 依存 | `fastcore`・`httpx`・`mistletoe` | 軽量（公式の独立リポジトリ） |
| 機能 | 仕様全体 ＋ nbdev 統合 ＋ CLI | CLI のみ |
| 向き | nbdev プロジェクトとの統合 | シンプルに CLI だけ使いたい場合 |

## submodule の更新

```bash
# 全 submodule を最新化（リポジトリルートから）
git submodule update --remote LLMs/llms-txt-official-repos/llms-txt
git submodule update --remote LLMs/llms-txt-official-repos/llm-ctx
git submodule update --remote LLMs/llms-txt-official-repos/pysymbol-llm
git submodule update --remote LLMs/llms-txt-official-repos/codesigs
git submodule update --remote LLMs/llms-txt-official-repos/nbs2ctx
```
