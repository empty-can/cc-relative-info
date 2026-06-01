---
name: update-official-doc-summary
description: Claude Code 公式ドキュメント (llms.txt / llms-full.txt) の更新差分を、人間向けの changelog / リリースノート風 Markdown として生成する。詳細版を LLM で生成し、ライト版は固定スクリプトで詳細版から機械的に抽出する。
allowed-tools: Read, Write, Edit, Grep, Bash(git diff:*), Bash(git log:*), Bash(git rev-parse:*), Bash(mkdir -p:*), Bash(mv:*), Bash(python:*)
argument-hint: "[--from <commit>]"
disable-model-invocation: true
---

## 引数パース

- `--from <commit>`: 初版作成時の起点コミット。省略時は前回サマリの末尾フッタから `head_commit` を取得し `BASE_COMMIT` とする。前回サマリが無く `--from` も無ければエラー終了

## 固定パス

- `SUMMARY_DIR` = `LLMs/official-doc-update-summary/claude-code-docs/`
- `LATEST_DETAIL` = `${SUMMARY_DIR}latest-detail.md`
- `LATEST_LIGHT` = `${SUMMARY_DIR}latest.md`
- `ARCHIVES_DIR` = `${SUMMARY_DIR}archives/`
- `TEMPLATE` = `.claude/skills/update-official-doc-summary/templates/detail.md.tmpl`
- `DERIVE_SCRIPT` = `.claude/skills/update-official-doc-summary/scripts/derive_light.py`
- `INPUT_LLMS_TXT` = `LLMs/official-llms-txts/code.claude.com/docs/llms.txt`
- `INPUT_LLMS_FULL` = `LLMs/official-llms-txts/code.claude.com/docs/llms-full.txt`
- `INPUT_DOCS_MAP` = `LLMs/official-llms-txts/code.claude.com/docs/en/claude_code_docs_map.md`

## 主要処理

### 1. 前回サマリ参照と BASE_COMMIT 決定

Read tool で `$LATEST_DETAIL` を読み込む。

- ファイルが存在する場合: 末尾の HTML コメント `<!-- ... head_commit: <hash> ... -->` から `BASE_COMMIT` を抽出。同時に `generated_at` も抽出して `PREV_GENERATED_AT` とする (アーカイブフォルダ名で使用)
- ファイルが存在しない場合:
  - 引数 `--from <commit>` があれば `BASE_COMMIT = <commit>`
  - なければ標準エラーに `初版作成には --from <commit> 指定が必要です` を出力して終了

### 2. HEAD_COMMIT 取得と差分検出

Bash で実行:
```
git rev-parse HEAD
```
結果を `HEAD_COMMIT` とする。

Bash で実行:
```
git diff <BASE_COMMIT> <HEAD_COMMIT> -- LLMs/official-llms-txts/code.claude.com/docs/
```
出力が空なら標準出力に `差分なし、処理停止` を出して終了 (exit 0)。
非空ならその内容を `DIFF_CONTENT` とする。

### 3. 入力ドキュメント読み込み

Read tool で以下を読む:
- `$INPUT_LLMS_TXT` (URL リスト・1 行説明)
- `$INPUT_LLMS_FULL` (全文展開) — 大ファイルなので、Grep tool で必要セクションだけ抽出する形でもよい
- `$INPUT_DOCS_MAP` (ページ見出しマップ)

### 4. ページ分類

`DIFF_CONTENT` を解析し、各変更ページを以下のいずれかに分類:

| カテゴリ | 判定条件 |
|---|---|
| 新規追加 | diff で完全に新規追加された URL エントリ (llms.txt 内で `+` のみ、`-` 対応なし) |
| 大幅更新 | 既存ページの本文 (llms-full.txt) で多数の追加・削除がある (目安: 50 行以上の変更) |
| 軽微更新 | 上記以外の小規模変更 |

### 5. 詳細版テンプレート読み込み

Read tool で `$TEMPLATE` を読み込む。

### 6. 詳細版生成 (英語)

テンプレートの各 placeholder を以下で埋める。出力先は一時的に変数として保持 (まだファイル書き出しはしない):

| Placeholder | 内容 |
|---|---|
| `{{PERIOD}}` | `BASE_COMMIT` の日付 〜 `HEAD_COMMIT` の日付 (`git log -1 --format=%cs <commit>` で取得) |
| `{{GENERATED_AT}}` | 今日の日付 (`YYYY-MM-DD`) |
| `{{OVERALL_SUMMARY}}` | 全体要約 1〜2 文 (英語) |
| `{{HIGHLIGHT_BULLETS}}` | 主要 3〜5 件の箇条書き各 1 文 (英語) |
| `{{HIGHLIGHT_DETAILS}}` | 各ハイライトに対応する `### <タイトル>` + 1〜2 段落 (blog 記事相当の展開、英語) |
| `{{NEW_PAGES_BULLETS}}` | 新規追加ページ各 1 文の箇条書き (英語、URL は ja/en 併記) |
| `{{NEW_PAGES_DETAILS}}` | 各新規ページの `### <タイトル>` + 2〜3 段落 (英語) |
| `{{UPDATED_PAGES_BULLETS}}` | 大幅更新ページ各 1 文の箇条書き (英語、URL は ja/en 併記) |
| `{{UPDATED_PAGES_DETAILS}}` | 各更新ページの `### <タイトル>` + 1〜2 段落 (英語) |
| `{{MINOR_UPDATES}}` | 軽微更新ページ各半行の箇条書き (英語、URL は ja/en 併記) |
| `{{BASE_COMMIT}}` | 手順 1 で決定した値 |
| `{{HEAD_COMMIT}}` | 手順 2 で取得した値 |
| `{{GENERATED_AT_FULL}}` | 生成時刻 (`YYYY-MM-DDTHH:MM:SS+09:00` 形式) |

URL 併記ルール: en URL の `/docs/en/` を `/docs/ja/` に機械的置換して ja URL とする。

#### 各 placeholder の bullet フォーマット(厳守)

ライト版抽出スクリプト `derive_light.py` が動作するためには、以下の bullet 形式を厳守する。`**<title>**` 部分が詳細版 `### <title>` セクションへの anchor link に機械的に置換されるため、**bold title は詳細版 `###` 見出しと完全一致** させる:

| placeholder | bullet 形式 |
|---|---|
| `{{HIGHLIGHT_BULLETS}}` | `- **<機能タイトル>**: <要約>` |
| `{{NEW_PAGES_BULLETS}}` | `- **<ページタイトル>** ([日本語](url-ja) / [English](url-en)): <要約>` |
| `{{UPDATED_PAGES_BULLETS}}` | `- **<ページタイトル>** ([日本語](url-ja) / [English](url-en)): <要約>` |
| `{{MINOR_UPDATES}}` | `- [日本語](url-ja) / [English](url-en): <要約>` (bold title 無し、軽微 = 詳細セクション無しのため anchor link 化対象外) |

### 7. Phase 1 セルフレビュー (英語段階)

以下を順次確認し、NG があれば該当箇所を Edit tool で修正する。新規 NG が出なくなるまで反復:

- [ ] リンク実在性: 全 en URL が `$INPUT_LLMS_TXT` 内に実在する
- [ ] 本文整合性: ハイライト・大幅更新の記述が `$INPUT_LLMS_FULL` の対応ページ本文と矛盾しない
- [ ] 網羅性: `DIFF_CONTENT` で検出された全ページが新規 / 大幅更新 / 軽微更新のいずれかに分類されている
- [ ] 構成・展開: 概要 → 詳細の順、1 セクションが極端に短い・長いがない、用語が一貫
- [ ] メタデータ整合性: frontmatter の `period` / `generated_at` と末尾フッタの `base_commit` / `head_commit` / `generated_at_full` が正しい値

### 8. 日本語化

英語版の本文 (frontmatter と末尾フッタ HTML コメント以外) を日本語に翻訳する。Edit tool で各セクションを翻訳。

### 9. Phase 2 セルフレビュー (日本語化後)

- [ ] 自然な日本語: 直訳的・不自然な表現がない (必要に応じて `$INPUT_LLMS_FULL` を再参照して再翻訳可)
- [ ] 誤訳: 英語サマリと日本語訳の意味が一致
- [ ] 誤字・脱字: 文字レベルの誤りなし

新規 NG が出なくなるまで反復。

### 10. 旧版アーカイブ (前回サマリが存在する場合のみ)

Bash で実行:
```
mkdir -p ${ARCHIVES_DIR}<PREV_GENERATED_AT>/
mv ${LATEST_LIGHT} ${ARCHIVES_DIR}<PREV_GENERATED_AT>/latest.md
mv ${LATEST_DETAIL} ${ARCHIVES_DIR}<PREV_GENERATED_AT>/latest-detail.md
```

(`<PREV_GENERATED_AT>` は手順 1 で抽出した値)

### 11. 詳細版書き出し

Write tool で手順 6〜9 の最終結果を `$LATEST_DETAIL` に書き出す。

### 12. ライト版生成

Bash で実行:
```
python ${DERIVE_SCRIPT} ${LATEST_DETAIL}
```

スクリプトは `$LATEST_DETAIL` を読み、`$LATEST_LIGHT` を生成する。
終了コードが非ゼロならエラー内容を標準エラーに出力して終了。

### 13. 完了報告

以下の情報を含む完了メッセージを出力:
- 生成パス: `$LATEST_LIGHT` / `$LATEST_DETAIL`
- 旧版アーカイブ先 (該当する場合): `${ARCHIVES_DIR}<PREV_GENERATED_AT>/`
- 統計: ハイライト件数 / 新規追加件数 / 大幅更新件数 / 軽微更新件数
- 期間: `<BASE_COMMIT short> .. <HEAD_COMMIT short>` (各 7 桁)
