---
name: generate-llms-txt
description: リポジトリから llms.txt と llms-full.txt を自動生成する。ローカルパスまたは GitHub URL を対象にできる。
allowed-tools: Agent(general-purpose)
argument-hint: "[--target <local_path_or_github_url>] [--base-url <url>] [--output <dir>] [--extract-sigs]"
---

## 引数パース

引数文字列から以下の変数を決定する：

| 変数 | デフォルト | 決定方法 |
|---|---|---|
| `TARGET` | `.`（カレントディレクトリ） | `--target <value>` または位置引数1 |
| `BASE_URL` | 自動検出 | `--base-url <value>` または後述の自動検出 |
| `OUTPUT_DIR` | 自動（後述の規則） | `--output <value>` |
| `EXTRACT_SIGS` | false | `--extract-sigs` フラグの有無 |

### OUT_DIR の決定規則

`--output` が指定された場合はその値を使用する。それ以外：

**GitHub URL の場合**（`https://github.com/` で始まる）：
- URL から `OWNER` / `REPO_NAME` / `BRANCH`（任意）を抽出する
  - 例: `https://github.com/langchain-ai/mcpdoc` → owner=`langchain-ai`, repo=`mcpdoc`
  - 例: `https://github.com/org/repo/tree/develop` → branch=`develop`
- `OUT_DIR` = `LLMs/work/gen-out/<OWNER>/<REPO_NAME>/`
- ブランチが指定されかつデフォルト（`main`/`master`）でない場合: `LLMs/work/gen-out/<OWNER>/<REPO_NAME>/<BRANCH>/`
- `REPO_PATH` = `LLMs/work/tmp-clone/<OWNER>/<REPO_NAME>`
- `BASE_URL` が未指定の場合: `https://github.com/<OWNER>/<REPO_NAME>/blob/<BRANCH_OR_MAIN>/`

**ローカルパスの場合**：
- `git -C <TARGET> remote get-url origin` で GitHub リモート URL を取得して上記と同様に扱う
- リモートが取得できない / GitHub 以外の場合: `OUT_DIR` = `LLMs/work/gen-out/<TARGET のディレクトリ名>/`

## 実行手順

### 1. Agent 起動

以下のプロンプトで `general-purpose` Agent を **1つ** 起動する。
変数 `TARGET` / `REPO_PATH` / `BASE_URL` / `OUT_DIR` / `EXTRACT_SIGS` には上記で決定した実際の値を埋めて渡す。

---
**Agent へのプロンプト（変数を実値に置換して渡すこと）**:

```
リポジトリから llms.txt / llms-full.txt を生成してください。

## 変数（確定値）
- REPO_PATH   : <REPO_PATH>
- BASE_URL    : <BASE_URL>
- OUT_DIR     : <OUT_DIR>
- EXTRACT_SIGS: <true|false>
- CLONE_URL   : <GitHub URL（ローカルパスの場合は空）>
- BRANCH      : <ブランチ名（指定がある場合のみ）>

## 手順

### 1. クローンまたは最新化（CLONE_URL が空でない場合のみ）

REPO_PATH が既に存在する場合: リポジトリを最新化する。
```
git -C <REPO_PATH> pull --depth=1
```

存在しない場合: 新規クローンする。
```
git clone --depth=1 [--branch <BRANCH>] <CLONE_URL> <REPO_PATH>
```

### 2. llms-full.txt / llms.txt 生成

```
python LLMs/scripts/gen-llms-txt/gen_llms_full.py <REPO_PATH> \
  --base-url <BASE_URL> \
  --output <OUT_DIR> \
  [--extract-sigs]
```

終了コードが非0の場合: エラーメッセージを出力して中断する。

### 3. ナラティブ生成

Read ツールで <OUT_DIR>/llms-full.txt の先頭 200 行を読み込む。

読み込んだ内容から以下を生成する：

**blockquote（1〜2文、必須）**: このプロジェクトが「何を・誰のために・どうやって解決するか」を端的に記述する。
**description（省略可）**: llms.txt を読む LLM が文脈を正しく解釈するための補足情報。不要なら空にする。

### 4. プレースホルダ置換

Edit ツールで以下を実行する：

1. <OUT_DIR>/llms.txt の `> {BLOCKQUOTE}` を `> <生成した内容>` に置換する
2. <OUT_DIR>/llms.txt の `{DESCRIPTION}` を生成した内容に置換する（空の場合は該当行ごと削除）
3. <OUT_DIR>/llms-full.txt の `> {BLOCKQUOTE}` と `{DESCRIPTION}` を同様に置換する

### 5. 検証

```
bash LLMs/scripts/gen-llms-txt/validate.sh <OUT_DIR>/llms.txt
```

終了コード 0 → ステップ 6 へ。非0 → エラーを報告して中断する。

### 6. 完了報告

以下の形式で報告する：

完了: llms.txt / llms-full.txt を生成しました。
  llms.txt     : <OUT_DIR>/llms.txt
  llms-full.txt: <OUT_DIR>/llms-full.txt
  blockquote   : "<生成した内容>"
```

---

### 2. 完了報告

Agent の完了メッセージをそのまま作業指示者に伝える。
