---
name: cross-review
description: 文書のクロスレビューを、構成の確認から 1.0 版（作業指示者の判断）まで進める。観点別のレビューア・反映の担当・差分の点検の担当・定型の作業の担当のサブエージェントを起動し、止まる所で作業指示者に伺う。メインのセッションで /cross-review として明示的に呼ぶ。
disable-model-invocation: true
argument-hint: "[台帳のパス、または対象の文書のパス]"
allowed-tools: Agent(cross-review-logic-reviewer), Agent(cross-review-practicality-reviewer), Agent(cross-review-reader-reviewer), Agent(cross-review-reviser), Agent(cross-review-diff-checker), Agent(cross-review-clerk), SendMessage, Read, Write, Edit, Grep, Glob, Bash(python -I -X utf8 .claude/skills/cross-review/scripts/*), Bash(git -C * diff *), Bash(git -C * show *), Bash(git -C * log *), Bash(git -C * status *)
---

# クロスレビューの進行（主担当用）

あなたは主担当である。進行、範囲の絞り込み、作業指示者への伺い、コミットを行う。レビュー・反映・点検は自分で行わず、担当のサブエージェントに任せる。担当の決まりは補助ファイルにある（`.claude/skills/cross-review/references/` の `rules.md`・`reviewing.md`・`revising.md`・`diff-check.md`・`clerk.md`）。担当は定義の指示で最初にこれらを Read で読む。主担当は依頼文を書く前に `references/rules.md` を Read で 1 回読む。担当用のファイルの手順を主担当が自分で行わない。

引数: $ARGUMENTS（台帳のパスなら、その台帳の「今の段階」から再開する。対象の文書のパスなら段階 0 から始める。無ければ作業指示者に対象を尋ねる）

## 主担当の決まり（この作業の間ずっと守る）

1. **スクリプトにできることはスクリプトを流す**（下の「道具」の表）。手で台帳・依頼文・件数・版を書かない。スクリプトが書式の誤りで止まったら（終了コード 3）、直してから流し直す。判断で上書きしない
2. **台帳**: `<作業フォルダ>\11_interim-artifacts\クロスレビューの台帳.md` を `ledger.py init` で作り、段階・版・担当の ID・決定・持ち越し・出来事を `ledger.py` で書き足す。圧縮や再起動の後は、まず台帳を読んで再開する
3. **判断は自分で読んでから**: 担当の報告の要約だけで決めない。決める前に、対象の文書の該当の文を自分で Read で読む
4. **依頼文はファイルに書く**: `fill_request.py` で台帳の値を埋めて `<作業フォルダ>\11_interim-artifacts\依頼文_<段階>_<担当名>.md` を作る。役割ごとの値は `名前=値` の引数で渡す。埋まらなかった欄（雛型で `【手】` の印を付けた欄、引数で渡さなかった欄）だけを判断で埋める
5. **反映は 1 つの文書に 1 体**。複数で行うなら直列にする。並列にしてよいのは、観点の違うレビュー（Round 1・確認の回）、型の違う同件調査、意味で判定する型の拾い出しの 2 体（読むだけで直さないため）だけ
6. **反映の後は必ず差分の点検**を別の 1 体で挟む。点検で見つかったものを直したら、直した分をもう一度点検する。レビューに回すのはその後
7. **直す範囲に上限を置く**: Round 2 で反映するのは、CRITICAL・IMPORTANT の直しと、その同じ型の誤りだけ。読みやすさ・説明の精度は段階 5 に回す
8. **各段階の終わりにコミットする**（作業指示者の決まりに従う。担当には書き込み系の git をさせない）
9. **hook の設定とログ**: 段階 0 で `templates/進行/hook設定.json` を埋めて、リポジトリの `.claude/workspace/cross-review-hook.json` に Write する（無い・壊れている・雛型のままだと、担当の Bash・PowerShell・Write・Edit が全部止まる）。hook が止めた記録は `<作業フォルダ>\30_tmp\cross-review-hook.log` に足される。足場は全部の担当が終わった後に `scaffold.py clean` で掃除する（主担当だけ）

## 道具（`python -I -X utf8 .claude/skills/cross-review/scripts/<名前> …`。使い方は各スクリプトの先頭）

| すること | スクリプト |
|---|---|
| 台帳を作る・段階・版・担当・決定・持ち越し・出来事を書き足す・値を読む | `ledger.py`（init・stage・version・agent・decide・carry・log・get） |
| 依頼文を雛型と台帳の値で作る | `fill_request.py <台帳> <役割> <出力> 名前=値…` |
| 権限の事前列挙の照合を台帳に書く | `check_permissions.py .claude/agents .claude/settings.json .claude/settings.local.json --ledger <台帳>` |
| 報告書をテンプレートから作る | `report_tool.py new <観点> <置き場所> <日付> <対象> <コミット>` |
| 指摘の一覧・件数・件数表の記入と検算 | `report_tool.py`（extract・count・fill-counts・check-counts） |
| 確認の回で確かめる ID | `report_tool.py targets <報告書> <n>` |
| 判断依頼サマリーの行の選び出し | `report_tool.py summary <報告書>` |
| 収束の判定と次の版 | `report_tool.py converge <報告書> <n>` |
| 版と変更履歴を書き換える | `report_tool.py set-version <報告書> <版> <日付> <内容>` |
| 回答の欄へ 1 回だけ流し込む | `report_tool.py fill-answers <報告書> <回答ファイル>` |
| 差分の大きさ（収束しなかったときに台帳に書く） | `diff_size.py <リポジトリ> <前> <今> <パス>…` |
| 同件調査の (a) 文字列・正規表現の型の拾い出し | `grep_type.py <型> <正規表現> <出力.tsv> <文書>…` |
| 同件調査の (b) の 2 体の結果の突き合わせ | `merge_findings.py <A.tsv> <B.tsv> <出力.md>` |
| 担当の返答と hook のログの突き合わせ | `check_return.py <返答を写したファイル> <subagent_type> <agent_id> <ログ>` |
| LF の確かめ・足場 | `check_lf.py`・`scaffold.py`（make・remove・clean） |

## 段階

段階ごとの詳しい手順は、その段階に入る時に `references/段階ごとの手順.md` の該当の節を Read で読む。⏸ は作業指示者の返事を待って止まる所。

| 段階 | すること | 起動する担当 | 出口 |
|---|---|---|---|
| 0 準備 | 台帳・hook の設定・権限の照合。扱う状態の範囲を決める（手順を含む文書のとき）。判断のための文書と運用の手順書を分ける（分けないときは合意を得る） | なし | ⏸ 状態の範囲と文書の分け方に、作業指示者が合意 |
| 1 構成の確認 | 執筆の前の構成案を 1 回だけ確かめる | reader-reviewer（構成の確認） | ⏸ 構成の選択を作業指示者が決める。執筆へ |
| 2 Round 1 | 論理整合性と実用性の 2 観点で 0.8 版を書く | logic-reviewer・practicality-reviewer（並列） | 2 本の報告書が 0.8。コミット |
| 3 Round 2 | 回答 → ⏸ 裁定 → 同件調査（(a) スクリプト／(b) clerk 2 体 → 突き合わせ → 片方だけを reviser が確かめる）→ 範囲の絞り込み → 反映 → 差分の点検 | reviser → clerk×2（並列）→ reviser → reviser（1 体）→ diff-checker | 差分の点検で D-I が 0。コミット |
| 4 確認の回 | 同じレビューアを再開し、前の回の指摘の解消と、差分の中の新しい欠陥を確かめる | 2 観点のレビューア（SendMessage で再開。並列） | `converge` で観点ごとに判定 → 0.9。収束しない観点は台帳に記録して（差の大きさは `diff_size.py`）、版を 1 つ進めて段階 3 へ。0.83 の後も収束しなければ打ち切り → コミット → ⏸ 報告 |
| 5 仕上げ | 2 観点が収束か打ち切りになった後。作業指示者+人間読み手の観点のレビューと、内容を変えない直し | reader-reviewer → reviser（仕上げ）→ diff-checker（仕上げ）→ reader-reviewer（確認の回） | 作業指示者+人間読み手の報告書が 0.9。版の上限は 0.81（収束しなければ 0.81 で直し・点検・確認をもう 1 回だけ。それでも残れば打ち切り、残った指摘は段階 6 の判断待ちへ）。コミット |
| 6 判断（1.0） | 判断待ち事項を作り、作業指示者に判断を仰ぐ。態度表明を反映する。差戻しの指摘は段階 3・4 を 1 回通す | reviser（1.0 の反映）→ diff-checker | ⏸ 作業指示者の判断 → 反映・点検 → 全部の報告書が 1.0。コミット |

## 判断の割り込み（どの段階でも）

次のどれかが出たら、その時点で中断し（⏸）、作業指示者に裁定を仰ぐ。これは正式な手順であり、段階の途中でも行う。

- 設計の選択・扱う範囲の選択で、決めないまま進めると文書が無用に膨らむもの
- 担当の報告の「判断してほしいこと」のうち、主担当の権限で決められないもの

確認の回で収束しなかったときは、割り込みにも報告にもせず、台帳に記録して次の版へ進む（打ち切りは、2 観点は 0.83 の後に段階 4 の ⏸ の報告、仕上げの回は 0.81 の後に段階 6 の判断待ちへ）。伺い方: 事項ごとに、選択肢・代償・主担当の推奨・決まらないと進まない手順を書く。決まったら `ledger.py decide` で台帳に書き、以後の依頼文の「決まっていること」に入れる。決まるまで進める場合は、手順・例・表をどの側で書くかを 1 つに決めて台帳に書く。

## サブエージェントの起動

| 担当 | `subagent_type` | 最初に読むファイル（`references/` の下とテンプレート） |
|---|---|---|
| 論理整合性のレビューア | `cross-review-logic-reviewer` | rules.md・reviewing.md・`templates/レビューア/論理整合性.md` |
| 実用性のレビューア | `cross-review-practicality-reviewer` | rules.md・reviewing.md・`templates/レビューア/実用性.md` |
| 作業指示者+人間読み手のレビューア | `cross-review-reader-reviewer` | rules.md・reviewing.md・`templates/レビューア/作業指示者+人間読み手.md`（構成の確認では `構成の確認.md`） |
| 反映の担当 | `cross-review-reviser` | rules.md・revising.md |
| 差分の点検の担当 | `cross-review-diff-checker` | rules.md・diff-check.md・`templates/点検/差分の点検.md` |
| 定型の作業の担当（Haiku） | `cross-review-clerk` | rules.md・clerk.md |

1. 起動の前に `check_permissions.py … --ledger <台帳>` を流す。終了コード 1（deny・ask に当たる決まった呼び出しがある）なら、`.claude/rules/agent-permission-runtime.md` §1.3 で対処を決めて台帳に書く。2（引数の誤り）・3（settings が壊れている・台帳に権限の表が無い）なら、直してから流し直す
2. Agent ツールで起動する。`prompt` は「依頼文 `<パス>` を全部読んでから始める。最後の返答は依頼文の形で。」の 1〜2 文にする
3. 担当は背景で動く。完了の通知が来るまで、その担当の結果を推測で書かない。並列にしたものは、全部の通知が来てから次へ進む
4. 完了の通知のエージェント ID を `ledger.py agent` で台帳に書く。確認の回では、その ID に SendMessage で依頼文のパスを送って再開する。再開できないときは新しい担当を起動し、依頼文に「報告書を引き継ぐ」と書く
5. 担当の最後の返答を `<作業フォルダ>\30_tmp\返答_<担当名>.md` に Write し、`check_return.py` を流す。終了コード 1 なら、足りないファイルの読み直しと見直しを SendMessage で求める。hook のログが無いだけのとき（ログは止めた・知らせたときにだけ書かれる。hook の設定が読め、渡したログのパスが設定の work_folder から出るパスと同じとき）は、`check_return.py` が注意（「記録 0 行（ログが無い）」）にして終了コード 0 を返す。設定が読めない・パスが違うときは 1 なので、設定の置き場所と渡すパスを直して流し直す（担当には求めない）。結果を `ledger.py log` で台帳に書く。許可されなかった呼び出しがあれば、`agent-permission-runtime.md` §2 の手順で対処し、その担当だけをやり直す
