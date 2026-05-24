# llms.txt 生成ツール 構築計画

llms.txt が存在しないリポジトリ・ドキュメントサイトに対して、llms.txt のドラフトを半自動で生成する仕組みの構築計画。

## 前提: 既存ツールとのギャップ

`llms-txt-official-repos/` に収録されているツールの役割を整理すると:

| ツール | 役割 | 本計画での位置づけ |
|---|---|---|
| `pysymbol-llm` | Python パッケージの公開シンボル + docstring → Markdown | **入力生成**（Phase 2 で使用） |
| `codesigs` | 多言語ソースのシグネチャ抽出（12 言語以上） | **入力生成**（Phase 3 で使用） |
| `nbs2ctx` | Jupyter ノートブック → XML コンテキスト | **入力生成**（Phase 4 で使用） |
| `llm-ctx` / `llms-txt` (`llms_txt2ctx`) | llms.txt → XML コンテキスト展開 | **検証**（全フェーズで使用） |

**ギャップ**: llms.txt の「生成」（スケルトン作成・URL 収集・セクション構成）を行うツールは存在しない。ここを本計画で構築する。

## 対象リポジトリの分類

生成難易度と使用ツールが異なるため、4 タイプに分類して対応する:

| タイプ | 説明 | 使用ツール |
|---|---|---|
| **Type A** ドキュメント系 | Markdown/rst ファイル中心、コードは少 or なし | ファイル列挙スクリプト（自作） |
| **Type B** Python パッケージ | pip インストール可能な Python ライブラリ | `pysymbol-llm` |
| **Type C** 多言語ソース | Python 以外を含む一般ソースコードリポジトリ | `codesigs` |
| **Type D** nbdev/Jupyter | `.ipynb` ファイル中心（nbdev プロジェクト） | `nbs2ctx` |

## フェーズ計画

### Phase 0: 共通基盤の整備

**目的**: 全フェーズで共通して使うテンプレート・検証ツールを整備する

| 成果物 | 内容 |
|---|---|
| `scripts/gen-llms-txt/template.md` | llms.txt スケルトンテンプレート（プレースホルダ付き） |
| `scripts/gen-llms-txt/validate.sh` | `llms_txt2ctx <file>` で展開できるかを確認するヘルパー |
| `scripts/gen-llms-txt/README.md` | スクリプト群の使い方・フェーズ説明 |

**template.md の構造**:
```markdown
# {PROJECT_NAME}

> {DESCRIPTION_ONE_LINER}

{OPTIONAL_DETAILS}

## Getting Started

- [{title}]({url}): {description}

## Guide

- [{title}]({url}): {description}

## API Reference

- [{title}]({url}): {description}

## Optional

- [{title}]({url}): {description}
```

---

### Phase 1: Type A（ドキュメント系リポジトリ）

**目的**: Markdown/rst ドキュメントが中心のリポジトリから llms.txt ドラフトを生成する

**入力**: リポジトリのローカルクローンパス（+ 公開 URL のベース）

**スクリプト**: `scripts/gen-llms-txt/gen_doc_repo.py <repo_path> [--base-url <url>]`

**処理ステップ**:
1. `README.md` の H1 を取得 → llms.txt の `# Title` に使用
2. `README.md` の冒頭段落を取得 → `> blockquote` に使用
3. ドキュメントファイルを列挙（`.md` / `.rst` / `.html`）
4. ファイルパスのキーワードパターンでセクションを自動分類:
   - `guide`, `tutorial`, `getting-started` → **Getting Started**
   - `api`, `reference`, `spec` → **API Reference**
   - `changelog`, `release`, `faq`, `contributing` → **Optional**
   - その他 → **Guide**
5. 各ファイルのタイトル（H1）と URL を列挙したドラフトを出力
6. 検証: `validate.sh <出力ファイル>` で `llms_txt2ctx` 展開を確認

**出力例**:
```markdown
# MyProject

> A concise description of MyProject.

## Getting Started

- [Installation](https://github.com/org/repo/blob/main/docs/install.md): ...

## API Reference

- [API Overview](https://github.com/org/repo/blob/main/docs/api.md): ...

## Optional

- [Changelog](https://github.com/org/repo/blob/main/CHANGELOG.md)
```

---

### Phase 2: Type B（Python パッケージ）

**目的**: `pysymbol-llm` を使って Python パッケージの公開 API を llms.txt に含める

**入力**: pip インストール済みの Python パッケージ名（+ Phase 1 と同じリポジトリパス）

**スクリプト**: `gen_doc_repo.py` に `--python-package <name>` オプションを追加

**追加処理ステップ**:
1. Phase 1 の手順でドキュメント部分の骨格を作成
2. `pysym2md <package_name> --output_file /tmp/api-list.md` を実行
3. `api-list.md` の各シンボルを整形して H2 "API Reference" セクションに変換:
   ```markdown
   ## API Reference
   
   - [ClassName.method](https://...): <docstring 1行目>
   ```
4. ドラフトにマージ
5. 検証

**注意点**: `pysymbol-llm` はインストール済みパッケージが入力。リポジトリをクローンしただけでは動作しない（`pip install` が前提）。

---

### Phase 3: Type C（多言語ソースリポジトリ）

**目的**: `codesigs` を使って Python 以外の言語を含むリポジトリのシグネチャを抽出する

**入力**: リポジトリのローカルクローンパス

**スクリプト**: `gen_doc_repo.py` に `--extract-sigs` オプションを追加

**追加処理ステップ**:
1. Phase 1 の手順でドキュメント部分の骨格を作成
2. ソースファイルを拡張子別に列挙し、`codesigs` で一括処理:
   ```python
   from codesigs import file_sigs
   sigs = []
   for f in source_files:
       try:
           sigs.extend(file_sigs(str(f)))
       except Exception:
           pass  # 非対応ファイルはスキップ
   ```
3. シグネチャをセクション別に整形（`_` 始まりのプライベートシンボルは除外）
4. H2 "Functions" または "API" セクションとしてドラフトに追加
5. 検証

**注意点**: `codesigs` は `ast-grep` バイナリを内部で使用。pip install 時に同梱されるが、実行環境によっては別途確認が必要。

---

### Phase 4: Type D（nbdev/Jupyter リポジトリ）

**目的**: `nbs2ctx` を使って Jupyter ノートブック系リポジトリを処理する

**入力**: `.ipynb` ファイルを含むディレクトリパス

**スクリプト**: `scripts/gen-llms-txt/gen_nb_repo.py <nbs_dir> [--base-url <url>]`

**処理ステップ**:
1. `nbs_to_ctx <nbs_dir> /tmp/ctx.xml` で XML コンテキストを生成
2. XML を解析し、各ノートブックのタイトルと先頭 markdown セルを取得
3. ノートブックのグループ分けを推定（ファイル名の番号プレフィックス等）してセクションに対応付け
4. llms.txt ドラフトを生成
5. 検証

---

## 実装優先順位

| 優先度 | フェーズ | 理由 |
|---|---|---|
| 1 | Phase 0（共通基盤） | 全フェーズの前提。template.md と validate.sh は小さく即作れる |
| 2 | Phase 1（ドキュメント系） | 最汎用。他フェーズの骨格になる。ツール依存なし |
| 3 | Phase 2（Python パッケージ） | pysymbol-llm が成熟しており実装コスト低 |
| 4 | Phase 3（多言語ソース） | codesigs の Python API 経由で実装。Phase 1 の拡張 |
| 5 | Phase 4（nbdev/Jupyter） | 対象が限定的（nbdev プロジェクト向け） |

## 成果物配置

```
LLMs/
└── scripts/
    └── gen-llms-txt/           # llms.txt 生成ツール群
        ├── README.md             # 使い方・フェーズ説明（人間向け）
        ├── template.md           # llms.txt スケルトンテンプレート
        ├── validate.sh           # 検証ヘルパー（llms_txt2ctx 展開チェック）
        ├── gen_doc_repo.py       # Phase 1〜3 統合スクリプト
        └── gen_nb_repo.py        # Phase 4 スクリプト（nbdev/Jupyter 向け）
```

## 留意事項

- **最終品質は人間のキュレーションに依存**: スクリプトはドラフトを生成するが、セクション分類・URL の選別・説明文の精査は人間が行う
- **URL の解決**: ローカルパスを公開 URL に変換するには `--base-url` の指定が必要。GitHub リポジトリの場合は `https://github.com/{owner}/{repo}/blob/main/` を指定する
- **スクリプトの実行環境**: Python 3.10+、および各ツールの pip install が前提（`pip install codesigs pysymbol_llm nbs2ctx llm-ctx`）
- **llms.txt の仕様制約**: H1 は必須。H2 セクション内のリンクは `[title](url): description` 形式。URL は絶対 URL が望ましい
