# 実測スクリプト

[結論・構成案](../結論・構成案.md) の【実測】を再現するスクリプトである。測った環境、項目ごとの結果、判定を誤りやすい点は [実測記録の別紙](../結論・構成案【別紙】実測記録.md) にある。ここには、実行の仕方とスクリプトの一覧だけを書く。

## 実行の仕方

Git Bash（または任意の bash 4 以降）から実行する。`claude` を起動するスクリプトは、API の利用が発生する。セッション記録を読むために Python 3 が要る（`python` が無ければ `python3` を使う）。ランチャーと移行のスクリプトは PowerShell（`pwsh`。`launcher-states.sh` は Windows PowerShell 5.1 の `powershell.exe` も選べる）が要る。

```bash
cd "$(git rev-parse --show-toplevel)/claude-dir-sharing-governance/reports_v2.1/01.配布・統制方針/verification" || exit 1
VERIF_ROOT=C:/tmp/v21-verif bash switch-fail.sh
```

### 足場の場所（`VERIF_ROOT`）

各スクリプトは、作業用のリポジトリ（足場）を環境変数 `VERIF_ROOT` の下に作る（既定 `C:/tmp/v21-verif`。毎回作り直す）。このディレクトリには足場以外を置かないこと。スクリプトが消すのは `VERIF_ROOT` の下だけである。

`VERIF_ROOT` は、**`C:\tmp` の下の絶対パスで、上位のディレクトリに `CLAUDE.md` も `.claude/` も無く、git リポジトリの中でも trust 済みでもない場所**にする。

- **`C:\tmp` の下に指定する**（`C:/tmp/<名前>`・`/c/tmp/<名前>`・`C:\tmp\<名前>` の形）。`lib.sh` は、ほかの場所・相対パス・`C:\tmp` そのもの・`..` を含むパス・リンクをたどると `C:\tmp` の外に出るパスを、何も作らずに終了コード 3 で止める（Windows（Git Bash）で確かめた）。既定の `C:/tmp/v21-verif` もこの検査を通る。**Git Bash の `/tmp` は利用者の Temp（`C:\Users\<利用者>\AppData\Local\Temp`）であって `C:\tmp` ではない**ので、`VERIF_ROOT=/tmp/…` も止まる。Windows 以外の環境では、この検査のため実行できない見込みである（確かめていない）
- このリポジトリの中に足場を置くと、上位の `CLAUDE.md`（リポジトリのルートとテーマのフォルダのもの）が子のセッションに入り、モデルの回答に混ざる。`lib.sh` は、パスに `cc-relative-info` を含む `VERIF_ROOT` と、git リポジトリの中の `VERIF_ROOT` を拒否する（解決した後のパスでも確かめる）
- **scratchpad（`…\AppData\Local\Temp\claude\<ID>\<セッションID>\scratchpad\…`）の下にも置かない**。その形のパスの下では、プロジェクトの資産がロードされない。`lib.sh` はこれも拒否する
- trust 済みのフォルダの下に置いた場合に `nestclone-trust-noninteractive.sh` の結果が変わるかは、このスクリプトでは測っていない。条件をそろえるため、trust 済みのフォルダの下には置かない

```bash
VERIF_ROOT=C:/tmp/my-verif bash trigger-setup.sh
```

足場を消すときは、`VERIF_ROOT` のディレクトリごと消す。スクリプトは足場を作り直すだけで、終わった後に消さない。

### 起動の条件（環境変数）

`claude` は、すべて `lib.sh` の `verif_claude` から起動する。**既定では、`CLAUDE` で始まる環境変数（`CLAUDECODE` を含む）をすべて外して起動する**。stdin は `/dev/null` にする。

**Claude Code のセッションの中（Bash ツール）から実行するか、別の端末から実行するかで、条件が変わる。** セッションの中から実行すると、子の `claude` は親のセッションの環境変数（`CLAUDECODE`・`CLAUDE_CODE_SESSION_ID`・`CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD`・`CLAUDE_CODE_ENTRYPOINT`・`CLAUDE_CODE_ENABLE_AUTO_MODE`・`CLAUDE_CODE_MESSAGING_*`・`CLAUDE_PID`・`CLAUDE_EFFORT` など）を引き継ぐ。たとえば `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` を引き継ぐと、`--add-dir` で足したディレクトリの `CLAUDE.md` が起動時に入る。既定で外すのはこのためである。別の端末から実行すると、親のセッションの環境変数はもともと無い。ただし、環境変数を外した起動と別の端末からの起動は同じではない（親のプロセスのほかの環境変数は残る）。実測記録の結果は、すべて Claude Code のセッションの中から実行したもので、別の端末からは測っていない。

| 環境変数 | 意味 |
|---|---|
| `VERIF_INHERIT_ENV=1` | 外さずに、引き継いだまま起動する（親のセッションと同じ条件を再現するとき） |
| `VERIF_KEEP_ENV="名前 名前"` | 外す対象から除く変数。認証に要る変数があればここに書く（2026-11-21 の実測では、すべて外しても認証は通った） |
| `VERIF_MODEL` | `claude -p` のモデル（既定 `haiku`） |

各セッションの出力の冒頭に、起動の条件（環境変数を外したか引き継いだか・外した変数の名前・足場のパス・モデル・CLI の版・使えるツール・時刻）が出る。値は出さない。

外すのは環境変数だけで、user スコープ（`~/.claude/` の設定・plugin・hooks・skills、claude.ai と user の MCP）は切り離していない。子のセッションには user の plugin の hooks が走り、`--tools` で絞っても MCP のツールは残る（init の行に数が出る）。`--permission-mode` を付けないスクリプトは、user の設定の permission mode で始まる。

Claude Code のセッションの中から PowerShell を起動すると、環境変数 `PSExecutionPolicyPreference`（2026-11-22 の実測では `RemoteSigned`）を引き継ぎ、実行ポリシーがその値になる。`launcher-states.sh` の状態 N14 だけは、この変数を外して実行する。

### 判定の証拠（`stream-show.py`）

`claude` を起動するスクリプトは `--output-format stream-json --verbose` で実行し、`stream-show.py` で次を表示する。

- init: 実際に使われたモデル・permission mode・使えるツール・起動時に見えている skills と agents
- ツール呼び出しと結果。**手番**（応答の `message.id`）ごとに番号を振る。先行操作と Skill が同じ手番に並んでいれば、Skill の起動の成否では判定できない（その旨を表示する）
- ツールの結果の permission の判定（`accept`・`reject` と出所）と、`permission_denials`。ツールの結果は先頭 300 字だけを出す。Agent ツールの結果は前置きが長いので、300 字より後ろに合言葉の形の文字列があれば、別の行に出す
- **セッション記録**（`~/.claude/projects/<足場のパスから作られる名前>/<session_id>.jsonl`。読むだけ）から、Claude Code が文脈に足したもの: 起動時の指示（`instructions`＝`CLAUDE.md` と `paths:` なしの rule）、`nested_memory`（`paths:` 付きの rule とサブディレクトリの `CLAUDE.md`）、`dynamic_skill`（サブディレクトリの skill）。**陰性（ロードされない）も、モデルの回答ではなくこの記録で判定できる**。記録には利用者のメールアドレス等も入っているので、表示するのはこれらの種類のパスと名前だけである

stream-json そのものには、文脈に足したものの記録は出ない（2.1.330）。セッション記録は既定の保存期間を過ぎると消える。

使えるツールは `--tools` で絞る。`--allowedTools` は確認なしで実行するツールの指定で、使えるツールを絞らない。`--tools` は MCP のツールには効かない。

### 実行の順序（必ず守る）

単独で実行できるのは次のスクリプトである（足場は自分で作る）。

- `switch-fail.sh`・`ffonly-test.sh`・`nestclone-localfile.sh`・`nestclone-trust-noninteractive.sh`・`nestclone-localsettings.sh`（足場は `$VERIF_ROOT/nclocal`・`nclocal-track`）・`maintain-move-asset.sh`
- `maintain-scenes.sh`・`maintain-controls.sh`・`maintain-remedy.sh`（どれも場面ごとに `maintain-setup.sh` を呼んで、別の名前の足場を作る）
- `launcher-states.sh`（足場は `$VERIF_ROOT/launcher-<シェル>-bom<0|1>`）・`launcher-remedy.sh`（足場は `$VERIF_ROOT/lremedy-<シェル>`）・`migrate-submodule.sh`（足場は `$VERIF_ROOT/migrate`）・`migrate-local-edit.sh`（足場は `$VERIF_ROOT/migrate-local-edit`）

残りは、**足場を作るスクリプトを先に実行する**。

| 測定のまとまり | 実行順 |
|---|---|
| 入れ子クローン | `nestclone-setup.sh`・`nestclone-setup.sh nodeny` → `nestclone-run.sh`（引数 4 通り）・`nestclone-worktree.sh` → `nestclone-branch.sh` → `nestclone-branch2.sh` → `nestclone-updaterefs.sh` |
| 発火 | `trigger-setup.sh` → `trigger-matrix.sh`・`trigger-adddir.sh`（順不同。ただし同じ足場を使うので、同時には実行しない） |

`nestclone-branch.sh` 以降は共有リポとメンバー側のクローンを書き換えるので、`nestclone-run.sh`・`nestclone-worktree.sh` の後に実行する。**もう一度通すときは `nestclone-setup.sh` からやり直す。** 足場を作り直さずに後段を再実行すると、`nestclone-branch2.sh` は `java/_base を作れない` で止まり、`nestclone-updaterefs.sh` は止まらずに 1 回目と別の履歴の上で通る（終了コード 0 のまま結果が変わる）。単独で実行できるスクリプトは、毎回足場を作り直すので、続けて何度実行してもよい。

足場が無いまま後段を実行すると、最初の `verif_enter_repo` で止まる。`cd` が失敗したまま続けると、後続の `git add -A`・`commit`・`reset --hard` が、このリポジトリ自身に対して実行される。このため、

- 書き込み系の git（`add`・`commit`・`reset`・`switch`・`clean`・`rebase`・`push`・`branch`・`worktree`）の前には、必ず `verif_enter_repo <dir>` で移る。これは `cd` に失敗したら止まり、移った先が `VERIF_ROOT` の下にある**独立したリポジトリのトップ**（`git rev-parse --git-dir` が `.git`。linked worktree なら自身がトップ）であることを確かめ、そうでなければ止まる
- 足場の削除は `verif_fresh_dir` だけで行い、`VERIF_ROOT` の外は消さない

スクリプトを足したり直したりするときは、この形を保つこと。

## スクリプトの一覧

| スクリプト | 測るもの | 本紙の節 |
|---|---|---|
| `lib.sh` | **共通**: `VERIF_ROOT` の確認（`C:\tmp` の下か、リポジトリの外か）、足場へ移るときの検査、`claude` の起動（環境変数を外す既定）、起動の条件の表示、PowerShell を `-Command` で呼ぶときの終わり方（構文エラーを終了コード 0 にしない） | — |
| `stream-show.py` | **共通**: stream-json とセッション記録から、判定の証拠を表示する | — |
| `nestclone-lib.sh` | **共通**: `nestclone-run.sh`・`nestclone-worktree.sh` の 2 種類のセッション（資産・deny） | — |
| `nestclone-setup.sh [deny\|nodeny]` | **足場**: 作業リポジトリ（`.gitignore` に `.claude/`）の `.claude/` が別のリポジトリのクローン、という案C-1 の形を組む。`deny`（既定）は共有リポの `settings.json` に `permissions.deny` `["Bash(./denyprobe.sh)"]` を書く。`nodeny` は書かない対照。作業リポジトリには、実行されるとファイルを作る `./denyprobe.sh` を commit する（`sub/` にも同じもの） | §3-1 |
| `nestclone-run.sh [deny\|nodeny] [root\|sub]` | 足場のルートまたはサブディレクトリ `sub/` から起動し、`CLAUDE.md`・`paths:` なしの rule・`settings.json` の `env`・skill・agent（`probeagent`）がロードされるか、`permissions.deny` が効くか（`./denyprobe.sh` が実行されないか）を測る | §3-1、§4-2、§5-7 |
| `nestclone-worktree.sh` | 作業リポジトリの linked worktree（`.claude/` が無い）から起動したとき、同じ項目がどうなるか | §3-1、§5-7、§8-2 V12 |
| `nestclone-trust-noninteractive.sh [scaffold-only]` | V7 の前段（非対話）。`.claude/settings.json` の `permissions.allow` が `claude -p --permission-mode default` で使われるか、stderr の警告に出る trust の key。入れ子クローンの形と、作業リポジトリが `.claude/` を追跡する普通の形を比べる。`~/.claude.json` は読むだけ（`trust-lookup.py`）。`scaffold-only` を付けると、入れ子クローンの足場（`trust-nested-<時刻>`）だけを作り、`claude` は起動しない（V7 の対話の手順で使う足場を作るとき） | §3-4、§8-2 V7 |
| `trust-lookup.py` | **共通**: `~/.claude.json` の `projects` から、指定したパスの trust の記録（`hasTrustDialogAccepted`）を読んで表示する（読むだけ）。`nestclone-trust-noninteractive.sh` と §8-2 の V7 の手順が使う | §8-2 V7 |
| `nestclone-branch.sh` | 当初の命名（`java`・`java/design`）で `git switch -c java/design` が D/F コンフリクトで失敗し、その後の手順も失敗が連鎖することの記録。多段 rebase・切替・`settings.local.json` は**測れていない** | §5-3 |
| `nestclone-branch2.sh` | D/F コンフリクトを `git branch` の 2 コマンドで再現した後、名前を変えて（`java/_base`・`java/design`）作り直し、master を進めてから多段の rebase、メンバー側の切替、`git pull --ff-only` の失敗までを通す | §5-3、§5-4、§5-5 |
| `nestclone-updaterefs.sh` | `rebase.updateRefs` が中間ブランチも進めること。中間ブランチをローカルに持たないクローンで rebase すると、`Updated the following refs` が出ず、`origin` の中間ブランチは master を取り込まないままであること（`merge-base --is-ancestor` で示す）。メンバー側で `pull --ff-only` が失敗した後に `reset --hard` で復旧できること | §5-4、§5-5 |
| `nestclone-localfile.sh` | メンバーの `settings.local.json` が `switch` と `reset --hard` の後に残るかを、(i) 共有リポで ignore 済み (ii) ignore なし (iii) あるブランチで追跡されている、に分けて測る。`git status --porcelain` と `git clean -fd`・`-fdx` が何を消すか | §5-5 |
| `nestclone-localsettings.sh [回数] [場面...]` | V6。入れ子クローン `.claude/` の中に置いた、git が追跡しない `.claude/settings.local.json`（`env` と `permissions.deny`）が読まれるかを、作業リポジトリのルート・サブディレクトリ `sub/`（`.claude/` なし）・linked worktree のルートから起動して測る。共有の `settings.json` の `env` を並べて比べる。対照は作業リポジトリが `.claude/` を追跡する形（`settings.local.json` だけ gitignore）のルートと `sub/`。追加の場面 `nest-sublocal` は `sub2/.claude/settings.local.json` を置いた `sub2/` から起動する。足場は自分で作る（`$VERIF_ROOT/nclocal`・`nclocal-track`） | §1-4、§3-1、§8-2 V6 |
| `trigger-setup.sh` | **足場**: サブディレクトリ `sub/` に、`paths:` 付きの rule の対象ファイル・`sub/CLAUDE.md`・`sub/.claude/skills/` を置く | §3-2 |
| `trigger-matrix.sh [回数] [行...]` | 先行操作の形ごとの発火。行: 対照・Read・Write（新規作成）・Edit（Read は使えない／Read も使える／Read は使えるが呼ばない。それぞれ Claude Haiku 5.5・4.5）・Bash の `cat`・`head`・`grep`（各 1 ファイル）・パイプ付き・複数ファイル・Grep ツール。使えるツールは `--tools` で絞る | §3-2 |
| `trigger-adddir.sh` | 起動時の `--add-dir <サブディレクトリ>` で skills がロードされること、起動時に `sub/CLAUDE.md` が入るか（環境変数で変わる）、非対話では `/add-dir` が使えないこと | §3-2 |
| `ffonly-test.sh` | リモートの履歴が書き換えられた（`commit --amend` ＋ force-push）後、`git pull --ff-only` が終了コード 128 で失敗し、`fetch` と `reset --hard` で復旧できること | §5-5 |
| `switch-fail.sh` | ランチャーと同じく `switch <B>` と `reset --hard origin/<B>` に**同じ名前**を渡し、switch の失敗を検査しないと、どの場面で「ブランチ名は元のまま、中身が `origin/<B>`」になるか（存在しないブランチ・未追跡ファイルとの衝突・ignore されたファイル・D/F） | §5-6 |
| `launcher-example.ps1` | 本紙 §5-6 のランチャー最小例と同じもの（UTF-8・BOM なし・LF で置いてある） | §5-6 |
| `launcher-example-check.ps1` | ランチャー例に、`switch` の前に「指定のブランチが共有リポにあるか（大文字小文字も区別して）と、手元の旧い名前と衝突しないか」を確かめる検査（3-a'）を足した版。本紙 §5-6 の選択肢 | §5-6 |
| `launcher-states.sh [出どころ]` | ランチャー例を、`$SharedUrl` と末尾の `claude @ClaudeArgs` の 2 行だけ差し替えて（`claude` の代わりに、受け取った引数を 1 個ずつ表示する）、状態ごとに通す。状態は C1〜C18（初回の clone・空や非空の `.claude`・ローカル変更・未追跡のファイル・存在しないブランチ・fetch の失敗・force-push の後・リモートで消えたブランチ・大文字小文字・detached HEAD・サブディレクトリからの起動）、A1〜A7（`claude` へ渡す引数）、N1〜N14（`-Branch` の書き間違い・大文字小文字・`index.lock`・`.claude` がファイル・名前の改名・二重引用符と空の引数・実行ポリシー）。`LSHELL=pwsh\|powershell` でシェル（PowerShell 7 か Windows PowerShell 5.1）、`LBOM=0\|1` で BOM の有無を選ぶ。出どころの既定は `launcher-example.ps1` で、本紙（`.md`）を渡すとコードブロックを抜き出して使う。`launcher-example-check.ps1` も渡せる。`claude` は起動しない | §5-6 |
| `launcher-remedy.sh [場面...]` | 本紙 §7-4 の「ランチャーが止まったとき」の表と §7-3 の対処を、止める → 書いてある対処（PowerShell で移す・消す・写す）→ もう一度起動、の順で通す。場面は T01〜T18（表の行ごと。`agent-memory/`・`worktrees/` を外へ移して戻す、戻す先が作り直されていたとき、`index.lock` を消す、実行ポリシーの (b)・(c) の形、BOM を付けて配り直す、など）と M73（通常のディレクトリから移った作業リポジトリで、`git checkout -- .claude` で戻してから pull）。ランチャーは `launcher-states.sh` と同じく 2 行だけ差し替え、BOM を付ける。`LSHELL=pwsh\|powershell` でシェルを選ぶ。`claude` は起動しない | §5-6、§7-3、§7-4 |
| `maintain-setup.sh [名前]` | **足場**: 共有リポ（bare）に `main` → `java/base` → {`java/design`・`java/ut`} と `main` → `python/base` → `python/coding` の 2 系列を置き、全ブランチをローカルに持つメンテナーのクローン `m`・`m2` を作る。その後に PR のマージに当たる操作で origin の `main` だけを進める（`m`・`m2` のローカルの `main` は古いまま）。足場は `$VERIF_ROOT/<名前>`（既定 `maintain`） | §5-4 |
| `maintain-steady.sh` | 本紙 §5-4 の定常手順（①〜④。③ の後で入力を待つ）そのもの。入力を待つ前に、push するブランチと `main` のこのクローンでの先頭を控え、push の直前に比べる（1 つでも動いていれば、1 本も push せずに止まる）。プレースホルダ（`REPO`・`URL`）のままで、単独では実行しない（`maintain-scenes.sh` が 2 行だけ差し替えて使う） | §5-4 |
| `maintain-middle.sh` | 中間ブランチ（土台）だけを更新したときの手順。`main` を含むかは検査しない（`main` も進んでいるときは、この手順の後に定常手順を実行する）。入力を待つ間に土台と子が動いていないかを、push の直前に比べる。プレースホルダのまま | §5-4 |
| `maintain-steady-resume.sh` | `maintain-steady.sh` に、rebase の衝突を手で解いた後に `resume` で続ける形を足したもの（① の値を `.git/steady-old` に保存し、`resume` で読み戻す）。本紙 §5-4 の選択肢。プレースホルダのまま | §5-4 |
| `maintain-scenes.sh [場面...]` | 上の 3 つを、場面ごとに作った足場（`$VERIF_ROOT/sc-<場面>`）で通す。プレースホルダの 2 行だけを差し替え、差し替えた行数を diff で確かめる。場面: 基準・2 回続けて・③' で中止・`y` 以外の入力・手元の PR 用のブランチ・origin で消したブランチ・origin の一覧外のブランチ・origin に無いブランチ・未コミットの変更・rebase の衝突（`--abort`・解いた後・`resume`）・入力待ちの間の別のメンテナーの push・別のブランチや detached HEAD から・新しいクローン・旧い名前のブランチ（D/F）・`--single-branch` のクローン・push していないコミット・資産を既にある土台へ移す・2 人目のメンテナー、中間ブランチの手順の基準・手元の古いブランチ・土台の書き換え・`main` も進んでいるとき（中間ブランチの手順の後に定常手順・定常手順を先に実行して止まった後）。対照として `control-*.sh` も通す | §5-4、§7-2 |
| `maintain-remedy.sh [場面...]` | 定常手順が止まる場面で、本紙に書いた対処をしてからもう一度実行し、通るかを見る（足場は `$VERIF_ROOT/rm-<場面>`）。E0〜E9 は ① の「origin にあって `BRANCHES` に無いブランチ」の検査を、squash・rebase でマージした PR のブランチ、開いている PR のブランチ、merge commit でマージしたブランチ（対照）、origin で消したブランチ、既にある系列と新しい系列の書き忘れ、系列の名前で始まる PR のブランチ、自分のコミットが無いブランチで通す。R-… は対処: 書き忘れたブランチを足す、系列の名前で始まる開いている PR のブランチを足すと何が起きるか・別の名前で出し直して消した後、origin に無いブランチ（`BRANCHES` を直す・`--single-branch`・push し忘れ）、未コミットの変更（`git stash`・commit・手元の `main` の commit を PR にしてマージする前と後・複数のコミットを 1 つに squash した後に手元の `main` を合わせる）、push していないコミットを捨てる、衝突の後（`--abort` の後・コミットを書き換える・`main` を直す PR・`resume` で拒否された後の 2 つの順）、載せ直した手元のブランチを手で push する、入力待ちの間に動かした後、③' の不合格の後（同じクローンで直す形を含む）、表示された clone 元を PowerShell に貼る（`pwsh` を使う）、誤った force-push を reflog の値で戻す（間に別のメンテナーの push があったときを含む）。R-STALE〜R-S24B は、origin がほかのメンテナーの手順で書き換わった後に、古い手元のブランチから push して拒否されたときの載せ直し（末端・土台・③' の不合格の後（入力待ちの間に別のメンテナーの定常手順が済んだときを含む）・衝突を解いたコミットの元が手元にあるとき）とその対照（このクローンの定常手順で載せ直したブランチ。土台と末端）、入力待ちの間に末端ブランチへ commit したとき、(b) の後の別のクローン、衝突するコミットを書き換える間の別のメンテナーの push、2 人の定常手順が重なったとき（入力待ちの間の操作は coproc で行う）、誤った force-push を戻すときの fetch と lease の値・正しい push をしたメンテナーのクローンで戻す形、衝突するコミットが土台にあるとき。「足す」「直す」は写しのファイルを書き換えて作り、変えた行を diff で表示する。R-S11X は先頭の中断の案内に従う手（変更を捨てる）と従わない手（末端で commit・origin に無いブランチで commit）、R-WT1〜R-WT7 は入力を待つ間にこのクローンのブランチを動かしたとき（末端・土台・`main`・動かさない・`n`・選択肢の版・土台の手順）の、待つ前の値との比べと中断の文の案内 | §5-4、§5-7、§7-2 |
| `control-steady-prev.sh`・`control-middle-prev.sh` | **対照**: 定常手順と中間ブランチの手順の前の形（③ でローカルの全ブランチを `--no-contains` で数える・③ の後で止まらない・先頭の検査が無い） | §5-4 |
| `control-steady-norecheck.sh` | **対照**: `maintain-steady.sh` から、push の直前の検査（入力を待つ前の値との比べと、③ の再検査）を除いた形 | §5-4 |
| `control-steady-resume-refs.sh` | **対照**: `maintain-steady-resume.sh` の `resume` で、① の値を保存せずにリモート追跡ブランチから取り直す形（入力を待つ前の値との比べも持たない） | §5-4 |
| `maintain-controls.sh` | 対照: 兄弟の末端ブランチをそれぞれ `rebase main` すると、`main` を含むかの検査には出ず `merge-base --is-ancestor` で見つかること（2 秒待つ・待たない）。期待値を付けた `--force-with-lease` が拒否されること、値を付けない `--force-with-lease` は直前に fetch していれば他のメンテナーの変更を消すこと | §5-4 |
| `maintain-move-asset.sh` | `main` にある資産を、`main` 以外のブランチ（足場では土台の `java/base`）へ移す順序。ブランチを切った後に `main` から外すと、rebase でブランチからも消える（終了コード 0）。先に `main` から外し、`origin/main` から切って足し直すと残る | §7-2 |
| `migrate-submodule.sh` | §7-3 の移行（submodule の `.claude/` を、gitignore した入れ子クローンへ置き換える）を本文どおりに通し、移行の commit を pull したほかのメンバーで何が起きるか（pull しただけ／手順 1 を自分でも実行した／`.claude/` と `.git/modules/.claude` を消してからランチャー）。参考に、通常のディレクトリの場合の手順 1・2・4 と、それを pull したメンバー（ランチャーが止まった後に `.claude/` を `.claude.old` へ移して起動し直すまで）。ランチャーは `launcher-example.ps1` を 2 行だけ差し替えて使う。`claude` は起動しない | §7-3 |
| `migrate-local-edit.sh` | §7-3 の移行で、手元で `.claude/` を編集していたメンバーが移行の commit を pull したとき（通常のディレクトリから・submodule から）と、`.claude/` がまだ無い新しい作業リポジトリで手順 2・4・5・7 を通したとき。`claude` は起動しない | §7-3 |

足場のブランチ名は、`nestclone-*.sh` では本紙の `main` に当たるものが `master`、`java/base` に当たるものが `java/_base` である。`maintain-*.sh` と `control-*.sh` は本紙と同じ `main`・`java/base` を使う。

`settings.local.json` が `switch` と `reset --hard` の後も残るかは、`nestclone-localfile.sh` が測る（`nestclone-updaterefs.sh` は `reset --hard` だけ、`nestclone-branch.sh` は switch も reset も失敗した場面で、根拠にならない）。
