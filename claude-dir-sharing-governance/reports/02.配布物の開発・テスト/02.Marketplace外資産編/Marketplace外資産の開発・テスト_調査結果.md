# Marketplace 外資産（CLAUDE.md / rules / settings 等）の開発・テスト — 調査結果（v1.6）

> - **想定読者**: Marketplace（層2）で配れない config 資産（`CLAUDE.md` / `.claude/rules/` / `settings.json` / skills / agents）を、config・テンプレートリポジトリ（層1）や managed settings（層3）でチームへ配るチームの開発担当者。「これら資産をどこで・どう開発・テストするか」を知りたい読み手。
> - **位置づけ**: 「ポータブルな `.claude/` のチーム共有・統制」調査の **タスク02（配布物の開発・テスト）第2フェーズ**。第1フェーズ（[Plugin・Marketplace 編](../01.Plugin・Marketplace編/Plugin・Marketplace配布物の開発・テスト_調査結果.md)）の続編で、**層2 で運べない資産**側を扱う。配布メカニズム自体は [v1.2 §解決案 案A/C/D](../../01.配布・統制方針調査/結論・構成案_ポータブルな.claude共有_v1.2.md) が確定済みで、本書はその**開発・テスト方法**に絞る。
> - **作成日**: 2026-06-21
> - **根拠ドキュメント**: Claude Code 公式ドキュメント（ローカル DL 版 `llms-full.txt`）。主担当ページは `docs/memory` / `docs/debug-your-config` / `docs/settings` / `docs/permissions` / `docs/permission-modes` / `docs/server-managed-settings` / `docs/env-vars`。出典は**ページ名＋セクション**を主アンカーとする（行番号は snapshot 依存）。原文照合は `cc-docs-config-scopes-expert` と `cc-docs-permissions-sandbox-expert`（公式 docs 原文忠実 agent）による。

---

<a id="summary"></a>

## エグゼクティブサマリ（結論の先出し）

**問い**: Marketplace で配れない資産（`CLAUDE.md` / `rules/` / `settings.json` / skills / agents）を、config・テンプレートリポジトリで公開する前提で、どこで・どう開発・テストするのが標準/推奨か。

**結論**: **plugin と違い、これら資産には専用の開発ロード機構（`--plugin-dir` 相当）が無い。** config 資産は Claude Code をそのディレクトリで起動すれば**ネイティブにロードされる**（plugin のようなキャッシュコピーの間接層が無い）。したがって——

- **開発** = config・テンプレートリポジトリ（ローカル）に資産を**素直に書く**だけ。「plugin 化」のような変換工程は無い。
- **テスト** = 2通り。
  - **(A) ネイティブ確認（スモーク）**: `<Share>`（開発中は `<Dev>`）で Claude Code を起動し、`/memory`・`/context`・`/status`・`/doctor` で「**ロードされたか・発火するか**」を確認する。ただし `<Share>` には操作対象の実ファイルが無いため**機能の正否までは検証できない**（`--add-dir` で結合できない `output-styles`/`hooks` の唯一の検証手段ではある。`commands` は **v2.1.235 版(2026-08-19)** から `--add-dir` で結合可能になったためこのグループから外れた／後述）。
  - **(B) 結合テスト（公開前の正式機能検証の本命）**: 作業リポ `<Other>` と**結合**し、実コード・ファイルに対して資産を働かせる。手段は資産で割れる——skills/agents は `--add-dir`、`CLAUDE.md`/`rules` は `--add-dir` ＋環境変数、`settings.json` は `--settings`（[§2](#combine)）。**`<Other>` 自身の `.claude` も混ざる**ため、`/memory`・`/skills`・`/context` で何がどこから読まれたか目視する（**v2.1.198 以降 `/agents` は subagent 一覧を表示しなくなった**ため、custom subagents をロード元パス付きで表示する `/context` が代わりの目視手段になる。混入を断つには `.claude` の無い空作業 dir から `--add-dir`＝クリーン隔離 [§4](#clean)）。
- **隔離** = 自分の通常設定の影響を切るには `CLAUDE_CONFIG_DIR` を空ディレクトリに向けた**クリーンセッション**で検証する（[§4](#clean)）。

「公開の配布用リポジトリと開発・テストリポジトリは別（後者はローカル）／テストは `--add-dir` 等で結合して実施」という当初の作業仮説は、**skills・subagents・CLAUDE.md・rules については正しい**。一方 `settings.json`（permissions/hooks 等）は `--add-dir` では結合されず `--settings` という別経路になる点が、plugin 編との最大の差である。

---

## 問い・スコープ

- **問い**: 層2 で配れない config 資産を、config/テンプレートリポジトリ（層1 中心）で開発・テストする標準/推奨手順は何か。作業リポと結合してテストする方法、ロード・適用を検証する方法。
- **スコープ内**: 層1（config/テンプレートリポ）の開発・テスト方法。結合手段（`--add-dir`/環境変数/`--settings`）、ロード検証手段、クリーン隔離テスト、反映タイミング、テスト時の落とし穴。層3（managed settings）の開発・検証は[§7](#layer3)で**注記**として扱う。
- **スコープ外**: 各資産が**どのチャネルで配布できるか**の判断（v1.2 マトリクスに委譲）。層3 の本格的な構築手順（v1.2 案D）。

---

<a id="overview"></a>

## 1. 開発・テストの全体像（plugin との対比）

| 観点 | plugin（[第1フェーズ](../01.Plugin・Marketplace編/Plugin・Marketplace配布物の開発・テスト_調査結果.md)） | config 資産（本書） |
|---|---|---|
| ロード方式 | install 時に `~/.claude/plugins/cache` へ**コピー**して使う（間接層あり） | ディレクトリを開けば `.claude/` から**ネイティブにロード**（間接層なし） |
| 専用の開発ロード機構 | **あり**（`claude --plugin-dir ./my-plugin`） | **無い**（リポで起動すればそのまま有効） |
| 「化ける」工程 | standalone → **plugin 化**（`plugin.json` 付与） | 無い（書いたものがそのまま資産） |
| 公開前バリデーション | `claude plugin validate` | **専用 validate は無い**。`/doctor` が設定ファイルの schema/無効キーを検査 |
| 反映 | `/reload-plugins` | settings はファイル監視で即時／skills はホットリロード（[§5](#timing)） |

→ config 資産の開発・テストは、**「書く → 起動 → ロードされたか・効いているかを確認」**という素直なループ。専用ツールが無いぶん、**検証コマンド（[§3](#verify)）で『実際にロード・適用されたか』を確かめること**が要になる。

---

<a id="combine"></a>

## 2. テスト時の結合手段（`<Share>` ↔ `<Other>`）

別ディレクトリ（配布ペイロード `<Share>`）の `.claude/` 資産を作業リポジトリ `<Other>` と結合してテストする手段は、**資産種別で割れる**（出典: `docs/permissions` の「Additional directories grant file access, not configuration」表、`docs/settings`）。

| 資産 | 結合手段 | 備考 |
|---|---|---|
| `skills/`（`.claude/skills/`） | **`--add-dir <Share>`** | 自動ロード・**live reload**あり |
| `agents/`（subagents） | **`--add-dir <Share>`** | 自動ロード（**v2.1.178+ で対応・v2.1.165 までは非ロード**。v1.2 報告書 errata 参照） |
| `settings.json` / `settings.local.json` の `enabledPlugins` / `extraKnownMarketplaces` | **`--add-dir <Share>`** | **この2キーのみ**読まれる |
| `CLAUDE.md` / `.claude/rules/` / `CLAUDE.local.md` | **`--add-dir <Share>` ＋ `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`** | 環境変数が `1` の時のみ。`CLAUDE.local.md` は `local` setting source（既定有効）も条件 |
| `settings.json`（permissions / hooks / env 等のその他キー） | **`--settings <Share>/.claude/settings.json`** | `--add-dir` では読まれない。command-line precedence でマージ（[§優先順位](#precedence)） |
| `commands/`（`.claude/commands/`） | **`--add-dir <Share>`** | **v2.1.235 版(2026-08-19) で新規に例外ロード対象へ追加**（live reload なし・再起動が要る）。`<Share>` と `<Other>` の両方に同名コマンドがある場合は **`<Other>`（参照元プロジェクト）側が優先**される |
| `output-styles/` / `hooks`（settings 内） | **結合不可** | `--add-dir` 先からはロードされない。物理配置か `<Share>` で直接起動する |

> **正本**: 版依存の事実（subagents の版境界・`settings.local.json` を含む2キー例外）は [v1.2 付録B『`--add-dir` 例外ロード一覧（正本）』](../../01.配布・統制方針調査/結論・構成案_ポータブルな.claude共有_v1.2.md#adddir-exceptions) を正とする（本表は運用早見）。

> **`--add-dir` フラグ／`/add-dir` コマンド限定**。`permissions.additionalDirectories` 設定経由では**ファイルアクセス付与のみ**で、上記の自動ロードは一切起きない（`docs/permissions`）。
>
> **plugin 編との最大差**: plugin のテストは `--plugin-dir` 一本で完結したが、config 資産は **skills/agents/commands（`--add-dir`）・CLAUDE.md/rules（`--add-dir`＋環境変数）・settings.json（`--settings`）の3経路**を使い分ける。`output-styles`/`hooks` は結合手段が無く、テストするなら `<Share>` で直接起動するのが確実。

<a id="adddir-memory-range"></a>

### `--add-dir` でロードされる memory ファイルの正確な範囲（共有境界の設計）

`--add-dir <Share>` ＋ `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` のとき、`<Share>` から**まとめてロードされる memory ファイル**（`docs/memory`「Load from additional directories」原文: *"This loads `CLAUDE.md`, `.claude/CLAUDE.md`, `.claude/rules/*.md`, and `CLAUDE.local.md` from the additional directory"*）:

- `<Share>/CLAUDE.md`（**ルート直下**）
- `<Share>/.claude/CLAUDE.md`
- `<Share>/.claude/rules/*.md`
- `<Share>/CLAUDE.local.md`（**ルート直下**。`--setting-sources` から `local` を除外するとスキップ・既定は有効）

**重要な性質**:

- **環境変数は all-or-nothing**: ON なら上記すべてロード、OFF なら上記すべて非ロード。**ルート直下か `.claude/` 配下かでロード可否は変わらない**（`<Share>/CLAUDE.md` と `<Share>/.claude/CLAUDE.md` は一緒に読まれる）。→ 「ルートは固有・`.claude/` は共通」のような**置き分けでは共有可否を制御できない**。
- **共有境界は `--add-dir` の対象範囲で制御する**: 参照側に読ませたくないファイルは (a) memory ファイル以外（`README.md` 等）へ逃がす、または (b) `--add-dir` 対象フォルダの外（または対象をサブフォルダに限定）へ出す。
- ⚠️ **`CLAUDE.local.md` の落とし穴**: gitignore 対象＝非公開の個人ファイルだが、`<Share>` にローカルで存在すると（環境変数 ON 時）**参照側セッションにロードされる**。配布 clone に個人 `CLAUDE.local.md` を残さないこと。

> **本調査での設計判断（採用）**: 配布 clone（`<Share>`）は**共有ペイロード専用**とし、ルート直下に `README.md`（リポ固有の運用メモ・**memory ファイルでないため自動ロードされない**）、共通ルールを `<Share>/CLAUDE.md`（＝`<Share>/.claude/CLAUDE.md` と等価）＋`<Share>/.claude/rules/` に置く。これにより `--add-dir <Share>`＋環境変数で**共通ルールだけ**が参照側へ届き、リポ固有情報は README に隔離される（[§推奨リポジトリ構成](#topology)）。

<a id="precedence"></a>

### `--settings` の優先順位（settings.json を結合テストする時）

スコープ優先（高い順）: **managed > command-line（`--settings`） > local（`settings.local.json`） > project（`settings.json`） > user（`~/.claude/settings.json`）**（`docs/settings`）。`--settings` で渡した値は他レイヤと**同じマージ規則**で結合し、同一キーを上書き、未指定キーは下位レイヤの値を残す。permission ルールの衝突は **deny → ask → allow** の順で評価され、**どのスコープであれ deny が最優先**（`docs/permissions`）。

> **`settings.local.json` は共有不可・`--settings` の対象は `settings.json`**: `settings.local.json` は **project 個人・gitignore 専用**（`docs/settings` で "Project only / personal overrides out of git"）で、`--add-dir` では原則読まれない（**例外: `enabledPlugins`/`extraKnownMarketplaces` の2キーのみ `settings.json` 同様にロードされる**・[§2 表](#combine)）。他リポへ名指し `--settings` で食わせるのは本来の用途に反する。`settings` の正しい使い分け: **共有＝`settings.json`（`--settings <Share>/.claude/settings.json`）／マシン全リポの個人既定＝`~/.claude/settings.json`（user スコープ。`~/.claude/settings.local.json` は存在しない）／特定リポの個人 override＝`<project>/.claude/settings.local.json`**。

---

<a id="verify"></a>

## 3. ロード・適用の検証手段（plugin の validate/--debug に相当）

config 資産が**実際にロード・適用されたか**を確認する公式手段。これが本書の中核（専用 dev-load ツールが無いぶん、検証で担保する）。

| 手段 | 何を確認できるか | 出典ページ |
|---|---|---|
| **`/memory`**（⚠v2.1.235 版(2026-08-19)で仕様変更） | **「ロード済み一覧」ではなく「置き場所一覧」**——user/project スコープの CLAUDE.md・CLAUDE.local.md・rules 等の所在を、**未作成のファイルも含めて**列挙し編集導線を提供する。auto memory のトグルも。**実際にセッションへロードされたかの確認は `/context` が正** | `docs/memory` / `docs/debug-your-config` |
| **`/context`** | コンテキストウィンドウの内訳（system prompt・system tools・MCP tools・**custom subagents（ロード元パス付き）**・memory files・skills・会話）。**CLAUDE.md/rules/skill description が"そもそも入っているか"を最初に確認**するのに最適。**ロードされた subagent とその読込元パスの確認手段としても使う**（`/agents` の代替・後述） | `docs/debug-your-config` |
| **`/status`**（Status タブ） | `Setting sources` 行＝ロードされた settings レイヤ一覧（`User settings`・`Project local settings` 等）。managed は配信チャネルを括弧表示（`(remote)`/`(plist)`/`(HKLM)`/`(HKCU)`/`(file)`）。**設定ファイルのエラーも報告**。※どのレイヤが個別キーを供給したかは出ない | `docs/settings` |
| **`/doctor`**（`claude doctor` CLI も） | 設定ファイルを**バリデーション**し、無効キー・schema エラーを表面化。検出結果を提示したうえで、修正内容を確認してから適用（**Before v2.1.205 は `f` キーで Claude に送信する方式だったが、現行は廃止済み**）。あわせて**同一ディレクトリ内の同名 subagent 定義**を検出し、リネーム/削除を提案する | `docs/debug-your-config` / `docs/setup` / `docs/sub-agents` |
| **`/skills`** | 利用可能 skill 一覧（project/user/plugin ソース）。バッジで `user-only` 等を識別。`t` でトークン数ソート | `docs/debug-your-config` / `docs/commands` |
| **`/agents`**（⚠v2.1.198+で仕様変更） | **v2.1.197 以前**は構成済み subagent 一覧と設定を表示。**v2.1.198 以降は一覧を表示せず**、`.claude/agents/` を直接編集するよう促すリマインダーのみを表示する。**ロード済み subagent と読込元パスの確認は `/context`（custom subagents をソース付きで表示）を使う** | `docs/debug-your-config` / `docs/sub-agents` |
| **`InstructionsLoaded` hook** | **どの指示ファイルが・いつ・なぜロードされたかをログ**。path-specific rules やサブディレクトリの遅延ロード `CLAUDE.md` のデバッグに有用 | `docs/memory` / `docs/hooks` |
| **`ConfigChange` hook** | settings 再読込のたびに発火（変更検出のフック） | `docs/settings` / `docs/hooks` |

> **スコープ可視性の限界**: `/memory` は置き場所を一覧するがスコープ"ラベル"は明示されない（パスから間接判断）。`/status` の `Setting sources` は"どのレイヤが読まれたか"は示すが"どのキーをどのレイヤが供給したか"は示さない。個別キーの出所を厳密に追うなら `InstructionsLoaded`/`ConfigChange` hook でログを取る。

---

<a id="clean"></a>

## 4. クリーン設定での隔離テスト

> **一次切り分け（v2.1.235 版(2026-08-19) で新設）**: 新設の `claude --safe-mode`（全カスタマイズ無効化・managed settings は適用継続）を先に試し、`<Share>` 側の問題を疑う場合のみ本節の `CLAUDE_CONFIG_DIR` 手順に進むと検証が速い。詳細は本節末尾を参照。

自分の通常の `~/.claude` / project 設定の影響を切り離して「**配る資産だけ**」を検証する公式手順（`docs/debug-your-config`）:

```bash
cd /tmp && CLAUDE_CONFIG_DIR=/tmp/claude-clean claude
```

- `CLAUDE_CONFIG_DIR` を**空ディレクトリ**に向けると `~/.claude` 配下を丸ごとバイパス。さらに `.claude`/`.mcp.json`/`CLAUDE.md` の無いディレクトリから起動すれば project 設定もスキップ → user も project も無い素のセッション（hooks/MCP/plugins/memory なし）。
- **バイセクト**: クリーンセッションで問題が消えるなら原因は実 `~/.claude` か project 側。ファイルを1つずつ temp にコピー（または project から起動）して切り分ける。
- **注意点**: (1) **managed settings は system パスにあるため、クリーンセッションでも適用され続ける**。(2) Linux/Windows は認証情報が config dir 配下のため**再ログインが要る**。(3) macOS は Keychain 保管で引き継がれる。

> 配布する `<Share>` の検証は、**クリーンな `CLAUDE_CONFIG_DIR` ＋ `<Share>` から起動（または `--add-dir`/`--settings` で結合）**すると、「自分の個人設定が混ざって誤って動いて見える」事故を避けられる。手順書 `scripts/clean-test-env.{sh,ps1}` が自動化する。

### `--safe-mode` による一次切り分け（一段構え目）

`claude --safe-mode` は、CLAUDE.md・skills・plugins・hooks・MCP サーバー・custom commands/agents・output styles・workflows・custom themes・custom keybindings・status line/file-suggestion コマンド・LSP サーバー・auto memory を**すべて無効化**して起動する（認証・モデル選択・組み込みツール・permissions は通常通り動作）。**managed settings のポリシー（managed hooks・status line 等）は適用され続け**、managed plugins/skills/CLAUDE.md/MCP のみ無効化される。

- `--safe-mode` は「セッションの全カスタマイズを切る」だけで、**`<Other>` や `~/.claude` からの完全分離はしない**（`CLAUDE_CONFIG_DIR` のように別ディレクトリへ切り替えるわけではなく、同一セッション内でロードを止めるだけ）。したがって `<Share>` 由来かどうかの**手早い一次切り分け**には向くが、`CLAUDE_CONFIG_DIR` クリーンセッションの完全な代替にはならない。
- 二段構えの運用: **まず `--safe-mode`** で「何らかのカスタマイズが悪さをしていないか」を素早く確認し、**それでも切り分かなければ `CLAUDE_CONFIG_DIR` の完全クリーンセッション**（本節の手順）に進む。
- 出典: `docs/cli-reference`「`--safe-mode`」行 ／ `docs/debug-your-config`「Test against a clean configuration」節（**v2.1.235 版(2026-08-19)**）。

---

<a id="timing"></a>

## 5. 反映タイミング（編集 → 反映）

| 対象 | 反映 | 出典 |
|---|---|---|
| `settings.json`（`permissions`/`hooks`/`apiKeyHelper` 等） | **ファイル監視で即時**（brief file-stability delay あり・再起動不要）。`ConfigChange` hook が発火 | `docs/settings` / `docs/debug-your-config` |
| `model` | 起動時に一度読む → 次回起動で反映（セッション中は `/model`） | `docs/settings` |
| `outputStyle` | system prompt の一部 → `/clear` か再起動で再構築 | `docs/settings` |
| 環境変数 | **起動時のみ**読む → 次回 `claude` 起動で反映 | `docs/env-vars` |
| skills（`SKILL.md`） | **ホットリロード**（即時）。`/reload-skills` で強制再スキャンも | `docs/changelog` / `docs/commands` |

---

<a id="pitfalls"></a>

## 6. テスト時の落とし穴

config 資産をテストする際、**「リポに commit したのに効かない」**を生む公式仕様:

- **trust dialog（workspace trust）**: clone/テンプレ展開した config は、**フォルダを trust 承認するまでフル有効化されない**。`autoMemoryDirectory` は trust 後のみ honored、`extraKnownMarketplaces` の install prompt も trust 後に初めて出る（`strictKnownMarketplaces` は trust 前から強制という違いも）。テストは**trust 承認の前後**で挙動が変わる点に注意（`docs/settings`）。
- **project/local では無視される security 系キー**（commit しても効かない＝テストでも効かない）:
  - `defaultMode: "auto"` … project/local settings では無視（v2.1.142+。リポが自分に auto mode を付与する攻撃防止）。効かせるなら `~/.claude/settings.json`
  - `skipDangerousModePermissionPrompt` … project settings で無視
  - `autoMode` / `useAutoModeDuringPlan` … shared project settings からは読まれない
  （出典: `docs/settings` / `docs/permission-modes`）
- **`--add-dir` の非カバー**: `output-styles`/`hooks`/`settings.json` の大半は `--add-dir` 先から読まれない（[§2](#combine)）。これらを「`--add-dir` で結合したのに動かない」と誤解しないこと。テストは `<Share>` で直接起動するか物理配置で。**`commands` は v2.1.235 版(2026-08-19) から `--add-dir` の例外ロード対象に加わった**（live reload なし）ため、このグループからは外れる（[§2](#combine)）。
- **`permissions.additionalDirectories` 経由は自動ロードしない**: 同じ追加ディレクトリでも、`--add-dir` フラグ／`/add-dir` コマンドなら skills 等を読むが、`additionalDirectories` 設定値経由ではファイルアクセス付与のみ。
- **`settings.local.json` を共有資産にしない**: project 個人・gitignore 専用（`--add-dir` で読まれるのは `enabledPlugins`/`extraKnownMarketplaces` の2キーのみで、それ以外は読まれない）。配布 clone（`<Share>`）に置かない（`CLAUDE.local.md` と同じアンチパターン）。共有したい設定は `settings.json` へ。
  - **配布されるのは Git 追跡分のみ**: `<Share>` が git リポジトリなら、漏洩可否を分けるのは「ローカルに実在するか」ではなく「**Git 追跡されているか**」。gitignore 済みで未追跡の個人ファイル（`settings.local.json`/`CLAUDE.local.md`）は、作業ツリーに実在しても clone には乗らない＝参照側へ漏れない（ただし掃除は推奨）。逆に**誤って追跡してしまった個人ファイルは漏れる**ため `git rm --cached` ＋ `.gitignore` で外す。`check-assets`（`scripts/`・手順書 §6）はこの**追跡基準**で判定する（追跡＝FAIL／未追跡で実在＝WARN／不在＝PASS。非 git の素ディレクトリのみ実在＝FAIL）。
- **同名衝突は警告なく解決される**: 方法B では `<Other>` 自身の `.claude` も同時にロードされ、`<Share>` の資産と混ざる。同一スコープに同名の subagent/skill があると Claude Code は**警告・プロンプトなしで片方を残し他方を破棄**する（`docs/sub-agents`）。混入はエラー検知に頼れないので、`/memory`・`/skills`・`/context` で**何がどのパスから読まれたかを目視**する（**v2.1.198 以降 `/agents` は subagent 一覧を表示しないため、ロード元パス付きで custom subagents を表示する `/context` を使う**）。`<Share>` 単独で検証したいなら `.claude` の無い空作業 dir から `--add-dir`（クリーン隔離 [§4](#clean)）。
  - **v2.1.235 版(2026-08-19) での部分自動化**: 現行の `/doctor` は**同一ディレクトリ内**の同名 subagent 定義を検出し、リネーム/削除を提案するようになった（`docs/sub-agents`）。ただし検出範囲は同一ディレクトリ内に限られ、`<Other>/.claude/agents/` と `--add-dir <Share>/.claude/agents/` のような**スコープをまたぐ衝突は対象外**。したがって上記の `/context` 目視確認は引き続き必要。

---

<a id="layer3"></a>

## 7. 層3（managed settings）の開発・テスト（注記）

層3（managed settings）で配る資産（permissions/`CLAUDE.md`/MCP/subagents/skills 等）の検証は、層1 と共通の手段（`/status`・`/doctor`）に加えて以下が効く（本フェーズはスコープ層1中心のため概要のみ。詳細は v1.2 案D）:

- **配信チャネルの確認**: `/status` の `Setting sources` 行に `Enterprise managed settings (remote)`/`(plist)`/`(HKLM)`/`(HKCU)`/`(file)` と表示され、**どの方式で managed settings が届いているか**を確認できる（`docs/settings` / `docs/admin-setup`）。
- **クリーンセッションでも適用される**: managed settings は system パスにあるため `CLAUDE_CONFIG_DIR` で隔離しても残る（[§4](#clean)）。テスト時はこれを織り込む。
- **server-managed の承認ダイアログ**: shell コマンド系設定・未知の環境変数・hook 定義を含む managed settings は、適用前に**ユーザー承認ダイアログ**が出る（拒否すると Claude Code は終了）。`-p`（非対話）では**ダイアログをスキップし、その実行限りで適用**される。**v2.1.207 以降は承認として記録・キャッシュされないため、次の対話セッションでは改めてダイアログが出る**（v2.1.207 より前は非対話実行が承認として保存され、以後の対話セッションでダイアログが出なくなっていた）。**CI の `-p` 実行で対話側の承認を代替することはできない**点に注意（`docs/server-managed-settings`「Approval memory」節）。
- **auto mode ルールの確認**: `claude auto-mode config`（展開後の適用ルールを JSON 出力）／`claude auto-mode defaults`／`claude auto-mode critique`（カスタムルールのレビュー）。

---

<a id="implications"></a>

## 8. v1.2・第1フェーズとの接続

- 本書は v1.2 §解決案 **案A（層1 commit/テンプレート）・案C（`--add-dir`）** の**開発・テスト運用面**を埋めるもの。v1.2 案A パターン2（共通リポ `<Share>` を clone ＋起動オプションで読込）が、そのまま本書の**結合テスト構成**に対応する（テスト用の結合＝そのまま配布運用にも使える）。
- 第1フェーズ（plugin）との統合像: **「機能・拡張資産は plugin 化して `--plugin-dir` でテスト」「config/ガバナンス資産はネイティブロードで `/memory`・`/status`・`/doctor` で検証」**——資産特性で開発・テストの型が分かれる。両者をまたぐ skills/agents は、plugin 同梱なら `--plugin-dir`、層1 単体なら `--add-dir`、と配布チャネルに応じてテスト手段も変わる。
- **作業仮説の確定**: 「配布用リポと開発・テストリポは別（後者ローカル）／`--add-dir` で結合してテスト」は、**skills・subagents・CLAUDE.md・rules で成立**。`settings.json` は `--settings`、`output-styles`/`hooks` は結合不可で直接起動、という差を本書で確定した（`commands` は v2.1.235 版(2026-08-19) から `--add-dir` の例外ロード対象に加わったため、この「結合不可」グループからは外れた。[§2](#combine)）。

---

<a id="topology"></a>

## 9. 推奨リポジトリ構成（`<Dev>` / `<Other>` / `<Share>`）

ローカル環境のリポジトリを役割で3分類すると動線が明確になる（仕組みは [§2](#combine) のまま・トポロジの整理）:

| 記号 | リポジトリ | 役割 |
|---|---|---|
| `<Dev>` | 共有資産を**開発**するリポジトリ | 自由に試作・イテレーション |
| `<Share>` | 公開（配布）リポジトリの**ローカル clone** | 共有ペイロード。`<Other>` から `--add-dir`/`--settings` で参照。**公開前検証はここに資産を格納して実施** |
| `<Other>` | 同じ環境で日常作業している**各リポジトリ** | `<Share>` を参照し、普段の作業がそのまま公開前テストになる |

動線: **`<Dev>` で試作 → `<Share>` に格納（staging）→ `<Other>` から参照して検証 → `<Share>` を push して公開**。第1フェーズ plugin の「standalone（速い試作）→ marketplace リポ（配布形態で検証）」と同型（`<Dev>`=standalone・`<Share>`=marketplace リポ）。`<Other>` は普段から `<Share>` を参照しているため、**`<Share>` へ格納するだけで日常作業が公開前テストになる**（専用ハーネス不要・真の配布形態＋真の参照経路で検証）。

**`<Share>` の構成（採用＝案1・共有ペイロード専用）**:

```
<Share>/
├── README.md            # <Share> リポ固有の運用メモ（memory ファイルでない＝自動ロードされない）
├── CLAUDE.md            # 全リポ共通ルール（= .claude/CLAUDE.md と等価・--add-dir+env で <Other> へ届く）
└── .claude/
    ├── rules/*.md       # 共通トピック規約
    ├── skills/          # --add-dir で自動ロード（env 不要）
    └── agents/          # --add-dir で自動ロード（env 不要）
    # settings.json を共有するなら <Other> 側で --settings <Share>/.claude/settings.json
```

- リポ固有情報を `README.md` に隔離 → `--add-dir <Share>`＋環境変数でも**共通ルールだけ**が `<Other>` に届く（[§memory ロード範囲](#adddir-memory-range)）。
- `<Other>` の起動ランチャーに `--add-dir <Share>` ・ `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` ・必要なら `--settings <Share>/.claude/settings.json` を仕込む（v1.2 案A パターン2 / 案C）。
- 公開前検証は `<Other>` 側で `/memory`・`/context`・`/status` を見て、`<Share>` 由来のファイル・レイヤがロードされているか確認（[§3](#verify)）。`output-styles`/`hooks` は `--add-dir` で届かないため、それらは `<Share>` で直接起動して検証（`commands` は v2.1.235 版(2026-08-19) から `--add-dir` で届くようになった）。
- **公開前の必須ゲート（衛生＋脆弱性）**: push 前に **`check-assets`（衛生・シェル/CI）と `/security-review`（脆弱性・Claude セッション内）の両方を必須**で通す。`/security-review` は「現在ブランチの差分への read-only なセキュリティパス」（`docs/security-guidance` のレイヤ表 "On demand"）で、**コードを含まない資産に走らせても read-only・findings ゼロで弊害が無い**ため、実行漏れ防止のため常に実行する。効きが高いのは同梱スクリプト・hooks（実行コード）。check-assets（衛生）とは役割が別の補完。

---

<a id="sources"></a>

## 出典

根拠は Claude Code 公式ドキュメントのローカル DL 版 `llms-full.txt`。**ページ名＋セクション**を主アンカーとする（行番号は snapshot 依存のため割愛。2つの照合 agent が参照した snapshot ファイルが異なり行番号が一致しないため、ページ名で照合すること）。原文照合は `cc-docs-config-scopes-expert`／`cc-docs-permissions-sandbox-expert` による。

| # | 主張 | ページ |
|---|---|---|
| C1 | `/memory`＝ロード済み CLAUDE.md/CLAUDE.local.md/rules 一覧＋auto memory トグル ／ **v2.1.235 版(2026-08-19)**: `/memory` は「ロード済み一覧」ではなく**未作成ファイルも含む置き場所一覧**（＋編集導線）に変化。実際にロードされたかの確認は `/context` が正 | `docs/memory`「View and edit with /memory」節 / `docs/debug-your-config`「See what loaded into context」節 |
| C2 | `/context`＝コンテキスト内訳（system prompt/memory/skills/MCP/会話） ／ **v2.1.235 版(2026-08-19)**: custom subagents をロード元パス付きで表示する項目が追加された | `docs/debug-your-config`「See what loaded into context」節 |
| C3 | `/status` の `Setting sources` 行＝ロード済み settings レイヤ＋managed 配信チャネル表示。個別キーの出所は非表示 | `docs/settings` / `docs/admin-setup` |
| C4 | `/doctor`（`claude doctor`）＝設定ファイルの schema/無効キー検査・`f` で修正 ／ **v2.1.235 版(2026-08-19)**: `f` キー方式は Before v2.1.205 の廃止済み挙動と明記。現行は検出結果を提示→確認のうえ適用。あわせて同一ディレクトリ内の同名 subagent 定義を検出しリネーム/削除を提案する機能が追加 | `docs/debug-your-config` / `docs/setup` / `docs/commands`「All commands」`/doctor` 行 / `docs/sub-agents`「Manage subagents」節 |
| C5 | `/skills`（バッジで user-only 等）・`/agents`・`/help`・`/` フィルタ ／ **v2.1.235 版(2026-08-19)**: `/agents` は v2.1.198 以降、一覧表示をやめ `.claude/agents/` の直接編集を促すリマインダーのみを表示するよう変更された。ロード元パス付きの subagent 確認は `/context` を使う | `docs/debug-your-config` / `docs/commands` / `docs/sub-agents`「Manage subagents」節 |
| C6 | `InstructionsLoaded` hook＝どの指示ファイルが・いつ・なぜロードされたかログ。`ConfigChange` hook＝settings 再読込で発火 | `docs/memory` / `docs/hooks` / `docs/settings` |
| C7 | クリーンテスト＝`CLAUDE_CONFIG_DIR` を空 dir に向け `.claude` 無し dir から起動。managed は残る・Linux/Win 再ログイン・mac は Keychain 継承 ／ **実機確認 v1.3**: `--debug-file` でクリーン起動の watch 対象は空 config の `settings.json` **のみ**＝個人 `~/.claude`・project・local を排除を実証。`C:\Program Files\ClaudeCode\managed-settings.json` は継続探索（managed 残存）。auth 非継承で `Not logged in`＝Win 再ログイン要を裏取り | `docs/debug-your-config` / `docs/env-vars` |
| C8 | settings はファイル監視で即時反映（brief delay）／`model`・`outputStyle` は再起動側／環境変数は起動時のみ／skills ホットリロード・`/reload-skills` | `docs/settings` / `docs/env-vars` / `docs/commands` |
| C9 | `--add-dir` 例外ロード表（skills/subagents〔**v2.1.178+**。v2.1.165 までは非ロード〕/`enabledPlugins`・`extraKnownMarketplaces`/環境変数で CLAUDE.md・rules）。`additionalDirectories` 設定経由はファイルアクセスのみ ／ **v2.1.235 版(2026-08-19)**: `commands/`（`.claude/commands/`）が例外ロード対象に新規追加（live reload なし。`<Share>` と参照元プロジェクトの両方に同名コマンドがある場合は参照元プロジェクト側が優先）。正本は [v1.2 付録B『`--add-dir` 例外ロード一覧（正本）』](../../01.配布・統制方針調査/結論・構成案_ポータブルな.claude共有_v1.2.md#adddir-exceptions) | `docs/permissions`「Additional directories grant file access, not configuration」表 / `docs/sub-agents` |
| C10 | `--settings` の優先順位（managed>command-line>local>project>user）・マージ規則・deny>ask>allow ／ **実機確認 v1.3**: `--debug-file` で各スコープが別 destination として併存——`--settings` 由来は **`flagSettings`（＝command-line 層）**、他は `userSettings`/`projectSettings`/`localSettings`（managed は本検証では不在のため未出現だが、C12 の WARN が "policy" 層として言及）。tier 名がそのまま precedence（policy>flag>local>project>user）に対応 | `docs/settings` / `docs/permissions` |
| C11 | `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` で `--add-dir` 先の CLAUDE.md/rules/CLAUDE.local.md をロード | `docs/permissions` |
| C12 | project/local で無視される security キー（`defaultMode:auto`・`skipDangerousModePermissionPrompt`・`autoMode`・`useAutoModeDuringPlan`） ／ **実機確認 v1.3**: project に `defaultMode:"auto"` を仕込み `--debug-file` 起動で `[WARN] settings defaultMode "auto" ignored — only policy/user/flag settings may grant auto mode (projectSettings and localSettings are repo-controllable)` を実観測＝無視を実証。**付与可能スコープは policy(managed)/user(`~/.claude`)/flag(`--settings`)**＝従来記載「効かせるなら `~/.claude`」を精密化（`--settings`・managed でも付与可） | `docs/settings` / `docs/permission-modes` |
| C13 | trust dialog の影響（`autoMemoryDirectory` は trust 後・`extraKnownMarketplaces` install prompt は trust 後・`strictKnownMarketplaces` は trust 前から強制） | `docs/settings` |
| C14 | server-managed の承認ダイアログ（shell/env/hook 設定）・拒否で終了・`-p` でスキップ／`claude auto-mode config|defaults|critique` ／ **v2.1.235 版(2026-08-19)**: `-p` 非対話での適用は**その実行限り**（承認として記録・キャッシュされない）。v2.1.207 以降、次の対話セッションでは改めてダイアログが出る（v2.1.207 より前は非対話実行が承認として保存され、以後の対話セッションでダイアログが出なくなっていた） | `docs/server-managed-settings`「Approval memory」節 / `docs/auto-mode-config` |
| C15 | `/security-review`＝現在ブランチ差分への read-only セキュリティパス（"On demand" レイヤ）。security-guidance プラグイン（in-session）・Code Review（PR）と多層 | `docs/security-guidance` / `docs/commands` |
| C16 | `claude --safe-mode`（**v2.1.235 版(2026-08-19) で新設**）＝CLAUDE.md/skills/plugins/hooks/MCP/custom commands・agents/output styles 等の全カスタマイズを無効化して起動する一次切り分け手段。managed settings のポリシーは適用継続。`<Other>`/`~/.claude` からの完全分離はしないため `CLAUDE_CONFIG_DIR` クリーンセッションの代替にはならない | `docs/cli-reference`「--safe-mode」行 / `docs/debug-your-config`「Test against a clean configuration」節 |

## 変更履歴

- **v1.6（2026-08-20）**: 公式ドキュメント最新版（**CLI v2.1.235 相当・2026-08-19 取込**）との照合で検出した本書対象の指摘 6 件（陳腐化 4 件・改善機会 2 件）を反映し、加えて対の手順書側の指摘 1 件を整合のため本書にも反映。**版番号は v1.4 が既に存在していたため、タスク指示の「v1.3→v1.4」から繰り上げて v1.6 とした**（H1 の版表記も同時に v1.0 の据え置き漏れを解消し v1.6 へ更新）。
  - **【CRITICAL】`/agents` の仕様変更**（§3・§6・§エグゼクティブサマリ・出典 C5）: v2.1.198 以降 `/agents` は subagent 一覧を表示せず `.claude/agents/` 直接編集を促すリマインダーのみになった。同名衝突の目視確認手段を `/context`（custom subagents をロード元パス付きで表示）へ差し替え。
  - **【IMPORTANT】`/memory` の仕様変更**（§3・出典 C1）: 「ロード済み一覧」から「置き場所一覧（未作成ファイル含む）」へ変化。実際のロード確認は `/context` が正である旨を明記。
  - **【IMPORTANT】`/doctor` の `f` キー廃止**（§3・出典 C4）: `f` キー方式は Before v2.1.205 の廃止済み挙動と明記し、現行の「提示→確認→適用」フローに更新。
  - **【IMPORTANT】`commands/` の `--add-dir` 対応**（§2・§6・§8・§9・出典 C9）: v2.1.235 版で `.claude/commands/` が `--add-dir` 例外ロード対象に追加された（live reload なし・同名は参照元プロジェクト優先）。結合手段表を `output-styles`/`hooks`（結合不可）と `commands`（結合可）に分割し、正本（[v1.2 付録B](../../01.配布・統制方針調査/結論・構成案_ポータブルな.claude共有_v1.2.md#adddir-exceptions)）と整合させた。
  - **【SUGGESTION】`--safe-mode` を一次切り分けとして追加**（§4・出典 C16）: 新設の `claude --safe-mode` を、既存の `CLAUDE_CONFIG_DIR` クリーンセッション手順の**前段**（一次切り分け）として追記。`<Other>`/`~/.claude` からの完全分離はしない点を明記し、既存手順を置き換えないことを明確化。
  - **【SUGGESTION】`/doctor` の同名 subagent 自動検出**（§6・§3・出典 C4）: 現行の `/doctor` が同一ディレクトリ内の同名 subagent を検出する機能を追記。検出範囲は同一ディレクトリ内限定でスコープをまたぐ衝突は対象外のため、`/context` 目視確認は引き続き必要と明記。
  - **【一貫性維持】server-managed の `-p` 承認スコープ**（§7・出典 C14）: 対の手順書側 v1.8 で追記した「`-p` 実行はその実行限りの適用（v2.1.207 以降、承認として記録・キャッシュされない）」を本書 §7・出典表にも反映し、2 文書間の矛盾を防止した。
  - **適用しなかった指摘**: なし（G3 一覧 13 件すべて適用。うち `/claude-security` プラグイン新設の追記は対の手順書側の変更で、本書は §9 の必須ゲート記述と矛盾しないため変更不要と判断）。
- **v1.5（2026-06-29）**: 横断整合性レビュー J1 反映。§2 結合表に版依存事実の**正本＝[v1.2 付録B『--add-dir 例外ロード一覧（正本）』](../../01.配布・統制方針調査/結論・構成案_ポータブルな.claude共有_v1.2.md#adddir-exceptions)** への参照注記を追加（本表は運用早見）。
- **v1.4（2026-06-29）**: 横断整合性レビュー反映。`settings.local.json` も `enabledPlugins`/`extraKnownMarketplaces` の2キーに限り `settings.json` 同様 `--add-dir` で読まれる事実（docs「Additional directories」表・v2.1.195）に合わせ、§2 結合表・§優先順位注記・§6 落とし穴の「`settings.local.json` は `--add-dir` でも読まれない」を**2キー例外あり**に精密化（対の手順書 v1.4 と一致）。共有用途に使わない実務指針は不変。
- **v1.3（2026-06-22）**: item3 残検証 **C7 / C10 / C12 を実機確認**（`claude -p … --debug-file` の設定ロードログ＝LLM 自己申告でない権威ある証跡で実証）。(C7) クリーン起動（`CLAUDE_CONFIG_DIR`=空 dir ＋ `.claude` 無し作業 dir）で watch 対象は空 config の `settings.json` のみ＝個人/project/local を排除・managed パスは継続探索・auth 非継承（`Not logged in`）を確認。(C10) `--settings` 由来が destination **`flagSettings`（command-line 層）**として `userSettings`/`projectSettings`/`localSettings` と別 destination で併存することを確認。(C12) project の `defaultMode:"auto"` に対し `[WARN] settings defaultMode "auto" ignored — only policy/user/flag settings may grant auto mode` を実観測＝無視を実証し、**付与可能スコープが policy/user/flag**（managed・`~/.claude`・`--settings`）であると判明（従来「効かせるなら `~/.claude`」を精密化）。検証用 fixture と個人ルールを含む debug ログは検証後に削除。
- **v1.2（2026-06-22）**: subagents×`--add-dir` の **CLI バージョン依存**を反映。§2 結合表・C9 を「**v2.1.178+ で `<Share>/.claude/agents/` をスキャン・ロード／v2.1.165 までは非ロード**」と版境界付きに訂正（v1.2 報告書 errata [75] と整合）。実機検証（item 3）で `cc-docs-config-scopes-expert` の原文照合および新旧スナップショット比較により、当初 errata の「subagents は `--add-dir` で常時ロード」が版依存だったと判明。
- **v1.1（2026-06-22）**: `base-dev-kit-for-cc` を実 `<Share>` として整備した際の知見を反映。§6 落とし穴に **「配布されるのは Git 追跡分のみ」** を追記——gitignore 済みで未追跡の個人ファイル（`settings.local.json`/`CLAUDE.local.md`）は作業ツリーに実在しても clone には乗らず参照側へ漏れない（誤って追跡したものは漏れるため `git rm --cached`＋`.gitignore`）。対の手順書の `check-assets`（`scripts/`）を**追跡基準**へ改修（追跡＝FAIL／未追跡で実在＝WARN／不在＝PASS・非 git の素ディレクトリのみ実在＝FAIL）し、共有共通ルールの所在期待を `.claude/CLAUDE.md` へ変更（ルート `CLAUDE.md` が追跡されている場合は `--add-dir`＋env 漏れを WARN）。bash/PowerShell 両版で FAIL=0 を実走確認。
- **v1.0（2026-06-21）**: 初版。`cc-docs-config-scopes-expert`／`cc-docs-permissions-sandbox-expert` の原文照合に基づき、Marketplace 外資産（config 資産）の開発・テスト方法（ネイティブロード・結合手段3経路・ロード検証コマンド・クリーン隔離テスト・反映タイミング・落とし穴・層3 注記）を整理。レビュー反映として §2 に **`--add-dir` の正確な memory ロード範囲**（ルート/`.claude/` 両 `CLAUDE.md`＋`rules`＋`CLAUDE.local.md` を環境変数 all-or-nothing で一括ロード・共有境界は `--add-dir` 範囲で制御・`CLAUDE.local.md` gotcha・出典 `docs/memory`）と **§9 推奨リポジトリ構成（`<Dev>`/`<Other>`/`<Share>`・案1＝共有ペイロード専用＋README 隔離）** を追加。さらに **`settings.local.json` は共有不可**（共有は `settings.json`／マシン全リポの個人既定は `~/.claude/settings.json`〔`~/.claude/settings.local.json` は非存在〕）を §2・§6 に追記。用語を手順書と揃え **`<D>`→`<Share>`・「config リポ」→`<Share>`/`<Other>`** に統一（対の手順書に開発・テスト補助スクリプト `scripts/` を追加）。レビュー反映: (A) ネイティブ確認＝スモーク・(B) 結合テスト＝**正式機能検証の本命**と明確化、方法B の `<Other>/.claude` 混入と**同名衝突が警告なく解決される**点（`/memory` 等で目視・クリーン隔離で回避）を §エグゼクティブサマリ・§6 に追記。**公開前の必須ゲート**として `check-assets`（衛生）＋ `/security-review`（脆弱性・read-only・空振り無害）の併用を §9 に追記し出典 C15（`docs/security-guidance`）を追加。
