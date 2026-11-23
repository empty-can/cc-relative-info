# cross-review（クロスレビュー）

文書のクロスレビューを、構成の確認から 1.0 版（作業指示者の判断）まで、メインのセッションが進めるための skill。Claude は自分から起動しない（`disable-model-invocation: true`）。担当（6 体のサブエージェント）の決まりとテンプレートも、この skill の補助ファイルとして持つ。担当は定義の指示で、最初に自分の分のファイルを Read で読む。

## 使い方

```
/cross-review <対象の文書のパス>        # 段階 0 から始める
/cross-review <台帳のパス>              # 台帳の「今の段階」から再開する（圧縮・再起動の後）
```

## 構成

| ファイル | 読む人 | 中身 |
|---|---|---|
| `SKILL.md` | 主担当 | 主担当の決まり、段階の表、判断の割り込み、サブエージェントの起動 |
| `references/段階ごとの手順.md` | 主担当 | 段階 0〜6 の詳しい手順。段階に入る時に該当の節だけを読む |
| `references/rules.md` | 全部の担当・主担当 | クロスレビューに固有の決まり。役割と版の進み方、ラベルと重要度の基準、用語、hook が通す形と止めるもの、足場、報告の決まり（最初に読んだファイルの報告を含む）。コマンドの繋ぎ方・背景での実行などの共通の部分は、起動時に足される「サブエージェントの共通の決まり」にあり、ここには重ねない |
| `references/reviewing.md` | レビューア 3 体 | Round 1、確認の回、構成の確認、指摘の書き方、セルフレビュー、確認の欄、判断依頼サマリー、件数表 |
| `references/revising.md` | 反映の担当 | 回答、同件調査（件数まで）、反映（範囲の上限）、反復セルフチェック、点検の結果の直し、仕上げ、1.0 の反映 |
| `references/diff-check.md` | 差分の点検の担当 | 見る 6 点、重要度、出力の形。反映の手順（revising.md）は読まない（直した側の前提に引きずられないため） |
| `templates/レビューア/論理整合性.md`・`実用性.md`・`作業指示者+人間読み手.md` | 各観点のレビューア（自分の 1 本だけ） | 報告書の雛型。ID は `C1`／`C-1`／`U-C1`。3 本は同じ骨組みで、観点・ID・該当箇所の欄だけが違う。骨組みを変えるときは 3 本を揃える |
| `templates/レビューア/構成の確認.md` | 作業指示者+人間読み手のレビューア（執筆の前） | 構成の確認の雛型（`K-I`・`K-S`） |
| `templates/点検/差分の点検.md` | 差分の点検の担当 | 点検の報告の雛型（`D-I`・`D-S`・`D-U`） |
| `templates/進行/依頼文_*.md` | 主担当 | 担当への依頼文の雛型（`依頼文_共通の欄.md` を先頭に写す） |
| `templates/進行/台帳.md` | 主担当 | 進行の台帳（段階・版・担当の ID・決定・持ち越し） |
| `templates/進行/状態の範囲.md` | 主担当 | 手順を含む文書で、書く前に合意する状態の範囲 |
| `templates/進行/作業指示者判断待ち事項.md` | 主担当 | 段階 6 で作る、作業指示者が決める事項の一覧 |
| `templates/進行/作業指示者レビュー.md` | 作業指示者 | 作業指示者（人間）が自分の指摘を書く雛型（`H-` 接頭辞） |
| `scripts/check_lf.py` | 全部の担当 | Write・Edit の後に CR が入っていないかを数える。`python -I -X utf8 .claude/skills/cross-review/scripts/check_lf.py <ファイル>...`。終了コード 0 = CR なし、1 = CR あり、2 = 引数なし・読めない |
| `scripts/hook_pre_bash.py` | 6 体の定義の hook（PreToolUse・Bash と PowerShell） | 通す形（`rules.md` §4.1）に無いコマンドと、中身の走査（§4.2）で当たるスクリプトを止める（終了コード 2 と、直し方を書いた stderr） |
| `scripts/hook_pre_write.py` | 同（PreToolUse・Write と Edit） | 一時の場所への書き込み、担当の種類ごとに許された場所の外への書き込み、hook の設定・ログへの書き込みを止める |
| `scripts/hook_post_write.py` | 同（PostToolUse・Write と Edit） | 書いたファイルに CR があれば Claude に知らせる（直さない） |
| `scripts/hook_common.py` | hook の 3 本 | 入力の読み込み、設定、ログ、拒否。`agent_type` が `cross-review-` で始まらない入力は何もせず通す |
| `scripts/guard_tmp.sh`・`guard_tmp.py` | 足場を使うスクリプト | 冒頭で読み込み、`C:\tmp` そのものではなくその下で動いていることを確かめる（外なら終了コード 3） |
| `scripts/scaffold.py` | 担当（`make`・`remove`）、主担当（`clean`） | 足場を作る・消す・掃除する。`C:\tmp` の下だけで動き、リンクの先をたどらない |
| `references/clerk.md` | 定型の作業の担当（Haiku） | 拾い出し・転記・書式の揃え直し。受けてはいけない作業、迷ったら `要確認` の印を付けて残すこと |
| `scripts/ledger.py` | 主担当 | 台帳を作り、段階・版・担当の ID・決定・持ち越し・出来事を書き足す。値を読む |
| `scripts/fill_request.py` | 主担当 | 依頼文の雛型を台帳の値（固有の値・決定）と引数で埋める。埋まらない欄を一覧にする |
| `scripts/check_permissions.py` | 主担当 | 担当の `tools` と settings の allow・ask・deny を照らし、権限の事前列挙の表を台帳に書く（近似） |
| `scripts/report_tool.py` | レビューア・反映の担当・主担当 | 報告書の作成（new）・指摘の抽出（extract）・件数（count・fill-counts・check-counts）・確かめる ID（targets）・判断依頼サマリーの行の選び出し（summary）・収束の判定（converge）・版（set-version）・回答の流し込み（fill-answers）。書式が合わなければ終了コード 3 |
| `scripts/diff_size.py` | 主担当 | 2 つのコミットの差の大きさ（確認の回で収束しなかったときに、台帳の記録に書く） |
| `scripts/grep_type.py` | 主担当 | 同件調査の (a) 文字列・正規表現で言い切れる型の拾い出し |
| `scripts/merge_findings.py` | 主担当 | 同件調査の (b) の 2 体の拾い出しの突き合わせ（両方／片方だけ、食い違いの割合） |
| `scripts/check_return.py` | 主担当 | 担当の最後の返答の欄（最初に読んだファイル・外れた実行）と hook のログの突き合わせ |
| `templates/進行/依頼文_同件調査_拾い出し.md`・`依頼文_同件調査_確かめ.md` | 主担当 | 同件調査の、Haiku 2 体への拾い出しの依頼と、反映の担当への確かめの依頼 |
| `templates/進行/hook設定.json` | 主担当 | hook の設定（作業フォルダ・リポジトリ・担当ごとの書いてよい場所）の雛型。段階 0 で埋めて、リポジトリの `.claude/workspace/cross-review-hook.json`（未追跡の固定のパス）に置く |

## 関連

- 担当の定義: `.claude/agents/cross-review-*.md`（6 体。うち `cross-review-clerk` は Haiku）。本文は薄く、最初に読むファイルのパスと足場の案内だけを書いている。frontmatter に hook の 3 本を持ち、子の担当を立てる `Agent` は持たない
- サブエージェントの共通の決まり: `.claude/rule-assets/subagent-common-rules.md`。設定の `SubagentStart` の hook（`.claude/hooks/subagent-start-rules.py`）が、全部の種類のサブエージェントの起動時に、文脈の先頭に足す（再開しても二重には入らない）
- `.md` のセルフチェック: rule `.claude/rules/md-self-check.md` と、チェックリスト `.claude/rule-assets/md-self-check/checklist.md`（反映の担当の反復セルフチェックの数字の正）
- 起動前の権限の事前列挙: `.claude/rules/agent-permission-runtime.md` §1
- リポジトリやテーマに固有の値は、補助ファイルに書かない。主担当が依頼文で渡す

## 担当の決まりについて

- 反映は 1 つの文書に 1 体で行い、複数なら直列にする（並列で書くと章の間の食い違いを生んだ、という振り返りによる）
- 同件調査は「型を決めて件数を出す」までで、反映する範囲は主担当が決める
- 読みやすさ・説明の精度は Round 2 では直さず、仕上げの回に回す
- 差分の点検の担当は、反映の後・レビューに回す前に、直した担当とは別の 1 体が差分だけを疑う

## 上限を見直すとき

セルフレビューと反復の上限（レビューアは `references/reviewing.md` §5、反映の担当は `.claude/rule-assets/md-self-check/checklist.md`、確認の回は論理整合性・実用性が 0.83 まで、作業指示者+人間読み手が 0.81 まで）を見直すときは、次を見る。

1. 打ち切り（上限の版の後も収束しない）や、確認の回のやり直しが起きた割合（直近 5 回のうち 20% を超えたら見直す）
2. 上限に達した回の主な目的（新しい NG の検出か、誤検知のチェックか、立場の記入か）
3. 対象の文書の性質（規模、手順を含むか、関連する資産が散らばっているか）

## 注意

- 担当は背景で動く。結果は完了の通知で届くので、届くまで次の段階へ進まない
- 担当が最初のファイルを読んだかは、最後の返答の「最初に読んだファイル」で確かめる（読み込みは自動ではない）
- 同じレビューアの再開は、台帳に控えたエージェント ID に SendMessage で行う。ID は圧縮・再起動の後も台帳から引ける
- `allowed-tools` の事前許可は、skill を呼んだターンの間だけ、メインのセッションに効く。担当の許可や長い作業の許可は `settings.json` / `settings.local.json` で行う
- 担当の定義（`.claude/agents/cross-review-*.md`）を置いた・書き換えた応答の中では、その定義はまだ使えない。次の応答の区切りから使える（定義を直した後は、応答を 1 度区切ってから担当を起動する）
