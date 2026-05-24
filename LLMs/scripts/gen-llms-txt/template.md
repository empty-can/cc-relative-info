# {PROJECT_NAME}
<!-- [スクリプト] README.md の最初の H1 から自動取得 -->

> {BLOCKQUOTE}
<!--
[LLM 生成] このプロジェクトが「何を・誰のために・どうやって解決するか」を 1〜2 文で記述する。
参照元: README.md の冒頭説明文、リポジトリの About 欄、docs の introduction セクション。
例: "A Python library for building fast web applications with minimal boilerplate."
-->

{DESCRIPTION}
<!--
[LLM 生成・省略可] llms.txt を読む LLM が文脈を正しく解釈するための補足情報。
使い方のコツ・前提知識・よくある誤解・特記事項など。不要なら削除する。
参照元: README.md の Note/Warning セクション、CONTRIBUTING.md の前書き。
-->

## {SECTION_NAME}
<!-- [スクリプト] ファイルパスキーワードで自動分類: Getting Started / Guide / API Reference / Optional -->

- [{LINK_TITLE}]({URL}): {LINK_DESCRIPTION}
<!--
  LINK_TITLE    : 対象ファイルの最初の H1。なければファイル名をタイトルケースに変換
  URL           : --base-url + ファイルの相対パス（例: https://github.com/org/repo/blob/main/docs/install.md）
  LINK_DESCRIPTION: H1 直後の最初の文（1 文のみ）。取得できない場合は省略（": " ごと削除）
-->
