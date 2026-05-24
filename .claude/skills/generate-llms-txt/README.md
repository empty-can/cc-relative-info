# generate-llms-txt Skill

ローカルリポジトリまたは GitHub URL を対象に `llms.txt` と `llms-full.txt` を自動生成する。単一ターゲットも、ファイルで指定した複数ターゲットの並列処理も可能。

## 使い方

### 単一ターゲット

```
/generate-llms-txt [--target <path_or_url>] [--base-url <url>] [--output <dir>] [--extract-sigs]
```

### 複数ターゲット（並列処理）

```
/generate-llms-txt --target-list <file>
```

| オプション | 説明 | デフォルト |
|---|---|---|
| `--target` | ローカルパスまたは GitHub URL | カレントディレクトリ |
| `--target-list` | ターゲット一覧ファイルのパス | — |
| `--base-url` | リンク URL のベース | git remote から自動検出 |
| `--output` | 出力先ディレクトリ（単一ターゲット時のみ有効） | 通常: `LLMs/work/gen-out/<owner>/<repo>/`、CC モード: `LLMs/work/gen-out/cc-extensions/<owner>/<repo>/` |
| `--extract-sigs` | codesigs によるソースコードシグネチャ抽出を有効化 | なし（ドキュメントのみ） |
| `--cc-extensions` | Claude Code 拡張リポジトリ向けモード（後述）。ソースシグネチャ抽出を自動実行 | なし |

### ターゲット一覧ファイルの形式

1行1ターゲット。`#` コメント・空行は無視。各行に `--extract-sigs` / `--base-url` を付与可能。

```
# 例: targets.txt
https://github.com/langchain-ai/mcpdoc
https://github.com/google-gemini/genai-processors --extract-sigs
https://github.com/sammchardy/python-binance --extract-sigs
LLMs/work/tmp-clone/mylocal --base-url https://example.com/docs/blob/main/
```

## `--cc-extensions` モード（Claude Code 拡張インデックス）

Claude Code の Skill・Rule・Agent 等を収録したリポジトリから、**検索用途に最適化された** llms.txt を生成する。

対象ファイル:
- `skills/<name>/SKILL.md`（スタンドアローン形式: anthropics/skills 等）
- `.claude/skills/<name>/SKILL.md`（embedded 形式: プロジェクト内の .claude/）
- `rules/*.md`, `agents/*.md` 等の Claude Code 拡張ファイル
- ソースコードファイル（`.py` / `.ts` 等）のシグネチャ（常に自動抽出）

各 `SKILL.md` の frontmatter `description:` が既に検索最適化されているため、LLM はリポジトリ全体の概要（blockquote）のみを生成する。

出力先は通常モードと分離: `LLMs/work/gen-out/cc-extensions/<owner>/<repo>/`

```
# Skill・Rule・Agent リポジトリの検索インデックスを作成
/generate-llms-txt --target https://github.com/anthropics/skills --cc-extensions
/generate-llms-txt --target https://github.com/myorg/my-claude-extensions --cc-extensions
```

### メタ llms.txt の生成

複数の CC 拡張リポジトリを生成した後、`cc-extensions/` 配下の全 llms.txt を集約したメタインデックスを作成できる（URL の代わりに個別 llms.txt への相対パスを使用）:

```bash
python LLMs/scripts/gen-llms-txt/gen_cc_extensions_meta.py
# → LLMs/work/gen-out/cc-extensions/llms.txt を生成
```

## 生成ファイル

| ファイル | 内容 |
|---|---|
| `llms.txt` | URL インデックス（軽量・LLM ナビゲーション用） |
| `llms-full.txt` | 全コンテンツ展開版（LLM コンテキスト用） |

出力先は git 管理外（`.gitignore` 対象）の `LLMs/work/gen-out/` 配下。CC モードは `LLMs/work/gen-out/cc-extensions/` 配下。

## 使用例

```
# ローカルのクローン済みリポジトリから生成
/generate-llms-txt --target LLMs/work/tmp-clone/mcpdoc

# GitHub URL を指定（自動クローン）
/generate-llms-txt --target https://github.com/langchain-ai/mcpdoc

# ソースコードシグネチャも含めて生成
/generate-llms-txt --target https://github.com/google-gemini/genai-processors --extract-sigs

# base-url を手動指定（ドキュメントサイト等）
/generate-llms-txt --target LLMs/work/tmp-clone/modelcontextprotocol/docs --base-url "https://modelcontextprotocol.io/"
```

## 処理の流れ

```
TARGET（ローカルパスまたは GitHub URL）
    ↓ GitHub URL の場合: git clone → LLMs/work/tmp-clone/<repo_name>/
    ↓ ローカルパスの場合: そのまま使用
gen_llms_full.py 実行
    ↓ ドキュメントファイル列挙・セクション分類
    ↓ （--extract-sigs 時）codesigs でソースシグネチャ抽出
llms-full.txt（{BLOCKQUOTE}/{DESCRIPTION} はプレースホルダ）
    ↓ [LLM] llms-full.txt を読んでナラティブを生成
    ↓ プレースホルダを置換
llms.txt / llms-full.txt（完成版）
    ↓ llms_txt2ctx で構文検証
完了
```

## 依存ツール

スクリプトを実行する前に以下をインストールしておく：

```bash
pip install codesigs llm-ctx  # --extract-sigs 使用時は codesigs も必要
```

## 注意事項

- GitHub URL 指定時はリポジトリを `LLMs/work/tmp-clone/` 配下にシャロークローンする
- `--base-url` を省略した場合、git remote から自動検出を試みる。リモートなしのローカルリポジトリでは `--base-url` の明示指定が必要
- ブロックquote・本文説明は LLM が `llms-full.txt` を読んで自動生成する。生成後に手動で編集することも可能
