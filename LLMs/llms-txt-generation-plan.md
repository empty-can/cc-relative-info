# llms.txt 生成ツール 構築計画

llms.txt が存在しないリポジトリ・ドキュメントサイトに対して、llms.txt を**自動生成**する仕組みの構築計画。

## 前提: 既存ツールとのギャップ

`llms-txt-official-repos/` に収録されているツールの役割を整理すると:

| ツール | 役割 | 本計画での位置づけ |
|---|---|---|
| `pysymbol-llm` | Python パッケージの公開シンボル + docstring → Markdown | **素材抽出**（Phase 2 で使用） |
| `codesigs` | 多言語ソースのシグネチャ抽出（12 言語以上） | **素材抽出**（Phase 3 で使用） |
| `nbs2ctx` | Jupyter ノートブック → XML コンテキスト | **素材抽出**（Phase 4 で使用） |
| `llm-ctx` / `llms-txt` (`llms_txt2ctx`) | llms.txt → XML コンテキスト展開 | **検証**（全フェーズで使用） |

**ギャップ**: llms.txt の「生成」（プロジェクト情報の収集・セクション構成の決定・URL とリンク説明の自動充填）を行うツールは存在しない。ここを本計画で構築する。

## 自動生成の設計方針

各フィールドを以下の規則で自動充填し、人手介入なしで完結する llms.txt を出力する:

| llms.txt フィールド | 自動充填ルール |
|---|---|
| `# Title`（H1） | リポジトリの `README.md` 最初の H1 |
| `> description`（blockquote） | `README.md` の H1 直後の最初の段落（コードブロック・バッジを除く） |
| H2 セクション名 | ファイルパスのキーワードパターンで分類（後述） |
| リンクタイトル | 対象ファイルの最初の H1。存在しない場合はファイル名（拡張子除く）をタイトルケースに変換 |
| リンク URL | `--base-url` + リポジトリ内相対パスを結合。GitHub の場合は `blob/main/` を挟む |
| リンク説明文 | 対象ファイルの H1 直後の最初の文（1 文のみ）。取得できない場合は省略 |

**セクション自動分類ルール（ファイルパスのキーワード照合）**:

| キーワード（パス中に含む） | 分類先セクション |
|---|---|
| `install`, `setup`, `quickstart`, `getting-started`, `start` | Getting Started |
| `api`, `reference`, `spec` | API Reference |
| `guide`, `tutorial`, `how-to`, `howto`, `example` | Guide |
| `changelog`, `release`, `faq`, `contributing`, `license`, `security` | Optional |
| それ以外 | Guide（フォールバック） |
| `README.md` | セクションに含めない（blockquote に使用済み） |

## 対象リポジトリの分類

| タイプ | 説明 | 使用ツール |
|---|---|---|
| **Type A** ドキュメント系 | Markdown/rst ファイル中心、コードは少 or なし | 自作スクリプト |
| **Type B** Python パッケージ | pip インストール可能な Python ライブラリ | `pysymbol-llm` |
| **Type C** 多言語ソース | Python 以外を含む一般ソースコードリポジトリ | `codesigs` |
| **Type D** nbdev/Jupyter | `.ipynb` ファイル中心（nbdev プロジェクト） | `nbs2ctx` |

## フェーズ計画

### Phase 0: 共通基盤の整備

**目的**: 全フェーズで共通して使う検証ツールを整備する

| 成果物 | 内容 |
|---|---|
| `scripts/gen-llms-txt/validate.sh` | `llms_txt2ctx <file>` で展開できるかを確認するヘルパー |
| `scripts/gen-llms-txt/README.md` | スクリプト群の使い方・フェーズ説明 |

**validate.sh の動作**:
```bash
# 使用例: bash validate.sh llms.txt
# 成功: "OK: <ファイル名>" を出力してexit 0
# 失敗: エラー内容を出力してexit 1
llms_txt2ctx "$1" > /dev/null && echo "OK: $1" || { echo "FAIL: $1"; exit 1; }
```

---

### Phase 1: Type A（ドキュメント系リポジトリ）

**目的**: Markdown/rst ドキュメントが中心のリポジトリから llms.txt を自動生成する

**入力**:
- `<repo_path>`: リポジトリのローカルクローンパス
- `--base-url <url>`: 公開 URL のベース（例: `https://github.com/org/repo/blob/main/`）

**スクリプト**: `scripts/gen-llms-txt/gen_doc_repo.py <repo_path> --base-url <url>`

**処理ステップ**:
1. `README.md` の H1 を抽出 → `# Title`
2. `README.md` の H1 直後の最初の段落を抽出（バッジ行・空行はスキップ）→ `> blockquote`
3. ドキュメントファイルを列挙（`.md` / `.rst`）。`README.md` は除外
4. 各ファイルに対してセクション自動分類ルールを適用
5. 各ファイルから H1（リンクタイトル）と H1 直後の最初の文（リンク説明文）を抽出
6. セクション内でパスのアルファベット順にソート
7. llms.txt を出力
8. `validate.sh` で `llms_txt2ctx` 展開を確認、exit 0 でなければエラーとして終了

**出力例**:
```markdown
# MyProject

> A library for doing X and Y efficiently.

## Getting Started

- [Installation](https://github.com/org/repo/blob/main/docs/install.md): Install MyProject using pip.
- [Quickstart](https://github.com/org/repo/blob/main/docs/quickstart.md): Run your first example in 5 minutes.

## Guide

- [Configuration](https://github.com/org/repo/blob/main/docs/configuration.md): Configure MyProject for your use case.

## API Reference

- [API Overview](https://github.com/org/repo/blob/main/docs/api.md): Complete API reference for MyProject.

## Optional

- [Changelog](https://github.com/org/repo/blob/main/CHANGELOG.md): Version history and release notes.
```

---

### Phase 2: Type B（Python パッケージ）

**目的**: `pysymbol-llm` で Python パッケージの公開 API を自動抽出し、API Reference セクションに充填する

**入力**:
- Phase 1 の入力に加えて `--python-package <name>`: pip インストール済みのパッケージ名

**スクリプト**: `gen_doc_repo.py` に `--python-package <name>` オプションを追加

**追加処理ステップ**:
1. Phase 1 の処理でドキュメント部分のセクション構成を生成
2. `pysym2md <package_name> --output_file /tmp/api-list.md` を実行
3. `api-list.md` の各エントリを解析:
   - シンボル名 → リンクタイトル
   - docstring の最初の文 → リンク説明文
   - URL → `--base-url` から `api/<module>.md` 等を構築（または GitHub ソースへの直リンク）
4. Phase 1 で生成した API Reference セクションを本データで置き換え（またはマージ）
5. 検証

**注意点**: `pysymbol-llm` はインストール済みパッケージを入力とする。スクリプト実行前に `pip install <package>` が完了していることが前提。

---

### Phase 3: Type C（多言語ソースリポジトリ）

**目的**: `codesigs` で多言語のソースからシグネチャを自動抽出し、API Reference セクションに充填する

**入力**:
- Phase 1 の入力に加えて `--extract-sigs`: シグネチャ抽出モードを有効化

**スクリプト**: `gen_doc_repo.py` に `--extract-sigs` オプションを追加

**追加処理ステップ**:
1. Phase 1 の処理でドキュメント部分のセクション構成を生成
2. ソースファイルを拡張子別に列挙（`.py`, `.ts`, `.js`, `.go`, `.rs`, `.java` 等）
3. `codesigs` の `file_sigs()` で各ファイルのシグネチャを抽出:
   ```python
   from codesigs import file_sigs
   for f in source_files:
       sigs.extend(file_sigs(str(f)))
   ```
4. シグネチャをフィルタリング:
   - `_` 始まりの非公開シンボルは除外
   - シグネチャ行をリンクタイトルとして使用
   - 直後の docstring 最初の文をリンク説明文として使用
5. ファイルパス別にグルーピングし、H2 "API Reference" セクションとして追加
6. 検証

---

### Phase 4: Type D（nbdev/Jupyter リポジトリ）

**目的**: `nbs2ctx` で Jupyter ノートブック系リポジトリの構造を解析し、llms.txt を自動生成する

**入力**:
- `<nbs_dir>`: `.ipynb` ファイルを含むディレクトリパス
- `--base-url <url>`: 公開 URL のベース

**スクリプト**: `scripts/gen-llms-txt/gen_nb_repo.py <nbs_dir> --base-url <url>`

**処理ステップ**:
1. `nbs_to_ctx <nbs_dir> /tmp/ctx.xml` で XML コンテキストを生成
2. XML を解析し、各ノートブックから以下を自動取得:
   - タイトル（最初の markdown セルの H1）→ リンクタイトル
   - 先頭の非コードセルの最初の文 → リンク説明文
3. ファイル名の番号プレフィックスでセクションをグルーピング:
   - `00_*.ipynb`, `01_*.ipynb` → 番号が小さい = Getting Started
   - `*_core.ipynb`, `*_api.ipynb` → API Reference
   - その他 → Guide
4. llms.txt を出力
5. 検証

---

## 実装優先順位

| 優先度 | フェーズ | 理由 |
|---|---|---|
| 1 | Phase 0（共通基盤） | 全フェーズの前提。validate.sh は小さく即作れる |
| 2 | Phase 1（ドキュメント系） | 最汎用。他フェーズの骨格になる。ツール依存なし |
| 3 | Phase 2（Python パッケージ） | pysymbol-llm が成熟しており実装コスト低 |
| 4 | Phase 3（多言語ソース） | codesigs の Python API 経由で実装。Phase 1 の拡張 |
| 5 | Phase 4（nbdev/Jupyter） | 対象が限定的（nbdev プロジェクト向け） |

## 成果物配置

```
LLMs/
└── scripts/
    └── gen-llms-txt/           # llms.txt 自動生成ツール群
        ├── README.md             # 使い方・フェーズ説明（人間向け）
        ├── validate.sh           # 検証ヘルパー（llms_txt2ctx 展開チェック）
        ├── gen_doc_repo.py       # Phase 1〜3 統合スクリプト
        └── gen_nb_repo.py        # Phase 4 スクリプト（nbdev/Jupyter 向け）
```

## 留意事項

- **URL の解決**: `--base-url` の指定が必須。GitHub リポジトリの場合は `https://github.com/{owner}/{repo}/blob/main/` を指定する
- **スクリプトの実行環境**: Python 3.10+、および各ツールの pip install が前提（`pip install codesigs pysymbol_llm nbs2ctx llm-ctx`）
- **codesigs の依存**: 内部で `ast-grep` バイナリを使用。pip install 時に同梱されるが、実行環境によっては別途確認が必要
- **llms.txt の仕様制約**: H1 は必須。H2 セクション内のリンクは `[title](url): description` 形式。URL は絶対 URL が望ましい
- **説明文が取得できないファイル**: リンク説明文を省略（`: description` 部分なし）して出力する。llms.txt 仕様上、説明文は任意のため仕様違反にならない
