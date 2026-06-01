# update-official-doc-summary

Claude Code 公式ドキュメント(`llms.txt` / `llms-full.txt` / `claude_code_docs_map.md`)の更新差分を、人間向けの changelog / リリースノート風 Markdown として生成する Skill。

## 目的

公式ドキュメントは更新頻度が高く(1〜3 日に 1 回更新ペース)、毎回 Claude Code に手動でサマライズ依頼するオーバーヘッドを排除したい。本 Skill は:

- 差分を漏れなく検出して構造化
- 詳細版を blog 風の流れで生成(LLM)
- ライト版は詳細版から固定スクリプトで機械的に抽出(LLM 揺らぎなし)
- ライト版・詳細版の両方を公開・アーカイブ

## 入出力

### 入力

| パス | 用途 |
|---|---|
| `LLMs/official-llms-txts/code.claude.com/docs/llms.txt` | URL 一覧と 1 行説明 |
| `LLMs/official-llms-txts/code.claude.com/docs/llms-full.txt` | 全文展開 |
| `LLMs/official-llms-txts/code.claude.com/docs/en/claude_code_docs_map.md` | ページ見出しマップ(新ページ検出補助) |

前提: `bash LLMs/scripts/dl_llms.sh` で最新化済みであること。

### 出力

```
LLMs/official-doc-update-summary/
└── claude-code-docs/
    ├── latest.md           ライト版(機械抽出)
    ├── latest-detail.md    詳細版(LLM 生成)
    └── archives/
        └── <YYYY-MM-DD>/   前回 generated_at
            ├── latest.md
            └── latest-detail.md
```

各ファイル末尾には HTML コメント形式で運用メタ(`base_commit` / `head_commit` / `generated_at_full`)を埋め込む。これは次回実行時の差分起点として使われる。

## 起動方法

### 通常運用(差分ベース更新)

```
/update-official-doc-summary
```

前回サマリ末尾フッタから `head_commit` を取得し、現在の HEAD との差分を反映する。差分がない場合は処理を停止する。

### 初版作成

```
/update-official-doc-summary --from <commit>
```

前回サマリが存在しない場合に必要。`<commit>` は対象期間の起点として扱われる。

## 設計判断と運用ポリシー

### ライト版 vs 詳細版

- **詳細版**(`latest-detail.md`): LLM が生成する blog 風記事。冒頭の総括 → ハイライト各機能の段落展開 → 新規追加・大幅更新ページの解説 → 軽微更新の箇条書き
- **ライト版**(`latest.md`): 詳細版からマーカー領域(`<!-- light:<name>:start --> ... <!-- light:<name>:end -->`)を `scripts/derive_light.py` で機械抽出した軽量版。各ハイライトの見出し・各大幅更新ページのエントリは詳細版該当セクションへのアンカーリンクに変換される

ライト版は詳細版から派生するため、両者が齟齬を起こすことがない設計。

### URL 併記(ja / en)

`llms.txt` には英語版 URL のみ含まれるため、日本語ページ URL は en URL の `/docs/en/` を `/docs/ja/` に機械的置換して併記する。日本語ページが未公開の場合でも併記する方針(時間差で公開されることが多く、都度ドキュメントを更新する負荷を避ける)。

### 差分検出

末尾フッタの `head_commit` を起点に `git diff <BASE_COMMIT> HEAD -- LLMs/official-llms-txts/code.claude.com/docs/` で生差分を取得し、ページ単位で分類する:

- 新規追加: llms.txt に新 URL エントリ
- 大幅更新: llms-full.txt で 50 行以上の変更
- 軽微更新: 上記以外

### セルフレビュー 2 Phase

LLM 生成の確度を上げるため、英語段階(Phase 1)と日本語化後(Phase 2)でそれぞれセルフレビューを実施:

- Phase 1: リンク実在性 / 本文整合性 / 網羅性 / 構成・展開 / メタデータ整合性
- Phase 2: 自然な日本語 / 誤訳なし / 誤字脱字なし

各 Phase で新規 NG が出なくなるまで反復する。

### 「公開」の定義

本リポジトリの正式運用フェーズでは「git push 時 = 公開」となる。現在は暫定運用フェーズなので、サマリの生成・コミットまでが本 Skill の責務。push は別途実施。

出力ファイルの場所(`LLMs/official-doc-update-summary/`)は暫定的。リポジトリの公開構造が確定したら、生成先パスも合わせて調整する想定。

## 既知の制約と残タスク

- **対象スコープ**: 現状は Claude Code Docs (`code.claude.com/docs/`) のみ。MCP 等は将来別系統として追加予定
- **差分長大時の対応**: 単一 LLM セッションで生成しきれない量の差分が来た場合、複数 Agent への分担化が必要(現状は単一セッションで生成)
- **セルフレビューチェックリスト**: 初版は一般的観点で運用。運用しながら具体化・整備を継続
- **自動起動 hook**: 本 Skill の責務外。`dl_llms.sh` 実行直後の Stop hook 等での自動呼び出しは別タスクとして実装予定
- **`LLMs/CLAUDE.md` への運用ルール追記**: フッタ HTML コメントによる運用メタ埋込み方式の明文化が残タスク

## 関連ファイル

- `SKILL.md`: Claude が実行するフロー
- `templates/detail.md.tmpl`: 詳細版テンプレート(ライト版マーカー含む)
- `scripts/derive_light.py`: 詳細版 → ライト版抽出スクリプト(Python、`python` コマンドで実行)
