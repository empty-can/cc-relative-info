---
name: generate-llms-txt
description: リポジトリから llms.txt と llms-full.txt を自動生成する。ローカルパスまたは GitHub URL を対象にできる。
allowed-tools: Bash(git clone:*), Bash(git -C:*), Bash(python:*), Bash(bash LLMs/scripts/gen-llms-txt/validate.sh:*), Read, Edit
argument-hint: "[--target <local_path_or_github_url>] [--base-url <url>] [--output <dir>] [--extract-sigs]"
---

## 引数パース

引数文字列から以下の変数を決定する：

| 変数 | デフォルト | 決定方法 |
|---|---|---|
| `TARGET` | `.`（カレントディレクトリ） | `--target <value>` または位置引数1 |
| `BASE_URL` | 自動検出 | `--base-url <value>` または後述の自動検出 |
| `OUTPUT_DIR` | 自動（スクリプトのデフォルト） | `--output <value>` |
| `EXTRACT_SIGS` | false | `--extract-sigs` フラグの有無 |

## 実行手順

### 1. ターゲット解決

**`TARGET` が GitHub URL（`https://github.com/` で始まる）の場合：**
1. `REPO_NAME` = URL の最後のパスセグメント（`.git` 除去）
2. `REPO_PATH` = `LLMs/work/tmp-clone/<REPO_NAME>`
3. `git clone --depth=1 <TARGET> <REPO_PATH>` を実行する
4. `BASE_URL` が未指定の場合: `<TARGET>/blob/main/` を `BASE_URL` とする

**`TARGET` がローカルパスの場合：**
1. `REPO_PATH` = `TARGET`
2. `REPO_NAME` = `REPO_PATH` の最後のディレクトリ名
3. `BASE_URL` が未指定の場合:
   - `git -C <REPO_PATH> remote get-url origin` を実行する
   - 成功した場合: 取得 URL を `https://github.com/{owner}/{repo}/blob/main/` 形式に変換して `BASE_URL` とする
   - 失敗した場合: 作業指示者に `--base-url` の指定を求めて中断する

`OUT_DIR` = `OUTPUT_DIR` が指定された場合はその値、それ以外は `LLMs/work/gen-out/<REPO_NAME>`

### 2. llms-full.txt / llms.txt 生成

以下を実行する：

```
python LLMs/scripts/gen-llms-txt/gen_llms_full.py <REPO_PATH> \
  --base-url <BASE_URL> \
  [--extract-sigs（EXTRACT_SIGS が true の場合）] \
  [--output <OUTPUT_DIR>（指定された場合）]
```

終了コードが非0: エラーメッセージを出力して中断する。

### 3. LLM ステップ：ナラティブ生成

`Read` ツールで `<OUT_DIR>/llms-full.txt` を読み込む（大きい場合は先頭 200 行程度で十分）。

読み込んだ内容を元に以下を生成する：

**`{BLOCKQUOTE}`**（1〜2文、必須）:
- このプロジェクトが「何を・誰のために・どうやって解決するか」を端的に記述する
- プロジェクト名・ドキュメント構成・Source Modules の内容を参照する

**`{DESCRIPTION}`**（省略可）:
- `llms.txt` を読む LLM が文脈を正しく解釈するための補足情報
- 不要と判断した場合は空文字列とする

### 4. プレースホルダ置換

`Edit` ツールで以下を実行する：

1. `<OUT_DIR>/llms.txt` の `> {BLOCKQUOTE}` を `> <生成した内容>` に置換する
2. `<OUT_DIR>/llms.txt` の `{DESCRIPTION}` を生成した内容に置換する（空の場合は該当行ごと削除）
3. `<OUT_DIR>/llms-full.txt` の `> {BLOCKQUOTE}` と `{DESCRIPTION}` を同様に置換する

### 5. 検証

```
bash LLMs/scripts/gen-llms-txt/validate.sh <OUT_DIR>/llms.txt
```

終了コード 0: ステップ 6 へ進む。
終了コード 非0: エラー内容を出力し、`llms.txt` の構文問題を作業指示者に報告して中断する。

### 6. 完了報告

以下の形式で報告する：

```
llms.txt / llms-full.txt を生成しました。

  llms.txt     : <OUT_DIR>/llms.txt
  llms-full.txt: <OUT_DIR>/llms-full.txt

blockquote: "<生成した {BLOCKQUOTE} 内容>"
```
