# 実測スクリプト

[結論・構成案](../結論・構成案.md) の 【実測】 を再現するスクリプトである。測った環境、項目ごとの結果、判定を誤りやすい点は [実測記録の別紙](../結論・構成案【別紙】実測記録.md) にある。ここには、実行の仕方とスクリプトの一覧だけを書く。

## 実行の仕方

Git Bash（または任意の bash）から実行する。各スクリプトは、自分と同じディレクトリに作業用のフォルダを作る（毎回作り直す。`.gitignore` 済み）。`claude` を起動するスクリプトは、API の利用が発生する。

```bash
cd reports_v2.1/01.配布・統制方針/verification
bash switch-fail.sh
```

### 実行の順序（必ず守る）

単独で実行できるのは `switch-fail.sh` と `ffonly-test.sh` だけである。残りは、**足場を作るスクリプトを先に実行する**。

| 系列 | 実行順 |
|---|---|
| 入れ子クローン | `nestclone-setup.sh` → `nestclone-run.sh`・`nestclone-worktree.sh` → `nestclone-branch.sh` → `nestclone-branch2.sh` → `nestclone-updaterefs.sh` |
| 発火 | `trigger-setup.sh` → `trigger-run.sh`・`trigger-edit.sh`・`trigger-write.sh`・`trigger-bash-forms.sh`・`trigger-adddir.sh`（後ろの 5 本は順不同） |

足場が無いまま後段を実行すると、最初の `cd` で止まる（全スクリプトの `cd` に `|| exit 1` を付けてある）。`cd` の失敗を検査していなかった版では、後続の `git add -A`・`commit`・`reset --hard` がこのリポジトリ自身に対して実行された（2026-11-21 に実際に起きた。未追跡のファイルが誤ったコミットに取り込まれ、`reset --hard` で作業ツリーから消えたので、コミットから復元した）。スクリプトを足したり直したりするときは、`cd` の失敗で必ず止まる形を保つこと。

## スクリプトの一覧

| スクリプト | 測るもの | 本紙の節 |
|---|---|---|
| `nestclone-setup.sh` | **足場**: 作業リポジトリ（`.gitignore` に `.claude/`）の `.claude/` が別のリポジトリのクローン、という案C-1 の形を組む | §3-1 |
| `nestclone-run.sh` | 上の足場で、`CLAUDE.md`・`paths:` なしの rule・`settings.json` の `env`・skill の 4 つがロードされるかを合言葉で確かめる | §3-1 |
| `nestclone-worktree.sh` | 作業リポジトリの linked worktree から起動したとき、入れ子クローンの資産がどこまでロードされるか（`CLAUDE.md`・rule・`settings.json` はロードされず、skill だけが本体の checkout から読まれる） | §3-1 |
| `nestclone-branch.sh` | ブランチ運用の一巡。途中の `git switch -c java/design` が D/F コンフリクトで失敗し、その後の手順も失敗が連鎖する（失敗の記録として、そのまま実行する） | §5-3 |
| `nestclone-branch2.sh` | D/F コンフリクトを `git branch` の 2 コマンドで再現した後、名前を変えて（`java/_base`・`java/design`）多段の rebase からメンバー側の切替までを通す。`git pull --ff-only` の失敗も測る | §5-3、§5-4、§5-5 |
| `nestclone-updaterefs.sh` | `rebase.updateRefs` が中間ブランチも進めること、中間ブランチをローカルに持たないクローンでは取り残されること | §5-4 |
| `trigger-setup.sh` | **足場**: サブディレクトリ `sub/` に、`paths:` 付きの rule の対象ファイル・`sub/CLAUDE.md`・`sub/.claude/skills/` を置く | §3-2 |
| `trigger-run.sh` | 先行操作（なし・Read ツール・Bash の `cat`・Grep ツール）ごとの発火 | §3-2 |
| `trigger-edit.sh` | Edit ツール単独（Read を許可しない）での Edit の成否と発火。モデル名を引数で渡す（既定は Claude Haiku 4.5 と 5.5） | §3-2 |
| `trigger-write.sh` | Write ツール単独（新規作成）での発火 | §3-2 |
| `trigger-bash-forms.sh` | Bash コマンドの形（`head`・`grep`・パイプ付き・複数ファイル）ごとの発火。`trigger-bash-forms-show.py` が、モデルの実行したツール呼び出しと回答を表示する | §3-2 |
| `trigger-adddir.sh` | 起動時の `--add-dir <サブディレクトリ>` で skills がロードされること、非対話では `/add-dir` が使えないこと | §3-2 |
| `ffonly-test.sh` | リモートが rebase して force-push した後、`git pull --ff-only` が終了コード 128 で失敗し、`fetch` と `reset --hard` で復旧できること | §5-5 |
| `switch-fail.sh` | `switch` の失敗を検査せずに `reset --hard` を続けると、ブランチ名は保たれたまま中身が別のブランチで上書きされること | §5-6 |

足場のブランチ名は、本紙の `main` に当たるものが `master`、`java/base` に当たるものが `java/_base` である。

`settings.local.json` が `switch` と `reset --hard` の後も残ることは、`nestclone-branch.sh`・`nestclone-branch2.sh`・`nestclone-updaterefs.sh` が測っている（`ffonly-test.sh` は測っていない）。
