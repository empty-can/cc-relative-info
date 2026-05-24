# llms.txt 自動生成 Skill 構築計画

llms.txt が存在しないリポジトリに対して `llms.txt` と `llms-full.txt` を自動生成する Skill の構築計画。

---

## 設計の前提

### なぜ完全自動化が難しいか

公式ドキュメント（`llms-txt-official-repos/llms-txt/nbs/nbdev.qmd`）が明示している通り、`llms.txt` はサイト/ライブラリオーナーが**手書きする文書**として設計されている。`pysymbol-llm` / `codesigs` は「手書きの素材」を提供するツールであり、`llms.txt` 自体の生成ツールは意図的に存在しない。

自動化の可否を部分ごとに整理すると:

| フィールド | 自動化 | 手段 |
|---|---|---|
| `# Title` | スクリプト | README.md の最初の H1 |
| `> blockquote` | **LLM** | README の内容を基にプロジェクト要約を生成 |
| 本文説明 | **LLM**（省略可） | README / docs から補足情報を生成 |
| H2 セクション分類 | スクリプト | ファイルパスのキーワードパターン |
| リンクタイトル | スクリプト | 対象ファイルの H1 |
| リンク URL | スクリプト | base-url + 相対パス |
| リンク説明文 | スクリプト | 対象ファイルの H1 直後の最初の文 |
| API シグネチャ | スクリプト | `pysymbol-llm` / `codesigs` |

### 生成フロー（アーキテクチャ B）

`llms.txt` を先に作るのではなく、リポジトリのコンテンツから `llms-full.txt` を直接生成し、そこから `llms.txt` を導出する:

```
対象リポジトリ（ローカルパスまたは GitHub URL）
    ↓ [スクリプト] コンテンツ抽出・セクション分類
llms-full.txt（全コンテンツ）
    ↓ [スクリプト] H1・最初の文・URL を抽出
    ↓ [LLM] blockquote・本文を生成
llms.txt（インデックス）
    ↓ [スクリプト] llms_txt2ctx で展開確認
検証 OK
```

---

## Skill 仕様

### 起動方法

```
/generate-llms-txt [--target <path_or_url>] [--output <dir>] [--base-url <url>]
```

| 引数 | 説明 | デフォルト |
|---|---|---|
| `--target` | ローカルパスまたは GitHub URL | カレントディレクトリ |
| `--output` | 出力先ディレクトリ | `--target` と同じディレクトリ |
| `--base-url` | リンク URL のベース | GitHub URL から自動推定 |

### 動作概要

1. `--target` がローカルパスなら直接使用。GitHub URL なら一時ディレクトリに `git clone`
2. リポジトリタイプを自動判定（Type A〜D）
3. コンテンツ抽出スクリプトを実行 → `llms-full.txt` を生成
4. LLM が `llms-full.txt` の内容を読んで blockquote と本文を生成
5. `llms-full.txt` + LLM 生成ナラティブから `llms.txt` を導出
6. `llms_txt2ctx` で検証
7. `--output` ディレクトリに `llms.txt` / `llms-full.txt` を出力

### 出力先

```
<output>/
├── llms.txt          # インデックスファイル（軽量・URL 付き）
└── llms-full.txt     # 全コンテンツ展開版（LLM コンテキスト用）
```

---

## テンプレート仕様

`scripts/gen-llms-txt/template.md` として管理。スクリプトはこのテンプレートを元に出力を生成する。

```markdown
# {PROJECT_NAME}
{{!-- [スクリプト] README.md の最初の H1 から自動取得 --}}

> {BLOCKQUOTE}
{{!--
[LLM 生成] このプロジェクトが「何を・誰のために・どうやって解決するか」を 1〜2 文で記述。
参照元: README.md の冒頭説明文、About 欄、docs の introduction セクション。
例: "A Python library for building fast web applications with minimal boilerplate."
--}}

{DESCRIPTION}
{{!--
[LLM 生成・省略可] llms.txt を読む LLM が文脈を正しく解釈するための補足情報。
使い方のコツ・前提知識・よくある誤解・特記事項など。不要なら空にする。
参照元: README.md の Note/Warning、CONTRIBUTING.md の前書き、公式ブログ記事。
--}}

## {SECTION_NAME}
{{!-- [スクリプト] ファイルパスキーワードで Getting Started / Guide / API Reference / Optional に自動分類 --}}

- [{LINK_TITLE}]({URL}): {LINK_DESCRIPTION}
{{!--
  LINK_TITLE: 対象ファイルの最初の H1。なければファイル名をタイトルケースに変換
  URL: --base-url + ファイルの相対パス
  LINK_DESCRIPTION: H1 直後の最初の文（1文）。取得できない場合は省略
--}}
```

---

## セクション自動分類ルール

ファイルパスに含まれるキーワードでセクションを機械的に決定する:

| キーワード（パス中に含む） | 分類先 |
|---|---|
| `install`, `setup`, `quickstart`, `getting-started`, `start` | Getting Started |
| `api`, `reference`, `spec` | API Reference |
| `guide`, `tutorial`, `how-to`, `howto`, `example` | Guide |
| `changelog`, `release`, `faq`, `contributing`, `license`, `security` | Optional |
| それ以外 | Guide（フォールバック） |
| `README.md` | セクションに含めない（ナラティブ生成の参照元として使用） |

---

## 対象リポジトリのタイプと処理の違い

| タイプ | 判定条件 | 追加処理 |
|---|---|---|
| **Type A** ドキュメント系 | `.md` / `.rst` が多数、ソースコード少 | なし |
| **Type B** Python パッケージ | `pyproject.toml` / `setup.py` が存在 | `pysymbol-llm` で API 抽出 → API Reference セクションに追加 |
| **Type C** 多言語ソース | Type B 以外でソースコードが多数 | `codesigs` でシグネチャ抽出 → API Reference セクションに追加 |
| **Type D** nbdev/Jupyter | `nbs/` 配下に `.ipynb` が多数 | `nbs2ctx` で XML 生成 → セクション構成に使用 |

タイプは排他ではない（Type B は Type A の処理も行う）。

---

## フェーズ計画

### Phase 0: 共通基盤の整備

**成果物**:

| ファイル | 内容 |
|---|---|
| `scripts/gen-llms-txt/template.md` | llms.txt テンプレート（上記仕様） |
| `scripts/gen-llms-txt/validate.sh` | `llms_txt2ctx <file>` で展開確認するヘルパー |
| `scripts/gen-llms-txt/README.md` | スクリプト群の使い方 |

---

### Phase 1: Type A（ドキュメント系）のスクリプト実装

**スクリプト**: `scripts/gen-llms-txt/gen_llms_full.py`

```
入力: <repo_path> --base-url <url>
出力: llms-full.txt（セクション構造 + 全ファイルのコンテンツ）
```

**処理**:
1. ドキュメントファイル（`.md` / `.rst`）を列挙
2. セクション自動分類ルールを適用
3. 各ファイルのコンテンツを構造化して `llms-full.txt` に出力
4. `llms-full.txt` から H1 + 最初の文 + URL を抽出し `llms.txt` の骨格を生成
5. blockquote / 本文は `{BLOCKQUOTE}` / `{DESCRIPTION}` プレースホルダのまま出力

（プレースホルダの充填は Skill の LLM ステップで行う）

---

### Phase 2: Type B（Python パッケージ）の対応追加

`gen_llms_full.py` に `--python-package <name>` オプションを追加:

1. `pysym2md <package> --output_file /tmp/api-list.md` を実行
2. 各シンボルのシグネチャ + docstring 1行目を抽出
3. API Reference セクションとして `llms-full.txt` に追加

---

### Phase 3: Type C（多言語ソース）の対応追加

`gen_llms_full.py` に `--extract-sigs` オプションを追加:

1. ソースファイルを列挙し `codesigs` の `file_sigs()` で一括処理
2. `_` 始まりの非公開シンボルを除外
3. シグネチャ + docstring 1行目を API Reference セクションとして追加

---

### Phase 4: Type D（nbdev/Jupyter）の対応追加

`scripts/gen-llms-txt/gen_nb_llms_full.py` として実装:

1. `nbs_to_ctx <nbs_dir> /tmp/ctx.xml` を実行
2. XML から各ノートブックのタイトルと先頭セルを抽出
3. セクション構成を生成して `llms-full.txt` に出力

---

### Phase 5: Skill 化

`.claude/skills/generate-llms-txt/SKILL.md` として実装:

**Skill の処理フロー**:

```
1. --target を解決
   - ローカルパス → そのまま使用
   - GitHub URL → git clone して一時ディレクトリに展開
2. リポジトリタイプを自動判定
3. gen_llms_full.py（または gen_nb_llms_full.py）を実行
   → llms-full.txt 生成（プレースホルダあり）
4. LLM ステップ:
   - llms-full.txt の冒頭〜数セクションを読み込む
   - blockquote（1〜2文の要約）を生成して {BLOCKQUOTE} を置換
   - 必要に応じて本文補足を生成して {DESCRIPTION} を置換
5. llms.txt を導出（H1 + ナラティブ + リンクインデックス）
6. llms_txt2ctx で検証（exit 非0 なら Skill がエラー報告）
7. --output に llms.txt / llms-full.txt を書き出し
```

**allowed-tools**（想定）:
- `Bash`: git clone、Python スクリプト実行、llms_txt2ctx 実行
- `Read`: llms-full.txt の読み込み（LLM ステップ用）
- `Write`: llms.txt / llms-full.txt の書き出し

---

## 実装優先順位

| 優先度 | フェーズ | 理由 |
|---|---|---|
| 1 | Phase 0（共通基盤） | template.md と validate.sh は小さく即作れる |
| 2 | Phase 1（ドキュメント系スクリプト） | 最汎用。Skill の骨格になる |
| 3 | Phase 5（Skill 化） | Phase 1 完了後、LLM ステップを組み込んで Skill として完結させる |
| 4 | Phase 2（Python パッケージ） | Skill の拡張オプション |
| 5 | Phase 3（多言語ソース） | 同上 |
| 6 | Phase 4（nbdev/Jupyter） | 対象が限定的 |

---

## 成果物配置

```
LLMs/
└── scripts/
    └── gen-llms-txt/               # llms.txt 自動生成スクリプト群
        ├── README.md                 # 使い方（人間向け）
        ├── template.md               # llms.txt テンプレート（プレースホルダ付き）
        ├── validate.sh               # 検証ヘルパー
        ├── gen_llms_full.py          # Type A/B/C 向け llms-full.txt 生成
        └── gen_nb_llms_full.py       # Type D 向け（nbdev/Jupyter）

.claude/
└── skills/
    └── generate-llms-txt/
        └── SKILL.md                  # Skill 定義（Phase 5 で作成）
```

---

## 留意事項

- **GitHub URL 指定時**: `git clone` を使用。認証が必要なプライベートリポジトリは PAT 設定が前提
- **base-url の自動推定**: `git remote get-url origin` から GitHub URL を検出し `blob/main/` を補完。ローカル専用リポジトリは `--base-url` の明示指定が必要
- **Python ツールの事前インストール**: `pip install codesigs pysymbol_llm nbs2ctx llm-ctx` が前提
- **llms-full.txt のフォーマット**: `llms_txt2ctx` の XML 形式ではなく、Markdown の平文結合形式で生成する（ローカルファイルを直接読むためHTTP fetch 不要）
