---
name: generate-llms-txt
description: リポジトリから llms.txt と llms-full.txt を自動生成する。ローカルパスまたは GitHub URL を対象にできる。--target-list でファイルから複数ターゲットを並列処理することも可能。
allowed-tools: Agent(general-purpose), Read
argument-hint: "[--target <local_path_or_github_url>] [--target-list <file>] [--base-url <url>] [--output <dir>] [--extract-sigs] [--cc-extensions]"
---

## 引数パース

引数文字列から以下の変数を決定する：

| 変数 | デフォルト | 決定方法 |
|---|---|---|
| `TARGET` | — | `--target <value>` または位置引数1 |
| `TARGET_LIST` | — | `--target-list <file>` のファイルパス |
| `BASE_URL` | 自動検出 | `--base-url <value>` または後述の自動検出 |
| `OUTPUT_DIR` | 自動（後述の規則） | `--output <value>` |
| `EXTRACT_SIGS` | false | `--extract-sigs` フラグの有無 |
| `CC_EXTENSIONS` | false | `--cc-extensions` フラグの有無 |

`--target` と `--target-list` は排他。両方指定された場合は `--target-list` を優先する。
どちらも省略された場合は `TARGET` = `.`（カレントディレクトリ）とする。

### ターゲット一覧ファイルの形式

`--target-list` で指定するファイルは以下の形式（1行1ターゲット）：

```
# コメント行（# で始まる行）・空行は無視する
https://github.com/langchain-ai/mcpdoc
https://github.com/google-gemini/genai-processors --extract-sigs
https://github.com/sammchardy/python-binance --extract-sigs
LLMs/work/tmp-clone/somelocal --base-url https://example.com/docs/blob/main/
```

各行の先頭トークンが `TARGET` に対応し、残りのトークンがその行専用のオプションとなる。
行ごとのオプションは SKILL 引数のオプション（`--extract-sigs`, `--base-url`）より優先する。

### OUT_DIR の決定規則

`--output` が指定された場合はその値を使用する（単一ターゲット時のみ有効）。それ以外：

**出力先ルート（`<ROOT>`）**:
- 通常モード（`CC_EXTENSIONS` が false）: `LLMs/work/gen-out/`
- `--cc-extensions` モード（`CC_EXTENSIONS` が true）: `LLMs/work/gen-out/cc-extensions/`

**GitHub URL の場合**（`https://github.com/` で始まる）：
- URL から `OWNER` / `REPO_NAME` / `BRANCH`（任意）を抽出する
  - 例: `https://github.com/langchain-ai/mcpdoc` → owner=`langchain-ai`, repo=`mcpdoc`
  - 例: `https://github.com/org/repo/tree/develop` → branch=`develop`
- `OUT_DIR` = `<ROOT><OWNER>/<REPO_NAME>/`
- ブランチが指定されかつデフォルト（`main`/`master`）でない場合: `<ROOT><OWNER>/<REPO_NAME>/<BRANCH>/`
- `REPO_PATH` = `LLMs/work/tmp-clone/<OWNER>/<REPO_NAME>`
- `BASE_URL` が未指定の場合: `https://github.com/<OWNER>/<REPO_NAME>/blob/<BRANCH_OR_MAIN>/`

**ローカルパスの場合**：
- `git -C <TARGET> remote get-url origin` で GitHub リモート URL を取得して上記と同様に扱う
- リモートが取得できない / GitHub 以外の場合: `OUT_DIR` = `<ROOT><TARGET のディレクトリ名>/`

---

## 実行手順 — 単一ターゲット（TARGET が確定している場合）

### 1. Agent 起動

以下のプロンプトで `general-purpose` Agent を **1つ** 起動する。
変数は上記で決定した実際の値に置換して渡す。

> ※ Agent プロンプトのテンプレートは「**Agent プロンプトテンプレート**」セクションを参照。

### 2. 完了報告

Agent の完了メッセージをそのまま作業指示者に伝える。

---

## 実行手順 — 複数ターゲット（TARGET_LIST が指定された場合）

### 1. ファイル読み込みと行パース

`Read` ツールで `TARGET_LIST` ファイルを読み込む。
- `#` で始まる行・空行を除外する
- 各行の先頭トークンを `TARGET`、残りを行オプションとして解析する
- 各ターゲットについて OUT_DIR 決定規則を適用し、変数セット（REPO_PATH, BASE_URL, OUT_DIR, EXTRACT_SIGS 等）を確定する

### 2. 全 Agent を並列起動（1メッセージで同時発火）

全ターゲット分の Agent を **単一メッセージで同時に起動する**（直列ではなく並列）。
各 Agent には「Agent プロンプトテンプレート」に実値を埋めたプロンプトを渡す。

### 3. 完了サマリ報告

全 Agent の結果を受け取ったら以下の形式でサマリを報告する：

```
[完了] <N> 件を処理しました。

  ✓ <owner>/<repo>  : <OUT_DIR>/llms.txt
  ✓ <owner>/<repo>  : <OUT_DIR>/llms.txt
  ✗ <owner>/<repo>  : エラー — <理由>
  ...
```

---

## Agent プロンプトテンプレート

> 以下のテンプレートの `<変数>` に実値を埋めて Agent に渡す。

```
リポジトリから llms.txt / llms-full.txt を生成してください。

## 変数（確定値）
- REPO_PATH   : <REPO_PATH>
- BASE_URL    : <BASE_URL>
- OUT_DIR     : <OUT_DIR>
- EXTRACT_SIGS: <true|false>
- CLONE_URL   : <GitHub URL（ローカルパスの場合は空）>
- BRANCH      : <ブランチ名（指定がある場合のみ、なければ空）>

## 手順

### 1. クローンまたは最新化（CLONE_URL が空でない場合のみ）

REPO_PATH が既に存在する場合: リポジトリを最新化する。
  git -C <REPO_PATH> pull --depth=1

存在しない場合: 新規クローンする。
  git clone --depth=1 [--branch <BRANCH>] <CLONE_URL> <REPO_PATH>

### 2. llms-full.txt / llms.txt 生成

  python LLMs/scripts/gen-llms-txt/gen_llms_full.py <REPO_PATH> \
    --base-url <BASE_URL> \
    --output <OUT_DIR> \
    [--extract-sigs（EXTRACT_SIGS が true の場合）] \
    [--cc-extensions（CC_EXTENSIONS が true の場合）]

終了コードが非0の場合: エラーメッセージを出力して中断する。

### 3. ナラティブ生成

Read ツールで <OUT_DIR>/llms-full.txt の先頭 200 行を読み込む。

読み込んだ内容から以下を生成する：
**CC_EXTENSIONS が false の場合（通常モード）**:
- blockquote（1〜2文、必須）: このプロジェクトが「何を・誰のために・どうやって解決するか」を端的に記述する。
- description（省略可）: llms.txt を読む LLM が文脈を正しく解釈するための補足情報。不要なら空にする。

**CC_EXTENSIONS が true の場合（CC 拡張インデックスモード）**:
- blockquote（必須）: このリポジトリが提供する Claude Code 資産の全体像を記述する。
  例: "N 個の Skill と M 個の Rule を含む Claude Code 拡張。X・Y・Z などの用途に対応。"
  各 Skills/Rules の description はスクリプトが frontmatter から自動生成済みなので改変しない。
- description: 省略する（blockquote で十分）。

### 4. プレースホルダ置換

Edit ツールで以下を実行する：
1. <OUT_DIR>/llms.txt の `> {BLOCKQUOTE}` を `> <生成した内容>` に置換する
2. <OUT_DIR>/llms.txt の `{DESCRIPTION}` を生成した内容に置換する（空の場合は該当行ごと削除）
3. <OUT_DIR>/llms-full.txt の `> {BLOCKQUOTE}` と `{DESCRIPTION}` を同様に置換する

### 5. 検証

  bash LLMs/scripts/gen-llms-txt/validate.sh <OUT_DIR>/llms.txt

終了コード 0 → ステップ 6 へ。非0 → エラーを報告して中断する。

### 6. 完了報告

完了: llms.txt / llms-full.txt を生成しました。
  llms.txt     : <OUT_DIR>/llms.txt
  llms-full.txt: <OUT_DIR>/llms-full.txt
  blockquote   : "<生成した内容>"
```
