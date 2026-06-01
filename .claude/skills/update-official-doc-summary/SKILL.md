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
| 新規追加 | リファレンス系で完全に新規追加されたページ (URL パスに `whats-new/` を含まない、`+` のみ) |
| 大幅更新 | リファレンス系で既存ページ本文に 50 行以上の変更 |
| 軽微更新 | リファレンス系で上記以外の小規模変更 |
| 新着情報 | URL パスに `/whats-new/` を含むページ (新規追加・更新を問わずすべてこのカテゴリ) |

> 新着情報 (`whats-new/...`) はリリースノート的性質を持ち、リファレンス・ガイドの新規ページとはインパクトが異なるため、別カテゴリとして扱う。

### 5. 詳細版テンプレート読み込み

Read tool で `$TEMPLATE` を読み込む。

### 6. 詳細版生成 (英語)

テンプレートの各 placeholder を以下で埋める。出力先は一時的に変数として保持 (まだファイル書き出しはしない):

| Placeholder | 内容 |
|---|---|
| `{{PERIOD}}` | `BASE_COMMIT` の日付 〜 `HEAD_COMMIT` の日付 (`git log -1 --format=%cs <commit>` で取得) |
| `{{GENERATED_AT}}` | 今日の日付 (`YYYY-MM-DD`) |
| `{{OVERALL_SUMMARY_INTRO}}` | 全体要約の冒頭 1〜2 文(英語、項目数の言及程度) |
| `{{OVERALL_SUMMARY_BULLETS}}` | 主要項目の番号付き箇条書き(後述の選定ルール参照) |
| `{{HIGHLIGHT_BULLETS}}` | 主要 3〜5 件のハイライト bullet(英語、内部リンク付き、後述フォーマット厳守) |
| `{{HIGHLIGHT_DETAILS}}` | 各ハイライトに対応する `## <タイトル>` 見出し + 1〜2 段落 + 末尾の ja/en ページリンク(後述フォーマット厳守) |
| `{{NEW_PAGES_BULLETS}}` | 新規追加ページ bullet(英語、URL は ja/en 併記、内部リンク付き) |
| `{{NEW_PAGES_DETAILS}}` | 各新規ページの `## <タイトル>` 見出し + 2〜3 段落 + 末尾の ja/en ページリンク |
| `{{UPDATED_PAGES_BULLETS}}` | 大幅更新ページ bullet(英語、URL は ja/en 併記、内部リンク付き) |
| `{{UPDATED_PAGES_DETAILS}}` | 各更新ページの `## <タイトル>` 見出し + 1〜2 段落 + 末尾の ja/en ページリンク |
| `{{MINOR_UPDATES}}` | 軽微更新ページ bullet(英語、URL は ja/en 併記、bold title 無し) |
| `{{WHATS_NEW_BULLETS}}` | 新着情報ページ bullet(英語、URL は ja/en 併記、内部リンク付き)。**日付は日本語表記** |
| `{{WHATS_NEW_DETAILS}}` | 各新着情報ページの `## <タイトル>` 見出し + 1〜2 段落 + 末尾の ja/en ページリンク |
| `{{BASE_COMMIT}}` | 手順 1 で決定した値 |
| `{{HEAD_COMMIT}}` | 手順 2 で取得した値 |
| `{{GENERATED_AT_FULL}}` | 生成時刻 (`YYYY-MM-DDTHH:MM:SS+09:00` 形式) |
| `{{PREV_GENERATED_AT}}` | 前回サマリの `作成日` (初版時は `(none)` 等の placeholder、関連リンクは手動編集で削除) |

URL 併記ルール: en URL の `/docs/en/` を `/docs/ja/` に機械的置換して ja URL とする。

#### `{{OVERALL_SUMMARY_BULLETS}}` の選定ルール

- **インプット元**: `DIFF_CONTENT` で検出された全カテゴリ(新規追加 / 大幅更新 / 軽微更新 / 新着情報)
- **必須包含**: ハイライトで取り上げた全項目は必ず含める
- **追加候補**: ハイライト未採用だが言及価値のある項目(`{{NEW_PAGES_BULLETS}}` / `{{UPDATED_PAGES_BULLETS}}` / `{{MINOR_UPDATES}}` / `{{WHATS_NEW_BULLETS}}` から選定可)
- **件数目安**: 4〜8 件(ハイライト + 追加候補の合計)
- **新着情報のみの差分の場合**: 新着情報ページ本文の "主要機能" と "Other wins" の重要項目から構成
- **形式**: 各行を `> 1. <項目>` 〜 `> N. <項目>` の番号付き箇条書きで blockquote 内に記述。番号はハイライト h2 番号とは独立して 1 から採番

#### bullet フォーマット(厳守)

ライト版抽出スクリプト `derive_light.py` が、`(#anchor)` 形式の内部リンクを `(./latest-detail.md#anchor)` の外部リンクに自動変換する。詳細版時点では **bullet 内見出しを内部リンクで書く**。

**ハイライトのみ番号付き箇条書き**(`1.` 始まり、対応する h2 番号と一致させる)。他カテゴリは `-` の通常箇条書き。

| placeholder | bullet 形式(改行は半角スペース 2 個 + 改行を意味する) |
|---|---|
| `{{HIGHLIGHT_BULLETS}}` | `N. [**<機能タイトル>**](#<anchor>):  ⏎`<br>`  <要約>` |
| `{{NEW_PAGES_BULLETS}}` | `- [**<ページタイトル>**](#<anchor>) ([日本語](url-ja) / [English](url-en)):  ⏎`<br>`  <要約>` |
| `{{UPDATED_PAGES_BULLETS}}` | `- [**<ページタイトル>**](#<anchor>) ([日本語](url-ja) / [English](url-en)):  ⏎`<br>`  <要約>` |
| `{{WHATS_NEW_BULLETS}}` | `- [**2026年MM月DD日～EE日(Week N)**](#<anchor>) ([日本語](url-ja) / [English](url-en)):  ⏎`<br>`  <要約>` |
| `{{MINOR_UPDATES}}` | `- [日本語](url-ja) / [English](url-en):  ⏎`<br>`  <要約>` (bold 無し、詳細セクション無しのため anchor 化なし) |

`<anchor>` は対応する `## <番号と本体>` 見出しから GFM 規則(小文字化・スペース→ハイフン・非英数字非ハイフン除去、Unicode 保持)で生成。**h2 が番号付き(`## 1. <title>`)の場合、anchor も番号を含む**(例: `#1-claude-opus-48-リリース`)。

#### h2 見出しの番号付け規約

固定 category 見出し(以下)は**番号なし**:

- `## ハイライト`
- `## 新規追加されたページ`
- `## 大幅に更新されたページ`
- `## 軽微な更新`
- `## 新着情報`
- `## 関連リンク`

それ以外の個別テーマ h2 は **`## N. <タイトル>`** 形式で番号付け:

| カテゴリ | 番号付け対象 h2 | 番号採番 |
|---|---|---|
| ハイライト配下 | 各機能 h2 | 1, 2, 3...(カテゴリ内で 1 から) |
| 新規追加されたページ配下 | 各ページ h2 | 1, 2, 3...(カテゴリ内で 1 から) |
| 大幅に更新されたページ配下 | 各ページ h2 | 1, 2, 3...(カテゴリ内で 1 から) |
| 新着情報配下 | 各週間ダイジェスト h2 | **番号なし**(日付表記で識別可能なため) |

#### 日付表記の規約

- 共通: ファイル内に登場する全ての年月日表現は **日本語表記**(例: `2026年05月18日`)
- 週間ダイジェスト(`whats-new/2026-wXX`): `2026年MM月DD日～EE日(Week N)`(`Week N` は英語のまま、対応する日本語表現がないため例外)

#### 各テーマセクションの末尾フォーマット(`{{HIGHLIGHT_DETAILS}}` / `{{NEW_PAGES_DETAILS}}` / `{{UPDATED_PAGES_DETAILS}}` / `{{WHATS_NEW_DETAILS}}`)

各 `## N. <タイトル>` セクションの本文の最後に、以下の形式でページリンクを記載(**「参考リンク:」の見出しは付けない**、リンク行を直接置く):

```
- [<日本語タイトル> - Claude Code Docs (日本語)](https://code.claude.com/docs/ja/<path>)
- [<English title> - Claude Code Docs (English)](https://code.claude.com/docs/en/<path>)
```

- リンク先タイトルは `$INPUT_LLMS_TXT` の各エントリ `[<Title>](<URL>): <Description>` から取得した `<Title>` を使う。日本語タイトルは LLM が `<Title>` を翻訳する
- **両 URL とも `.md` 拡張子を付けない**(`.md` 付き URL は raw ファイルが表示されるため、人間向けには拡張子なし URL が正しい)。`$INPUT_LLMS_TXT` の URL は `.md` 付きなので、`.md` を除去した上で記載する
- ja URL は en URL の `/docs/en/` を `/docs/ja/` に機械的置換し、かつ `.md` 拡張子を除去したもの

ハイライトテーマ(機能単位)では、その機能を主に解説しているページの URL を 1〜2 ページ分記載。

#### 新着情報ページ独自情報の検出(セルフレビュー観点)

`/whats-new/<page>.md` の本文と、`$INPUT_LLMS_FULL` 内の対応ページ展開を比較し、**新着情報ページにしか記載されていない内容があれば** `{{WHATS_NEW_DETAILS}}` の該当セクションに反映する。両者に差がなければ通常通り要約する。

### 7. Phase 1 セルフレビュー (英語段階)

以下を順次確認し、NG があれば該当箇所を Edit tool で修正する。新規 NG が出なくなるまで反復:

- [ ] リンク実在性: 末尾参考リンクの全 URL の `.md` 除去前形(en パスに対応する `.md` 付き URL)が `$INPUT_LLMS_TXT` 内に実在する
- [ ] URL 拡張子: 末尾参考リンクの ja URL / en URL いずれにも `.md` が付いていない
- [ ] 本文整合性: ハイライト・大幅更新の記述が `$INPUT_LLMS_FULL` の対応ページ本文と矛盾しない
- [ ] 網羅性: `DIFF_CONTENT` で検出された全ページが新規 / 大幅更新 / 軽微更新 / 新着情報のいずれかに分類されている
- [ ] カテゴリ整合性: `whats-new/` ページは全て新着情報カテゴリに分類されている
- [ ] 構成・展開: 概要 → 詳細の順、1 セクションが極端に短い・長いがない、用語が一貫
- [ ] h2 番号整合性: ハイライト / 新規追加 / 大幅更新 配下の個別テーマ h2 に `## N. <title>` 形式で番号が付与されている。新着情報配下と固定 category 見出しには番号がない
- [ ] ハイライト bullet 番号整合性: `{{HIGHLIGHT_BULLETS}}` が `N.` 始まりの番号付き箇条書きになっていて、対応する `## N.` 見出しと番号が一致
- [ ] 内部リンク整合性: bullet 内の `(#anchor)` が対応する `## N. <タイトル>` の GFM アンカー(番号含む)と一致する
- [ ] 末尾参考リンクのテキスト: `[<タイトル> - Claude Code Docs (日本語 or English)]` 形式で空タイトルなし
- [ ] 新着情報ページ独自情報: `whats-new/` ページに `$INPUT_LLMS_FULL` の同セクションには無い内容がある場合、それも反映済み
- [ ] メタデータ整合性: frontmatter の `対象期間` / `作成日` と末尾フッタの `base_commit` / `head_commit` / `generated_at_full` が正しい値
- [ ] 日付表記: 全ての年月日が日本語表記(`YYYY年MM月DD日`、ただし `Week N` は例外で英語のまま)

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
- 統計: ハイライト件数 / 新規追加件数 / 大幅更新件数 / 軽微更新件数 / 新着情報件数
- 期間: `<BASE_COMMIT short> .. <HEAD_COMMIT short>` (各 7 桁)
