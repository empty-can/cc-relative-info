---
paths:
  - "**/.claude/agents/*.md"
  - "**/作業計画書*.md"
  - "**/v3_作業計画書*.md"
  - "**/.claude/skills/*/SKILL.md"
---

# Agent 実行時の permission の運用ルール（auto mode が既定の前提）

サブエージェント（以下「担当」。背景で動くものを含む）を起動する作業に関わるファイル（agent の定義・作業計画書・SKILL.md など）を読み書きするときに自動でロードされる path-scoped rule。担当を起動する前の確かめ（§1）、止まったときの復旧（§2）、公式の仕様と既知の落とし穴（§3）を定める。クロスレビュー（skill `.claude/skills/cross-review/`）も、担当の起動前の照合で本ルール §1（台帳の表）と §1.3、止まったときに §2 を参照する。

> **根拠の書き方**: `（L83973）` は公式ドキュメントの断面（CLI 2.1.330 相当）の行番号。断面は、LLMs リポジトリ（`C:\cc-workspace\LLMs`。参照だけ）のコミット `5f51174`（2026-11-21）の `official-llms-txts/code.claude.com/docs/llms-full.txt` と同じ中身（`git -C <LLMs> show 5f51174:official-llms-txts/code.claude.com/docs/llms-full.txt` で取り出せる。作業ツリーの同じファイルは日々更新されるので、行番号は合わなくなる）。「探り」は 2026-11-23 に主担当が実機（同じ版）で確かめたこと。「未確認」と書いたものは断定しない。
>
> **経緯**: 流用元で 2026-05 に、F02-001（背景の担当の Write の権限の設定漏れ）への対処として作った。当時は auto が既定ではなく、実行中の担当で `PostToolUseFailure`・`PermissionRequest` が多発したため、8 種別の事前列挙と、拒否のたびに allow を足す復旧を定めた。F02-001 などの参照先は、このリポジトリには無い。

## 0. 前提: 今の既定と、止まる場合

- 端末・VS Code の新しいセッションの既定は auto（v2.1.283 以降。L83470）。`claude -p` と Agent SDK は Manual（`default`）で始まり、確認の要る呼び出しは拒否される（L83468・L83485）。プロジェクトの `settings.json`・`settings.local.json` に `defaultMode: "auto"` を書いても効かない（L83455）
- 担当は親のモードと permission のルールを受け継ぐ。親が auto・`acceptEdits`・`bypassPermissions` なら、定義の `permissionMode` は無視される（L52844・L52848・L84018）
- ルールの評価は deny → ask → allow の順で、最初に当たったもので決まる。細かい allow が ask・deny より先に来ることはない（L84513・L84515）
- auto で確認が出るか止まるのは、次の 5 つの場合。どれでもない呼び出しは、allow に当たるか、読み取り・作業フォルダの中の編集として自動で承認されるか、分類器が通す（L83968〜L83981）

| # | 場合 | 何が起きるか |
|---|---|---|
| 1 | **ask に当たる** | auto でも確認に落ちる（L83973）。背景の担当の確認はメインのセッションに出て、Esc はその 1 回だけを拒否する（L53172）。長く続く承認を選ぶと、メインを含むセッション全体に効く（L53207） |
| 2 | **protected path への書き込み**（`.claude/`・`.git`・`.vscode` など） | allow があっても分類器に回る（L83969・L84143）。allow では前もって承認されない（L84153）。`.claude/workspace/` が例外に入っていないことは未確認（例外の一覧は「such as」。L84169）。サーバー側の判定（`/status` の `Auto mode server: Enabled`。作業指示者の端末は 2026-11-23 に Enabled）では、作業フォルダの中のふつうの書き込みも判定を待つ（L83977）ので、`.claude/` の下かどうかで待ちの差はほぼ無く、分類器の別の通信も出ない（L84027） |
| 3 | **分類器のブロック** | 理由（`[Destructive or Unwanted Actions]` など）が担当に届く（L83984）。続けて 3 回か合計 20 回で auto が止まり、確認に戻る（L83947）。担当の起動時に依頼の説明を、終了時に作業と報告を審査する（L84017・L84019）。無害な Write が拒まれたことがある（探り） |
| 4 | **deny に当たる** | どのモードでも止まり、確認でも通せない（L83968・L84205） |
| 5 | **定義の hook が止める** | 終了コード 2 で止まり、stderr の文が担当に届く（探り）。hook が `allow` を返しても、deny・ask は先に効く（L85106） |

- ほかに、どのモードでも自動で承認されないもの: `AskUserQuestion`、critical path の `rm`・`rmdir` など（L83416〜L83425）
- `claude -p` では、確認の要るものは全部拒否される（L83485）。auto で起動した `-p` では、分類器のブロックが続いても実行は止まらない（L83956）。プロジェクトの定義の hook は、定義のあるフォルダを信頼の確認で受け入れるまで飛ばされ、`-p` のセッションは信頼に数えない（L53023・L53025）。前もって対話で信頼したフォルダで `-p` のときに hook が動くかは未確認

## 1. 担当を起動する前に見ること

担当を起動する作業を計画するメインのセッションが責任を持つ（担当が自分で吸収できる構造ではないため）。結果は計画書か台帳に残す。

### 1.1 止まり方に沿って見ること

1. **書く先**: 担当が書く先は protected path（§0 の 2）か。auto では分類器が決め、Manual では確認、`-p` では確認の代わりに拒否される（L84141・L84143・L83485 から推した。未確認）。`.claude/` の外に置ける一時ファイル・足場は外に置く
2. **ask**: 担当に、ask に当たるコマンド（今の設定では push・reset・`rm` など）を流させる必要があるか。あるなら担当にやらせず、メインのセッションか作業指示者が流す（§1.3 の (a)）
3. **deny**: deny（秘匿ファイルの Read、`reset --hard` など）に当たる操作が無いか。deny は確認で通せない
4. **担当の定義**: `tools` の各エントリが厳密なツール名か（§3.5）。定義に hook があるなら、依頼文で流させるコマンドが hook の通す形に合うか。定義を足した・書き換えたなら、使えるのは次の応答の区切りから（探り）
5. **入れ子と背景**: 担当に子の担当・fork・背景の Bash を使わせるか。どれも担当の中から起動でき、非同期（探り）。使わせないなら、定義の `tools` から `Agent` を外す（または `disallowedTools` に入れる）か、依頼文で禁じる。fork は高く付く（§3.5）ので担当には使わせない
6. **依頼文**: 分類器は起動時に依頼の説明を審査する（L84017）。目的・書き先・流すコマンドの形を書き、破壊的に見える語だけの依頼にしない
7. **無人（`claude -p`）**: 確認の要るものは全部拒否されるので、§1.2 の 8 種別を総当たりで照合する

### 1.2 権限の事前列挙: 8 種別の照合（台帳の表）

公式のルールの書式（`code.claude.com/docs/en/permissions`）に対応する 8 種別について、(1) 担当が出しうる呼び出しを担当ごとに挙げ、(2) 共有 `.claude/settings.json`・個人 `.claude/settings.local.json` の allow・ask・deny と照らし、(3) 当たるものの対処を §1.3 で決める。出さないと判断した種別は、根拠を書いて飛ばしてよい。対話の auto では、照合の主眼は allow の不足ではなく、deny・ask・protected path との衝突にある。クロスレビューは `check_permissions.py` がこの照合を近似で行い、台帳の表に書く。

| # | 種別 | 見る所 |
|---|---|---|
| 1・2 | **Write・Edit** | 書く先が protected path か。ルールは `Edit(path)` で書く（`Write(path)` のルールは何にも当たらない。L84825〜L84829） |
| 3 | **Bash** | deny・ask に当たる形か（§3.2）。組み込みの読み取りの集合は確認が要らない（L84732） |
| 4 | **PowerShell** | 同上。Bash のルールは PowerShell に効かない（§3.4） |
| 5 | **MCP** | `mcp__<server>__<tool>`。ask に当たるもの、リモートを変えるもの |
| 6 | **WebFetch** | `WebFetch(domain:<ホスト名>)`。ホスト名と照らすので、パスつき（`github.com/anthropics`）は当たらない（L85003）。WebFetch は原則として使わない（§2.2） |
| 7 | **Agent** | 子の担当・fork を使わせるか。入れ子は既定で 3 階層まで（L53317）。`Agent` の allow は auto に入るとき外される（L83998） |
| 8 | **Read の deny** | 既存の deny（`.env*`・`secrets/**`・`~/.aws/credentials`・`~/.ssh/**`）を読みに行かないか |

### 1.3 deny・ask・protected path に当たるときの対処

上から順に検討する。広い allow を足すのは最後にする。

| 選択肢 | 使いどころ |
|---|---|
| **(a) 担当にやらせない** | push・reset・削除など ask・deny の操作。メインのセッションか作業指示者が流す |
| **(b) 形を変える** | スクリプトファイルに書いて 1 コマンドで流す／定義の hook の通す形に合わせる／書く先を protected path の外にする |
| **(c) 確認が出る前提で進める** | ask が避けられないとき。背景の担当の確認はメインに出る（L53172）。作業指示者に前もって伝える |
| **(d) 狭い allow を足す** | 読み取り系など。§2.2 に従う。auto では狭い allow が分類器を飛ばす（§3.3）ので、書き込み系は範囲を絞る |
| **(e) 定義の hook** | 引数の水準で絞る・止める。担当の中だけで発火する（§3.5）。deny・ask を覆す目的には使えない（L85106） |
| **(f) 並列度を下げる** | 緊急時だけ。担当を 1 体ずつ動かし、確認にその場で答える。対話の端末で担当の終わりを待つには fork mode を切る（`CLAUDE_CODE_FORK_SUBAGENT=0`。L53179・L53185） |

## 2. 止まったときの復旧

事前の確かめには限界があり、まれな事象は実行時に初めて出る。止まったら次の順で扱う。

### 2.1 手順

1. **何で止まったかを見分ける**（§0 の 5 つ）: 担当に届いた理由の文、hook の stderr、`/permissions` の **Recently blocked**（分類器のブロック。L83946）を見る
2. **止まった担当・箇所だけをやり直す**。ほかの担当は起動し直さない
3. **場合ごとの手を選ぶ**:
   - 分類器: 同じ形で繰り返さない（3 回続くと確認に戻る。L83947）。スクリプトの docstring か依頼文に目的を書いて出し直す（探りで通った）。**Recently blocked** から承認して、やり直させることもできる（L83946）
   - 定義の hook: stderr の「直し方」に合わせて形を変える
   - ask: 確認を作業指示者に回す。要らない操作なら担当の作業から外す（§1.3 の (a)）
   - deny: 担当では通せない。決まりで禁じた操作なので、やり方を変えるか、作業指示者に伺う
   - protected path: 書く先を変える。auto では分類器のブロックとして扱う（上の分類器の行）。確認の出るモードでは作業指示者が承認でき、`.claude/` にはセッション限りの承認の選択肢がある（L84153・L84155）
4. **やり直しは、依頼文を直して新しい担当に渡すのを基本にする**（同じ担当の再開で作業を積み増さない。`chunked-generation.md`）。小さな直しなら SendMessage で再開してよい
5. **allow を足すのは最後の手**。足すなら §2.2 に従い、書き込み系は作業指示者に確かめる
6. 再び起きうるものは、条件（コマンドの形・引数・モード・並列度）を具体的にして §3.6 に足す

### 2.2 settings に置くルールの基準

共有 `.claude/settings.json`（全員）と個人 `.claude/settings.local.json`（各自・未追跡）の今の置き方を、この表の実態とする（設定に合わせる。2026-11-23 の決定 P13）。

| 種類 | 置き場所 | 扱い |
|---|---|---|
| 読み取り系の Bash・MCP の読み取りと検索 | 共有か個人 | allow してよい |
| WebFetch のドメイン | 共有（Anthropic の文書のドメインだけ） | **原則として足さない**。WebFetch は、Anthropic が認めた一部のドメインを除き、取得した内容を小さなモデルで要約・変換するので情報が欠ける（作業指示者の方針・2026-11-23）。GitHub のリポジトリは事前に clone し、リポジトリに無い wiki・issue などは GitHub の MCP で取る |
| 作業フォルダの Edit（`.claude/` の外） | 共有か個人 | allow してよい。`.claude/` の下は allow しても前もって承認されない（L84153） |
| 書き込み系の Bash の限定の allow（`git add *`・`git commit *` など） | 個人だけ | 置いてよい。auto では分類器を飛ばす（§3.3）ので、作業を捨てる形（`git checkout -- .`・`git clean -f`・`git stash drop` など）は個人の ask で止める（P5） |
| push・reset・`rm`・`python -c` など、戻せない操作・外へ出る操作・決まりで避ける形 | push は共有（P2）、ほかは個人 | ask |
| 決まりで禁じる操作（`reset --hard`、秘匿ファイルの Read など） | 共有 | deny |
| `Bash`・`PowerShell` 丸ごとの allow | 個人（残す。P1） | auto では外れる。帰結は §3.4 |

## 3. 落とし穴（公式の仕様の要点と既知の挙動）

原典は §4 の公式ドキュメント。版が上がると変わるので、設計の根拠にするときは断面の行を読み直す。

### 3.1 permission modes（`code.claude.com/docs/en/permission-modes`）

| モード | 要点 | protected path への書き込み（L84139〜L84145） |
|---|---|---|
| `default`（表示名 **Manual**） | 確認の要るものを毎回確認する。`-p` では確認の代わりに拒否（L83485） | 確認 |
| `acceptEdits` | 作業フォルダの中の編集と一般の FS コマンドを自動で承認 | 確認 |
| `plan` | 読むだけ。auto が使えるときは分類器がシェルのコマンドを審査する（L83682） | 条件による |
| `auto` | 当たるルールが無いものを分類器が審査する（§0） | 分類器 |
| `dontAsk` | 前もって allow したもの以外は拒否 | 拒否 |
| `bypassPermissions` | 確認をすべて飛ばす。隔離された環境のためのもの | 通る |

### 3.2 ルールの当たり方（`code.claude.com/docs/en/permissions`）

- **書いた形にしか当たらない**: `Bash(git push *)` は `git -C . push`・`git -c push.default=current push` に当たらない。`/usr/bin/curl`・`sh -c '…'` も同じ。セキュリティの境界ではない（L84716〜L84726）。**スクリプトファイルの中や、Python などの子プロセスはルールでは見えない**（L84823）。守りを固くするなら PreToolUse の hook（L84728）
- **複合のコマンド**: deny・ask は部分のどれかに当たれば効き、auto でも確認が出る（L84689）。allow で通すには、すべての部分が allow か読み取りの集合に当たる必要がある（L84687）
- **書式**: `Bash` と `Bash(*)` は同じ（L84562）。`Bash(x:*)` は `Bash(x *)` と同じで、末尾にだけ書ける（L84655・L84657）。末尾の ` *` は、それが唯一の `*` なら裸のコマンドにも当たる（L84652）
- **ラッパー**: `timeout`・`time`・`nice`・`nohup`・`stdbuf`・`command`・`builtin`・`noglob`・フラグの無い `xargs` は外してから照らす（L84697・L84701）。`npx`・`docker exec`・`devbox run` などは外さないので、中のコマンドまで書く（L84703）。`watch`・`setsid`・`ionice`・`flock` と、`find` の `-exec`・`-delete` は前置きのルールでは承認できない（L84707〜L84712）
- **先頭の環境変数**: allow は決まった安全な変数以外の代入の後ろには当たらない。deny・ask はどの代入の後ろにも当たる（L84699）
- **読み取りの集合**: `ls`・`cat`・`echo`・`pwd`・`head`・`tail`・`grep`・`find`・`wc`・`which`・`diff`・`stat`・`du`・`cd`・読み取りの `git` は、どのモードでも確認が要らない。auto では分類器の審査を待つことがある（L84732）。ただし `cd` で別のフォルダに入ってから `git` を流す形は確認が出る（L84749）
- **Read・Edit のパス**: `//path` は絶対パス、`~/path` はホーム、`/path` は設定ファイルの元からの相対（プロジェクトの設定ではルート。絶対パスではない）、`path`・`./path` はカレント。Windows のパスは POSIX の形（`C:\Users\alice` → `/c/Users/alice`）で照らす（L84838〜L84843・L84867）。Read・Edit の deny は、組み込みのファイルのツールと、解析できる Bash のファイルのコマンド（`cat` など）とリダイレクトに効くが、スクリプトの中の読み書きには効かない（L84821・L84823）

### 3.3 auto mode 特有のこと

- **入るときに外される広い allow**: `Bash(*)`・`PowerShell(*)`（丸ごとの `Bash` も同じ）、`Bash(python*)` のようなインタープリタ、ラッパー＋ワイルドカード、ワイルドカードで始まる形、パッケージマネージャの run、`Agent`・`Monitor` の allow など。auto を出ると戻る（L83990〜L84001）
- **狭い allow は分類器を飛ばす**: 外されない allow に当たったコマンドは分類器を通らないので、前置きが想定していない破壊的な引数も素通りする（L98808）。例: `Bash(git checkout *)` は `git checkout -- .` を通す。すべてのシェルのコマンドを分類器に回す `autoMode.classifyAllShell` は、ユーザーか managed の設定にだけ書ける（L98810）
- **分類器が見るもの**: ユーザーの発言・読み取り以外のツールの呼び出し・CLAUDE.md。ツールの結果は見ない（L84007）
- **外されるかどうかの境目**（`Bash(git -C:*)`・`Bash(claude plugin *)`・`Bash(python LLMs/scripts/*)` などが外されるか）は、例から推した範囲を出ず未確認（`/permissions` で確かめる必要がある）

### 3.4 Windows とシェルのツール

- **PowerShell ツールに Bash のルールは効かない**。PowerShell には `PowerShell(...)` のルールを別に書く（L106986）
- **Windows＋Git Bash で、Bash の deny（範囲つきでも）があると、PowerShell ツールが黙って切れる**。PowerShell の範囲つきのルールを置くか、`CLAUDE_CODE_USE_POWERSHELL_TOOL=1` で残せる（L106984〜L106993）
- **`Bash`・`PowerShell` 丸ごとの allow の帰結**: Manual では deny・ask に当たらないシェルのコマンドがすべて確認なしに通り、ほかの狭い Bash の allow はあっても無くても同じになる（L84562 から。見直しの報告 §2.5）。auto では入るときに外れ、狭い allow だけが残る（L83992）。`claude -p` でも個人のファイルの丸ごとの allow が効き、`--allowedTools` で絞ったつもりでもシェルは何でも通る（推測。見直しの報告 §2.5）
- Bash の sandbox は macOS・Linux・WSL2 のもので（L83439）、ネイティブの Windows では OS の層の守りに頼れない（推測）

### 3.5 サブエージェント（`code.claude.com/docs/en/sub-agents`）

- **継承**: §0 のとおり。auto では、担当の各呼び出しを親と同じ順と規則で判定する（L84018）
- **`tools` に引数つきの書き方はできない**: `Bash(git status:*)` は黙って捨てられ、全部が解決できないときだけ起動を拒む（2026-08-29 に確かめ。L30490〜L30496）。`Agent(<型>)` の型の一覧は `claude --agent` のメインでだけ効き、担当の定義では括弧の中が無視される（L52781）。引数の水準の絞り込みは deny・ask か hook で行う
- **背景の担当の確認**: メインのセッションに、どの担当の要求かを示して出る（L53172）。古い版の「起動前に一括で承認し、未承認は拒否」の前提で設計しない
- **定義の追加・書き換え**: 置いた応答の中では使えず、次の応答の区切りから使える（探り）
- **定義の hook**（frontmatter の `hooks`）: その担当の中だけで発火し、メインのセッションでは発火しない（探り・L53017）。`command: python`＋`args` の形で動き、`${CLAUDE_PROJECT_DIR}` は置換される。入力には `agent_id`・`agent_type`（定義の `name`）・`cwd`・`permission_mode`・`tool_name`・`tool_input` などがある（探り）。プロジェクトの定義の hook は、フォルダの信頼が要る（L53023〜L53025）。plugin の担当では `hooks`・`permissionMode`・`mcpServers` は無視される（L52466）
- **`SubagentStart` の hook**（設定ファイル）: `hookSpecificOutput.additionalContext` を返すと、すべての種類の担当の文脈の先頭に足される（L72594）。再起動なしで反映され、再開しても二重にならず、10,000 字まで（探り）。担当に共通の決まりを渡すのに使う
- **path-scoped rule**: 担当が該当のファイルを Read したときにロードされる。セッションの途中で足した `paths` の無い rule は、そのセッションで起動した担当には入っていなかった（探り）
- **入れ子と fork**: 担当は既定でメインから 3 階層下まで担当を起動できる（L53317。`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`）。fork mode は既定で有効（L53539）。同じ流し方のコストは、専用の定義（haiku・ツール 2 つ）約 9,400 トークン、汎用の haiku 約 54,600、fork 約 364,900（探り）。担当に fork を使わせない

### 3.6 既知の落とし穴（このリポジトリと流用元での経験）

- **`afea8b8` の重複の疑い**（流用元でのこと。このリポジトリの共有の allow には無い）: 読み取りの集合に入る `cd`・`wc`・`git show` などで確認が出たため、2026-05-06 に allow に足した。確認が出た条件は特定していない。`cd` で別のフォルダに入ってから `git` を流す形（L84749）や、解析できない複合のコマンド（L84745）が候補だが未確認
- **`tools: Bash(git status:*)` の黙った破棄**: `agents/code-reviewer.md` が、Bash を持たないまま起動していた（2026-08-29 に直した）
- **分類器の誤ったブロック**: 元のファイルを写すだけのスクリプトの Write が `[Destructive or Unwanted Actions]` で拒まれ、目的を docstring に書いて書き直すと通った（2026-11-23）
- **`.claude/` の下への Edit の allow は効かない**: 個人の設定にある `Edit(.claude/**)` などは、protected path の確認を前もって消さない（L84153）
- **`Write(path)` のルールは何にも当たらない**: `Edit(path)` で書く（L84825〜L84829）
- **`bypassPermissions` の盲点**: protected path への書き込みも通る（L84145）。本リポジトリの方針（deny を明示する）と合わないので使わない

## 4. 参照

- 関連する rule・skill: `.claude/rules/md-self-check.md`（`.md` の反復セルフチェック。チェックリストは `.claude/rule-assets/md-self-check/checklist.md`）／`.claude/rules/chunked-generation.md`（生成と文脈を小分けにする）／`.claude/skills/cross-review/SKILL.md`（クロスレビューの進行。担当の起動前に本ルール §1.3 を参照）
- 公式ドキュメント: `code.claude.com/docs/en/permissions` / `code.claude.com/docs/en/permission-modes` / `code.claude.com/docs/en/sub-agents` / `code.claude.com/docs/en/hooks`
- 既存の settings: `.claude/settings.json`（チーム共有）/ `.claude/settings.local.json`（個人ローカル、`.gitignore` 対象）
- 設定の見直しの記録（2026-11-23）: 作業 `202611-01_write-report-v3` の `10_interim-deliverables\permissionsの見直し.md`

> **`paths:` の調整方針**: 今は「担当を起動する計画段階のファイル」「agent の定義」「SKILL.md」「作業計画書」を対象にする。(a) 報告書の執筆で本ルールが要る作業が出たら `**/reports/**/*.md` などの追加を検討する、(b) 要らない場面でのロードが目立ったら絞る、(c) `md-self-check.md`（`**/*.md`）と重なる領域を整理する。

## 変更履歴

- 2026-05-07: 初版作成（Claude Opus 4.7、F02-001 §5.2.2 採用案の中核実装。案 1 + 案 2 + 案 5 を統合配置）
- 2026-08-29: 公式ドキュメント最新版（2026-08-28 取込）との照合により失効記述を更新（判断事項 D-9 対応）。(1) §3.1 permission modes を全面改訂 —— **auto が Pro/Max/Team の既定開始モード**、`default` の表示名は **Manual**、`plan` の classifier 連動、`defaultMode: "auto"` が project settings では効かない点、どのモードでも自動承認されない集合を追記。(2) §1.1 #7 に **subagent の入れ子起動（既定 3 階層）** を追記。(3) §1.3 (b) の「Pro 非適用」を削除。(4) §3.5 に **`tools` フィールドは引数スコープを解釈しない**（無言破棄）を追記し、**background subagent の permission 挙動**を v2.1.186 以降（tool call 時点でメインセッションに prompt）へ更新。(5) §3.6 の落とし穴 2 件を差し替え
- 2026-11-23: auto mode が既定の前提に全面改訂（断面 CLI 2.1.330 相当と、同日の探り）。§0 に止まる 5 つの場合を新設し、§1 を止まり方に沿った確かめに組み直し（8 種別の表は台帳との対応のため短くして残す）、§2 を広い allow を足さない復旧に改め、§2.2 を設定の実態（決定 P13）に合わせ、§3 の古い記述を直して足りない落とし穴を足した。経緯の記述を縮めた
