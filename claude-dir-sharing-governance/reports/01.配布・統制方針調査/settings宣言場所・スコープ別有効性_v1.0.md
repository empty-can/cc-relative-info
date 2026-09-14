# settings キー × 宣言場所 × スコープ別有効性（D-12）

> - **想定読者**: `.claude/` のチーム配布・統制を設計する担当者。**「その設定をどこに書けば効くのか」**を確かめたい読み手。
> - **位置づけ**: 確定成果物。[`結論・構成案_ポータブルな.claude共有_v2.0.md`](./結論・構成案_ポータブルな.claude共有_v2.0.md) の**補助資料**にあたる。**D-12**（公式 docs のページ再編に伴う旧出典のページ名写像）への回答を §5 に含み、あわせて宣言場所・スコープ別有効性を整理した。
> - **扱わないこと**: 配布チャネル適合（層1 commit / 層2 plugin / 層3 managed）。それは v2.0 [§2](./結論・構成案_ポータブルな.claude共有_v2.0.md#where) の担当である（軸C 対象外）。
> - **作成日**: 2026-09-14 ／ **調査方法**: 公式ドキュメントの読解のみ（Read / Grep）。**実機検証は行っていない**。
> - **収録基準**: 後述 §1。**全 237 キーは写していない**（間違えると設計が壊れるキーに絞った）。
> - **原典（唯一の根拠）**: v2.0 と同一の基準スナップショット **BASE-D** —— `empty-can/LLMs` @ commit **`f42c3bbc7514f65d9b93da10d594de373927552d`**（2026-09-13 取込）の `official-llms-txts/code.claude.com/docs/llms-full.txt`（**CLI v2.1.269 相当・96,349 行**・blob `26ddc6534ed2f96e147cd77a1b8acfddba986ce2`）。**本文中の `L<数字>` はすべてこの断面の絶対行番号**。
>
>   ```bash
>   git -C <LLMs のクローン> show f42c3bbc7514f65d9b93da10d594de373927552d:official-llms-txts/code.claude.com/docs/llms-full.txt > base-d.txt
>   sed -n '<行番号>p' base-d.txt
>   ```

---

## 1. 収録基準と、この表の読み方

### 1.1 収録したキー

次のいずれかに当たるものだけを収録した。

| # | 基準 | 該当例 |
|---|---|---|
| A | settings 系以外にも宣言場所がある（CLI フラグ・plugin・別ファイル・環境変数・frontmatter） | `hooks` / `model` / `permissions.additionalDirectories` / `env` |
| B | スコープによって無視される（project / local に書いても効かない等） | `autoMode` / `pluginConfigs` / `modelPicker` / `permissions.defaultMode: "auto"` |
| C | `.claude/` のチーム共有・配布設計に直接影響する | `strictPluginOnlyCustomization` / `allowManagedHooksOnly` / `extraKnownMarketplaces` |

**これ以外のキーは「settings 系（user / project / local / `--settings` / managed）でのみ宣言可・全スコープ有効（Scope = `Any file`）」と畳んでよい。** 網羅性より、間違えると設計が壊れるキーを確実に押さえることを優先した。

### 1.2 5 スコープの定義（原典の用語）

BASE-D は settings ファイルを 4 つ＋managed として定義する（L85539–L85548）。`--settings` はファイルではなく「コマンドライン引数」層として precedence スタックに入る（L85773）。

| 本ドラフトの呼称 | 実体 | 原典の記述 |
|---|---|---|
| `user` | `~/.claude/settings.json` | L85545 |
| `project` | `.claude/settings.json`（コミット対象） | L85546 |
| `local` | `.claude/settings.local.json`（gitignore 想定） | L85547 |
| `--settings` | CLI に渡す JSON かそのパス。user/project/local の上、managed の下 | L85706, L85773 |
| `managed` | `managed-settings.json` / MDM / server-managed 等 | L85548, L30476–L30481 |

**precedence（高い順）**: managed → コマンドライン引数（`--settings` 含む）→ local → project → user（L85770–L85777）。
**環境変数はこのスタックの層ではない**。ペアごとに勝敗が決まる（L85778）。

### 1.3 settings-reference の Scope 列が一次情報源

`settings-reference` の **Settings index**（L86308 以降、表は L86314–L86543）に全キーの Scope 列がある。値は `Any file` / `User or managed` / `User, local, or managed` / `Managed` / `Global config` の 5 種（凡例は L86310）。軸B はこの列を機械的に読み取ったもの。

---

## 2. 軸A: 同じ設定を宣言できる場所と、競合時の勝敗

### 2.1 叩き台の検証結果サマリ

| 叩き台の記述 | 判定 | 根拠 |
|---|---|---|
| `hooks` → `settings.json` / plugin `hooks/hooks.json` | **正しいが不足**。実際は 7 箇所 | L73943–L73951 |
| MCP → `.mcp.json` / plugin 同梱 / `--mcp-config` / `managed-mcp.json` / `managedMcpServers` | **正しい**。＋`~/.claude.json`（local/user scope）と in-process `type:"sdk"` がある | L31327–L31331, L29964, L90443–L90448 |
| permissions → settings / `--allowedTools` / skill `allowed-tools` / subagent `tools` / `PreToolUse` hook | **概ね正しいが用語要注意**。subagent の `tools` は「許可」ではなく**利用可能ツールの絞り込み**で permission rule ではない。`PermissionRequest` hook のほうが permission 判断の正規経路 | L43882–L43906, L42644, L27245–L27267 |
| `env` → settings `env` ブロック / シェル環境変数。変数ごとに勝敗が違う可能性 | **正しい**。settings の `env` がシェルを上書きするのが原則だが、無視される変数群がある | L88481, L88493–L88505 |
| `model` / `permissions.defaultMode` / `outputStyle` | **正しい** | L86759, L87291, L79797 |
| `additionalDirectories` と `--add-dir` は同名だが挙動が違う | **正しい。設計上もっとも危険な差** | L81082–L81102 |

### 2.2 `hooks`

| 宣言場所 | 有効範囲 | 共有可否 | 根拠 |
|---|---|---|---|
| `~/.claude/settings.json` | 全プロジェクト | 不可（個人マシン） | L73945 |
| `.claude/settings.json` | 当該プロジェクト | コミットで共有可 | L73946 |
| `.claude/settings.local.json` | 当該プロジェクト | 不可 | L73947 |
| managed settings | 組織全体 | 管理者のみ | L73948 |
| plugin の `hooks/hooks.json` | plugin 有効時 | plugin に同梱 | L73949, L81300 |
| skill frontmatter | 呼び出し後、**セッション残り全体** | skill ファイルに同梱 | L73950, L74381 |
| subagent frontmatter | **その subagent 実行中のみ** | agent ファイルに同梱 | L73951, L74380 |
| plugin manifest の `hooks` フィールド（inline / 別パス） | plugin 有効時 | plugin に同梱 | L81300, L81754 |

**競合時の勝敗**: hooks は**上書きではなくマージ**（L73968, L74347）。managed の hooks は他ファイルから消せない（L73968, L74424）。

| 制御キー | 効果 | 根拠 |
|---|---|---|
| `disableAllHooks`（`Any file`） | managed に書けば managed hooks 含め全停止。他ファイルに書くと user/project/local/plugin のみ停止、managed・SDK・managed force-enable plugin の hooks は動き続ける | L89581–L89584 |
| `allowManagedHooksOnly`（`Managed` 専用） | managed hooks ＋ SDK hooks ＋ managed が force-enable した plugin の hooks だけが動く。**agent frontmatter の hooks もブロック** | L89540, L89556–L89559 |
| `strictPluginOnlyCustomization.hooks`（`Managed` 専用） | user/project/local の `settings.json` の hooks を停止。plugin hooks と managed hooks は残る | L90106 |

> **設計上の注意**: 「チーム共通 hooks を plugin へ移す」方針を採る場合、`allowManagedHooksOnly` が敷かれた環境では **managed が `enabledPlugins` で force-enable した plugin のみ**が例外になる（L89557）。plugin なら常に通る訳ではない。
> **plugin subagent の制約**: plugin 由来の subagent は `hooks` / `mcpServers` / `permissionMode` frontmatter を**無視する**（L43690）。hooks 付き subagent は plugin 配布できない。

### 2.3 MCP サーバ

| 宣言場所 | スコープ | 根拠 |
|---|---|---|
| `~/.claude.json`（local scope: プロジェクト単位 / user scope: 全プロジェクト） | 個人 | L31329, L31331, L31335 |
| `.mcp.json`（プロジェクトルート） | チーム共有（要承認） | L31330, L31368 |
| plugin 同梱（`mcpServers` フィールド） | plugin 有効時 | L81755 |
| `--mcp-config`（CLI） | そのセッションのみ | L70780 |
| `managed-mcp.json`（システムパス） | 組織全体・**排他制御** | L29964, L29974–L29976 |
| `managedMcpServers`（managed settings、`Managed` 専用） | 組織全体・ユーザ自身のサーバと**併存** | L90443–L90447 |
| in-process `type: "sdk"` | ホストアプリが登録 | L90311, L90356 |

**競合時の勝敗**

| 規則 | 内容 | 根拠 |
|---|---|---|
| `managed-mcp.json` の排他性 | これをデプロイすると、そこに書いたサーバ＋`managedMcpServers`＋in-process のみ。plugin サーバも `--mcp-config` も無効 | L29964 |
| `--mcp-config` との衝突 | ワークステーションでは**起動時に exit**。cloud session ではサーバを落として起動 | L30015–L30016 |
| `--strict-mcp-config` | `managed-mcp.json` 下では常に exit | L30018 |
| deny > allow | `deniedMcpServers` は `allowedMcpServers` に優先。managed 由来サーバにも効く | L90370, L30024 |
| allowlist の適用外 | `managedMcpServers` の全エントリと、`${VAR}` 展開を使わない `managed-mcp.json` エントリは allowlist 免除 | L90313 |
| `allowManagedMcpServersOnly`（`Managed`） | `allowedMcpServers` を managed のみから読む。`deniedMcpServers` は全スコープマージのまま | L90333 |
| `strictPluginOnlyCustomization.mcp`（`Managed`） | `~/.claude.json` と `.mcp.json` からのロードを停止。plugin / `managed-mcp.json` / `managedMcpServers` は残る | L90120 |
| `disableSideloadFlags`（`Managed`） | `--plugin-dir` / `--plugin-url` / `--agents` / `--mcp-config` を起動時に拒否 | L91314 |

### 2.4 permission（何を許すか）

| 宣言場所 | 何を宣言できるか | 勝敗 | 根拠 |
|---|---|---|---|
| settings の `permissions.allow` / `.ask` / `.deny` | permission rule | **deny → ask → allow の順に評価、最初にマッチしたものが決まる**。スコープの上下は関係ない | L87174, L81145–L81147 |
| `--allowedTools`（CLI） | 1 セッションの allow rule 追加 | 任意ファイルの deny rule が優先 | L87158 |
| `--disallowedTools`（CLI） | 1 セッションの deny rule 追加 | managed を含め、制限のみ追加できる | L87212, L81145 |
| skill frontmatter の `allowed-tools` | **その skill を呼んだターンのみ**の事前承認 | 次のメッセージでクリア。ツールを制限はしない | L42644 |
| skill frontmatter の `disallowed-tools` | skill 有効中はツールプールから除去 | 次のメッセージでクリア | L42659 |
| subagent frontmatter の `tools` / `disallowedTools` | **その subagent が使えるツールの絞り込み**（permission rule ではない） | `disallowedTools` を先に適用し、残りに `tools` を解決 | L43882–L43902 |
| `PermissionRequest` hook | 権限プロンプトを自前ロジックで許可/拒否 | `"behavior":"allow"` で Claude Code が代わりに応答 | L27245–L27258, L81333 |
| `PreToolUse` hook | ツール呼び出しのブロック | L81332 |

**設計上重要な例外**

| 事象 | 内容 | 根拠 |
|---|---|---|
| `allowManagedPermissionRulesOnly`（`Managed` 専用） | user/project/local/`--settings` の allow/ask/deny を**全部無視**。`--allowedTools` も無視。プロンプトの「常に許可」選択肢も隠す。`--disallowedTools` とセッション内 deny/ask は残る | L87038, L87042 |
| workspace trust ゲート | project の `.claude/settings.json` の `permissions.allow` と `permissions.additionalDirectories` は**信頼ダイアログ受諾まで効かない**。`deny` / `ask` は即時有効 | L81153, L87170, L87249 |
| local ファイルの trust | `.claude/settings.local.json` が **git 追跡下にある**か `.claude` が symlink だと、repository 由来とみなされ trust 待ちになる | L81165 |
| `-p` / SDK 実行 | trust ダイアログが出ないため、project の allow rule は**使われない**（警告が stderr に出る） | L81185 |
| local の allow が project の ask に勝てない | 「今後聞かない」で local に保存した allow rule は、project/managed の ask rule を上回らない | L85861 |

### 2.5 `permissions.additionalDirectories` と `--add-dir` ―― 同名だが挙動が正反対

**両方とも「ファイルアクセスを与える」点は同じ**（L81051–L81057）。差は `.claude/` 設定を読み込むかどうか。

| 読み込まれる設定 | `--add-dir` / `/add-dir` | `permissions.additionalDirectories` |
|---|---|---|
| `.claude/skills/` | **読む**（live reload あり） | **読まない** |
| `.claude/commands/` | **読む**（live reload なし。同名はプロジェクト側が勝つ） | **読まない** |
| `.claude/agents/` | **読む**（live reload なし） | **読まない** |
| `.claude/settings.json` / `settings.local.json` | **`enabledPlugins` と `extraKnownMarketplaces` キーのみ** | **読まない** |
| `CLAUDE.md` / `.claude/rules/` / `CLAUDE.local.md` | `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` のときのみ | **読まない** |

根拠: 表は L81092–L81098。「settings ファイルに書いた `additionalDirectories` はファイルアクセスのみを与え、上記のどの設定もロードしない」は L81086 に明記。

補足:
- Agent SDK の `additionalDirectories`（TS）/ `add_dirs`（Python）は**内部で `--add-dir` に渡される**ので、settings キーと同名でも `--add-dir` 側の挙動になる（L81088）。
- `--add-dir` 由来の skills / commands / subagents は `project` setting source 経由でロードされるので、`--setting-sources` で project を外すとロードされない（L81088）。
- プロジェクト配下のサブディレクトリに `/add-dir` すると、作業ディレクトリを増やさずに skills/commands/subagents だけ読み込める（v2.1.257 以降、L81100）。
- hooks とその他の `settings.json` キーは**カレント作業ディレクトリの `.claude/` のみ**から読まれ、親ディレクトリへのフォールバックはない（L81102）。output styles は作業ディレクトリとその親、`~/.claude/`、managed から探索される（L81102）。

### 2.6 `env`

| 宣言場所 | 勝敗 | 根拠 |
|---|---|---|
| settings の `env` ブロック | **シェルの export を上書きする**。settings 間は通常の precedence | L88481, L72400 |
| シェルの環境変数 | settings の `env` に同名があれば負ける | L88481 |
| `env` に空文字を設定 | シェル export の打ち消しに使う。provider 選択上は unset 扱い、子プロセスは空値を継承 | L88482, L72402 |

**変数ごとに勝敗が違うケース**（叩き台の懸念は正しい）

| 変数 | 挙動 | 根拠 |
|---|---|---|
| `ANTHROPIC_MODEL` | シェル export が**任意ファイルの `model` キーに勝つ** | L85778, L86759 |
| `ANTHROPIC_DEFAULT_MODEL` | どのファイルも `model` を設定していないときだけ効く | L85778, L86767 |
| `NO_COLOR` / `FORCE_COLOR` | `env` に書いても**子プロセスにしか届かない**。Claude Code 自身の色はシェルで設定 | L88483 |
| `CLAUDE_CONFIG_DIR` / `CLAUDE_CODE_TMPDIR` / `HOME` / `TMPDIR` / `TMP` / `TEMP` / `XDG_*` | **project / local settings では無視**（警告ログのみ） | L88495–L88497 |
| `OTEL_LOG_RAW_API_BODIES` / `ENABLE_BETA_TRACING_DETAILED` / `BETA_TRACING_ENDPOINT` | 同上（project / local で無視） | L88498 |
| `CLAUDE_CODE_PROCESS_WRAPPER` / `CLAUDE_CODE_SYNC_SKILLS` / `CLAUDE_CODE_SYNC_PLUGINS` / `CLAUDE_CODE_PLUGIN_CACHE_DIR` / `CLAUDE_CODE_PLUGIN_SEED_DIR` | 同上（project / local で無視） | L88499 |
| `CLAUDE_CODE_REMOTE` / `CLAUDE_CODE_ACCOUNT_UUID` | **全ファイルで無視** | L88502 |
| `CLAUDE_CODE_MESSAGING_SOCKET` / `CLAUDE_CODE_MESSAGING_TOKEN` | 全ファイルで無視 | L88503 |
| `CLAUDE_CODE_PROJECT_DIR_NAME` / `CLAUDE_CODE_RESTRICTED` | 起動環境からのみ読む。全ファイルで無視 | L88504–L88505 |

**適用タイミング**: user / `--settings` / managed の `env` は起動時に適用。project / local の `env` は **workspace trust 受諾後**（ただし `-p` は trust ダイアログを出さないので起動時）（L88488–L88489）。

### 2.7 `model` / `permissions.defaultMode` / `outputStyle` / `agent`

| キー | settings 以外の宣言場所 | 勝敗 | 根拠 |
|---|---|---|---|
| `model` | `--model`（CLI）、`ANTHROPIC_MODEL`、`ANTHROPIC_DEFAULT_MODEL` | `--model` > `ANTHROPIC_MODEL` > `model` キー（**managed の `model` にも勝つ**）。`ANTHROPIC_DEFAULT_MODEL` は最下位 | L86759, L86767, L30660 |
| `model` の実質的なロック | `availableModels` キー | `/model`・`--model`・自前ファイルの `model` すべてを制約する。managed の `availableModels` はそのまま適用され、下位のエントリは無視 | L85772, L86591, L85788 |
| `permissions.defaultMode` | `--permission-mode`、`--dangerously-skip-permissions` | CLI フラグが 1 セッション優先。**`auto` と `bypassPermissions` は project / local から効かない** | L87281, L87291 |
| `outputStyle` | `/config`（Output style メニュー） | `/config` は **`.claude/settings.local.json`** に書く。plugin の output style は `force-for-plugin: true` でユーザの `outputStyle` を上書きできる | L79797, L79866 |
| `agent` | `--agent`（CLI）、**plugin ルートの `settings.json`** | `--agent` が 1 セッション優先。plugin の `settings.json` は `agent` と `subagentStatusLine` の 2 キーのみサポート。plugin の `settings.json` は `plugin.json` の `settings` より優先 | L86477, L90485, L38364, L38374 |

### 2.8 plugin / marketplace 系

| キー | 宣言場所と特記 | 根拠 |
|---|---|---|
| `enabledPlugins`（`Any file`） | project が user に勝つので、user で `false` にしても project の `true` を打ち消せない。打ち消すなら **local** に書く。managed の force-enable は打ち消せない | L90159 |
| `enabledPlugins` の限界 | project の `.claude/settings.json` で外部 plugin を有効化しても**他人にはインストールされない**。各自インストールが必要 | L90161 |
| `extraKnownMarketplaces`（`Any file`） | repository の `.claude/settings.json` / `settings.local.json` からは **trust 受諾後のみ**。未信頼フォルダ（`-p` 含む）は**無言で無視** | L90167 |
| `extraKnownMarketplaces` の競合 | 同名エントリは**最高優先ファイルのものを丸ごと採用**。フィールド継承なし（v2.1.228 以降） | L90196 |
| `strictKnownMarketplaces`（`Managed` 専用） | allowlist。空配列は完全ロックダウン（公式 Anthropic marketplace も遮断）。**空でない allowlist を設定すると `~/.claude/skills/` の `@skills-dir` plugin も止まる**（`{"source":"skills-dir"}` で復活） | L89923, L89925, L89969 |
| `pluginConfigs`（`User or managed`） | project / local は**無視**（v2.1.207 以降）。plugin の hook / MCP / LSP 設定に値を差し込むため、clone したリポジトリに供給させない | L90265, L90283 |
| `strictPluginOnlyCustomization`（`Managed` 専用） | `skills` / `agents` / `hooks` / `mcp` の 4 サーフェスを plugin ＋ managed のみに固定 | L90058–L90130 |

---

## 3. 軸B: スコープ別の有効性（どこに書くと無視されるか）

### 3.1 叩き台の検証結果

| 叩き台の記述 | 判定 | 実際 | 根拠 |
|---|---|---|---|
| `permissions.defaultMode: "auto"` が project/local で無視 | **正しい** | `auto` と `bypassPermissions` が project / local から効かない（v2.1.257 より前は `bypassPermissions` は任意ファイルから効いた） | L87281, L85839 |
| `skipDangerousModePermissionPrompt` が project/local で無視 | **誤り** | Scope は `User, local, or managed`。**無視されるのは project だけ**、local は有効 | L86499, L87342 |
| `autoMode` が project/local で無視 | **正しい** | Scope は `User or managed` | L86340, L87062 |
| `useAutoModeDuringPlan` が project/local で無視 | **誤り** | Scope は `User, local, or managed`。**無視されるのは project だけ** | L86529, L87139 |
| `modelPicker` が project/local で無視 | **正しい** | Scope は `User or managed` | L86419, L86793 |
| `pluginConfigs` が project/local で無視 | **正しい** | Scope は `User or managed` | L86435, L90265 |
| `network.strictAllowlist` 等のセキュリティ系 | **キー名が誤り** | 正しくは `sandbox.network.strictAllowlist`、Scope は `User or managed` | L86488 |

### 3.2 project / local に書いても効かないキー（Scope ≠ `Any file`）

Settings index（L86314–L86543）の Scope 列から機械的に抽出。

#### `Managed` のみ（user / project / local / `--settings` すべて無視）

| 分類 | キー | 行 |
|---|---|---|
| permission | `allowManagedPermissionRulesOnly` | L86325 |
| hooks | `allowManagedHooksOnly` | L86323 |
| MCP | `allowAllClaudeAiMcps` / `allowManagedMcpServersOnly` / `managedMcpServers` | L86319, L86324, L86413 |
| plugin | `allowedChannelPlugins` / `blockedMarketplaces` / `channelsEnabled` / `disableCommandPluginSources` / `pluginSuggestionMarketplaces` / `pluginTrustMessage` / `strictKnownMarketplaces` / `strictPluginOnlyCustomization`（+ `.agents` / `.hooks` / `.mcp` / `.skills`） | L86320, L86350, L86352, L86371, L86436, L86437, L86508, L86509–L86513 |
| memory | `claudeMd` | L86353 |
| model | `modelPricing` | L86420 |
| 認証 | `forceLoginGatewayUrl` | L86400 |
| version | `requiredMaximumVersion` / `requiredMinimumVersion` | L86450, L86451 |
| sideload | `disableSideloadFlags` | L86377 |
| tools / desktop | `browserExternalPageTools` / `disableBrowserExternalNavigation` / `disableMobileSimulatorTools` / `disableDesktopLocalSessions` / `sshHostAllowlist` | L86351, L86368, L86375, L86373, L86506 |
| sandbox | `sandbox.bwrapPath` / `sandbox.socatPath` / `sandbox.filesystem.allowManagedReadPathsOnly` / `sandbox.network.allowManagedDomainsOnly` | L86458, L86491, L86471, L86483 |
| 配信制御 | `forceRemoteSettingsRefresh` / `managedSourcesBehavior` / `policyHelper`（+ `.path` / `.refreshIntervalMs` / `.timeoutMs`） / `wslInheritsWindowsSettings` | L86403, L86414, L86438–L86441, L86543 |

#### `User or managed`（project **と** local の両方で無視）

`askUserQuestionTimeout` (L86328) / `autoContinueAtUsageLimit` (L86336) / `autoMode` (L86340) / `autoMode.classifyAllShell` (L86341) / `desktopSessionCleanupPeriodDays` (L86361) / `dialogExpiry` (L86362) / `feedbackDrafts` (L86395) / `footerLinksRegexes` (L86399) / `modelPicker` (L86419) / `pluginConfigs` (L86435) / `processWrapper` (L86444) / `skipAutoPermissionPrompt` (L86498) / `spellcheck` (L86501) / `sshConfigs` (L86505) / `vimInsertModeRemaps` (L86532) / `sandbox.allowAppleEvents` (L86455) / `sandbox.credentials.allowPlaintextInject` (L86460) / `sandbox.credentials.awsPairs` (L86461) / `sandbox.credentials.sigv4` (L86464) / `sandbox.filesystem.disabled` (L86476) / `sandbox.network.strictAllowlist` (L86488) / `sandbox.network.tlsTerminate` (L86489) / `sandbox.ripgrep` (L86490)

#### `User, local, or managed`（**project だけ**無視）

| キー | 特記 | 行 |
|---|---|---|
| `skipDangerousModePermissionPrompt` | 「信頼していないリポジトリが確認ダイアログを飛ばせないようにする」 | L86499, L87342 |
| `syncClaudeAiSkills` | `false` のみ有効。`true` は unset と同じ | L86517, L89796 |
| `useAutoModeDuringPlan` | 「リポジトリがあなたのために off にはできない」 | L86529, L87139 |

#### `Global config`（`~/.claude.json` のみ。settings 系すべてで無視）

`autoConnectIde` (L86335, L91570) / `autoInstallIdeExtension` (L86337, L91589) / `copyOnSelect` (L86357, L91607) / `diffTool` (L86363, L91625) / `externalEditorContext` (L86390, L91657) / `permissionExplainerEnabled`（v2.1.257 で削除、L86425, L91662）/ `teammateDefaultModel`（v2.1.234 で削除、L86520, L91674）

### 3.3 「コミットしたのにチームに届かない」2 大原因（原典の整理）

BASE-D は project ファイルのキーが全員に効かない原因を 2 つに分ける（L85854–L85857）。

| 原因 | 判別法 | 例外 |
|---|---|---|
| **① Claude Code がリポジトリファイルのキーを読まない** | settings index の Scope 列が `User, local, or managed` / `User or managed` / `Managed` / `Global config` | `autoContinueAtUsageLimit` のみ例外。project ファイルが値を設定し、user / `--settings` / managed が設定していない間は「off として読む」ことはできる（L85856） |
| **② trust 待ち** | `permissions.allow` / `permissions.additionalDirectories` / `extraKnownMarketplaces` / ほとんどの `env` 値 | `deny` と `ask` は即時有効（L85857） |

### 3.4 スコープを丸ごと無効化する CLI フラグ

| フラグ | 効果 | 根拠 |
|---|---|---|
| `--setting-sources user,project,local` | 読み込む setting source をカンマ区切りで限定 | L70802 |
| `--restricted` | **managed settings と `--settings` しか読まない**。built-in ファイルツールを working directories に限定、`bypassPermissions` を拒否（v2.1.248 以降） | L70798 |
| `--safe-mode` | CLAUDE.md / skills / plugins / hooks / MCP / commands / agents / output styles / workflows / themes / keybindings / statusLine / LSP / auto memory を**全部ロードしない**。managed policy は残る（managed plugins / skills / CLAUDE.md / MCP は残らない） | L70800 |
| `--bare` | hooks / skills / commands / subagents / plugins / MCP / auto memory / CLAUDE.md の auto-discovery をスキップ。project の `env` と `awsAuthRefresh` 等は残り、`apiKeyHelper` は `--settings` からのみ | L70748, L81196 |
| `--settings` | 任意のキーを 1 セッション上書き。**`Managed` / `Global config` キーは設定できない**。ファイルは 2 MiB 以内の通常ファイル | L85706, L70803 |

### 3.5 cloud session / VS Code / Cowork でのスコープ差

| 実行形態 | 読まれるもの | 根拠 |
|---|---|---|
| cloud session（web / `claude --cloud`） | `.claude/settings.json` は読む（clone に含まれるため）。**`~/.claude/settings.json` と `.claude/settings.local.json` は読まない**。managed は **server-managed のみ**（デバイス上の `managed-settings.json` / MDM は届かない） | L85887–L85889 |
| cloud session の hooks | repo と server-managed settings 由来のみ | L73953 |
| VS Code 拡張が開始する会話の `permissions.defaultMode` | **user / managed / `--settings` のみ**を読む | L87281 |
| Cowork（Claude Desktop 内、ローカル実行） | claude.ai の server-managed settings を**fetch しない**。デバイスの MDM / ファイルポリシーは読む（`requireCoworkFullVmSandbox` 未設定時） | L85648, L30493–L30497 |

### 3.6 managed の「例外」―― 下位スコープの厳しい値が勝つキー

L85868–L85879 の表（管理者設計時に必須）。

| キー | Claude Code が尊重する値 |
|---|---|
| `disableClaudeAiConnectors` | 任意スコープの `true` |
| `enableArtifact` | 任意スコープの `false`（および `disableArtifact: true`）。**一度 off にすると何も on に戻せない** |
| `isolatePeerMachines` | 任意スコープの `true` |
| `remoteControlAtStartup` | project / local の `false`（project / local の `true` は無視） |
| `crossSessionInbound` | project / local の**より厳しい値**（`accept` < `hold` < `refuse`） |
| `useAutoModeDuringPlan` | managed / `--settings` / user / **local** の `false`（`.claude/settings.json` の `false` は無視） |
| `syncClaudeAiSkills` | 同上 |
| `maxEffortLevel` | 任意スコープのより低い上限（`--settings` 含む）。最も低い上限が適用 |

加えて、`permissions.blockReadsOutsideWorkingDirectories` は**どのスコープでも `true` なら有効**という一方向キー（L87257）。リポジトリのコミット済みファイルでプロジェクト単位に block を on にはできるが、あなたが設定した block を解除はできない。

---

## 4. settings キーではないもの（境界の明確化）

**結論: `output-styles` / `skills` / `agents` / `commands` は settings キーではなく、`.claude/` 配下の独立したファイル/ディレクトリである。** `settings.json` に同名キーは存在しない。settings index（L86314–L86543）にこれらのキーはなく、`claude-directory` のファイル一覧（L14624–L14641）に別ファイルとして列挙されている。

| `.claude/` 配下のもの | 実体 | settings キーか | 対応する settings キー（あれば） | 根拠 |
|---|---|---|---|---|
| `CLAUDE.md` | ファイル | ✕ | `claudeMd`（`Managed` 専用・組織配布用）/ `claudeMdExcludes` | L14626, L86353, L86354 |
| `rules/*.md` | ファイル | ✕ | なし | L14627 |
| `skills/<name>/SKILL.md` | ディレクトリ | ✕ | `skillOverrides`（表示制御のみ）/ `disableBundledSkills` / `disableSkillShellExecution` / `skillListing*` | L14632, L86497, L86369, L86378 |
| `commands/*.md` | ファイル | ✕ | skills と同じ機構（L14633） | L14633 |
| `agents/*.md` | ファイル | ✕ | `agent`（どの agent をメインスレッドにするかの選択のみ） | L14635, L86317 |
| `output-styles/*.md` | ファイル | ✕ | `outputStyle`（**どのスタイルを選ぶかの名前だけ**） | L14634, L86423 |
| `workflows/*.js` | ファイル | ✕ | `disableWorkflows` / `enableWorkflows` / `workflowSizeGuideline` 等 | L14636, L86379 |
| `.mcp.json` | ファイル（プロジェクトルート） | ✕ | `enabledMcpjsonServers` / `disabledMcpjsonServers` / `enableAllProjectMcpServers` | L14630, L86385, L86374, L86383 |
| `settings.json` / `settings.local.json` | ファイル | ― | 本ドラフトの対象そのもの | L14628, L14629 |
| `~/.claude.json` | ファイル | △ | **`Global config` キー専用**。settings ファイルではない。sign-in / MCP 設定 / プロジェクト単位 state を保持 | L85583, L91551 |
| `keybindings.json` / `themes/*.json` | ファイル | ✕ | なし（`theme` キーはテーマ**名**の選択のみ） | L14640, L14641, L86524 |
| `agent-memory/<name>/` | ディレクトリ | ✕ | `autoMemoryDirectory` / `autoMemoryEnabled` | L14637, L86338, L86339 |

**この境界を踏み外しやすい点**:
- `outputStyle` は**スタイル名の文字列**であって、スタイル本体（Markdown ファイル）は `.claude/output-styles/` にある（L86923, L79820–L79827）。
- `agent` も同様に**agent 名の文字列**で、定義は `.claude/agents/*.md`（L86475, L43685）。
- 各ファイル種別には settings キーとは別の「managed policy directory」配布経路がある（skills: L42260 ／ agents: L43685 ／ output-styles: L79825）。

---

## 5. 公式ページ再編に伴う旧出典の写像表

旧 `settings` ページの主要セクションが、v2.1.269 相当の BASE-D でどのページに存在するか。**BASE-D 内で見出しを検索し、`Source:` 行で区切られたどのページ範囲に入るかを確認した結果**。

| 旧 `settings` ページのセクション | 現在のページ | 現在の見出し | 行 |
|---|---|---|---|
| Settings files | `settings` | `## Settings files and who they affect` | L85539 |
| （同上・スコープ比較） | `settings` | `### Compare the scope of each settings file` | L85556 |
| Settings precedence | `settings` | `## Settings precedence` | L85764 |
| （同上・リストのマージ） | `settings` | `### Lists merge instead of overriding` | L85782 |
| **Available settings** | **`settings-reference`** | `## Settings index`（全キー索引・Scope 列つき） | L86308 |
| `enabledPlugins` | `settings-reference` | `### \`enabledPlugins\``（`## Plugins and skills` 配下） | L90132（節は L89724） |
| `extraKnownMarketplaces` | `settings-reference` | `### \`extraKnownMarketplaces\`` | L90163 |
| `pluginConfigs` | `settings-reference` | `### \`pluginConfigs\`` | L90261 |
| `strictKnownMarketplaces` | `settings-reference` | `### \`strictKnownMarketplaces\`` | L89919 |
| **Managed-only settings** | **`managed-settings`** | `## Keys only a managed source can set` | L30752 |
| （同上・別記述） | `server-managed-settings` | `### Managed-only settings`（索引への誘導のみ） | L40960 |
| **Sandbox settings** | **`settings-reference`** | `## Sandbox settings` | L87354 |

**その他、旧 `settings` ページから移った/新設された主要セクション**

| 内容 | 現在のページ | 見出し | 行 |
|---|---|---|---|
| managed settings の配信手段 | `managed-settings` | `## Choose a delivery mechanism` | L30461 |
| managed 内の優先順位 | `managed-settings` | `## How Claude Code combines managed sources` | L30537 |
| managed より厳しい下位値が勝つキー | `settings`（残留） | `### Exceptions to managed settings precedence` | L85866 |
| 設定が効かないときの切り分け | `settings`（残留） | `### Troubleshoot a setting that doesn't apply` | L85829 |
| cloud session でのスコープ | `settings`（新設と思われる） | `## Settings in cloud sessions` | L85883 |
| 1 セッションだけの変更 | `settings` | `### Change a setting for one session` | L85702 |
| `Global config` キー群 | `settings-reference` | `## Global config settings` | L91549 |
| permission rule の構文 | `permissions` ＋ `settings-reference` 両方 | `## Permission rule syntax`（L80617）/ `#### Permission rule syntax`（L87172） | L80617, L87172 |

### 5.1 旧アンカーの扱い（要注意）

BASE-D 内の他ページから、**現在の `settings` ページに存在しない見出しアンカー**へのリンクが残っている。

| 参照されているアンカー | 参照元 | 現 `settings` ページの対応見出し |
|---|---|---|
| `/docs/en/settings#where-settings-live` | L14601, L14629, L72394 | 該当見出しなし（内容は `## Settings files and who they affect` L85539） |
| `/docs/en/settings#where-claude-code-looks-for-each-file` | L81102 | 該当見出しなし（内容は `#### Where Claude Code keeps the local file in a git repository` L85615） |
| `/docs/en/settings#security-keys-where-the-stricter-value-applies` | L14585 | 該当見出しなし（内容は `### Exceptions to managed settings precedence` L85866） |

`settings` ページ本文には `<span />` だけの行が多数ある（L85525–L85537 / L85552–L85554 / L85569 / L85591–L85598 / L85609–L85613 / L85628–L85636 / L85656 / L85700 / L85733–L85735 / L85756–L85762 / L85791 / L85821–L85827 / L85864）。

> **推測**（原典に明示なし）: これらの `<span />` は旧アンカーを保持するためのアンカーコンポーネントが Markdown 化で潰れたものであり、旧アンカー URL は今もリダイレクトされる。**ただし BASE-D からは各 `<span />` がどのアンカー名を持つか判別できない。** 既存成果物の出典を書き換える際は、アンカー名ではなく**上表の見出し名**で参照し直すのが安全。

---

## 6. 確認できなかった点・原典に記載が無い点

| # | 論点 | 状態 |
|---|---|---|
| 1 | 旧 `settings` ページのセクション名の**完全な一覧**（2026-08-19 版の目次） | **原典に記載なし**。BASE-D は現行版のスナップショットのみで、旧版の目次を含まない。§5 の写像表は「タスク指示で列挙されたセクション名」を現行ページで検索した結果であり、旧版に実在したかは BASE-D では確認できない |
| 2 | `<span />` 行が保持しているアンカー名 | **BASE-D からは判別不能**（§5.1）。推測として記載した |
| 3 | 「全 237 キー」の 237 という数 | **未検証**。Settings index の表（L86314–L86543）は 229 行（`\| [\`key\`]` 形式）だが、`## Global config settings` 節のキーや別名（`allowedMarketplaces` / `additionalMarketplaces`）の数え方で変わる。本ドラフトでは数を主張しない |
| 4 | `permissions.blockReadsOutsideWorkingDirectories` の実機挙動 | **実機検証なし**（タスク制約）。原典記述（L87251–L87275）のみに依拠 |
| 5 | `--permission-prompts none` と `PermissionRequest` hook の相互作用の CLI 側記述 | CLI 側は L70788 のみ。SDK 側には「`permissionPrompts:'none'` でも `PermissionRequest` hook は判断の機会を得る。hook が決めなければ deny」との記述がある（L54496）。**CLI の `--permission-prompts none` でも同じかは原典に明示なし** |
| 6 | plugin の `settings.json` がサポートするキーの完全な一覧 | 「現在は `agent` と `subagentStatusLine` のみ」と記載（L38364）。将来拡張の有無は記載なし |
| 7 | `.claude/settings.local.json` のリポジトリルート解決が Windows で無効になる条件の詳細 | 「Windows では `.claude/settings.json` と同じ場所に置かれる」とのみ（L85621）。それ以上の詳細は記載なし |
| 8 | `--add-dir` 由来ディレクトリの `settings.json` から読まれるキーが `enabledPlugins` / `extraKnownMarketplaces` **だけ**であることの網羅性 | 表（L81097）にそう書かれている。他キーが読まれない旨の明示的な否定文は L81086 の「most `.claude/` configuration is not discovered」まで |

---

## 7. 出典一覧（BASE-D の行番号）

| ページ | `Source:` 行 | 本ドラフトで参照した範囲 |
|---|---|---|
| `claude-directory` | L14563 | L14563–L14642 |
| `managed-mcp` | L29922 | L29922–L30051 |
| `managed-settings` | L30412 | L30412–L30592, L30640–L30699, L30735–L30764 |
| `mcp` | L30820 | L31323–L31402 |
| `plugins` | L38100 | L38362–L38421, L38545–L38584 |
| `server-managed-settings` | L40849 | L40960–L41039 |
| `skills` | L42148 | L42248–L42277, L42642–L42691 |
| `sub-agents` | L43461 | L43670–L43700, L43855–L43910 |
| `hooks-guide` | L26822 | L27245–L27306, L27640–L27699 |
| `cli-reference` | L70681 | L70681–L70855 |
| `env-vars` | L72300 | L72360–L72419 |
| `hooks` | L73695 | L73930–L74000, L74330–L74440 |
| `output-styles` | L79769 | L79769–L79903 |
| `permissions` | L80531 | L81049–L81218 |
| `plugins-reference` | L81215 | L81280–L81340, L81640–L81780 |
| `settings` | L85509 | L85509–L85907（全文） |
| `settings-reference` | L86294 | L86294–L86623, L86752–L86811, L86916–L86965, L87032–L87361, L88460–L88588, L89514–L89813, L89919–L90517, L91308–L91367, L91549–L91698 |

---

## 付録: 本ドラフトのスコープ外だが設計に影響しうる論点

- **plugin subagent の機能欠落**: plugin 由来の subagent は `hooks` / `mcpServers` / `permissionMode` frontmatter を無視する（L43690）。「チーム共通 subagent を plugin で配る」設計を採る場合、これらを使う agent は plugin 化できず、`.claude/agents/` に残すか `permissions.allow`（セッション全体に効く）で代替するしかない。層2 plugin 方針の再検討材料。
- **`extraKnownMarketplaces` の `headersHelper` フィルタ**: project の `.claude/settings.json` / `settings.local.json` に置いたエントリは、ルーティング系・クライアント識別系ヘッダ名が**ドロップされる**（L90250）。`--add-dir` ディレクトリの settings からは `headersHelper` 自体が無視される（L90218）。private marketplace をリポジトリ経由で配る設計に効く。
- **`managed-settings.d/` によるポリシー分割**: 複数チームでポリシーを分担する場合、1 ファイルを共同編集せず drop-in ディレクトリに分けられる（L30518–L30531）。マージ規則（単値は後勝ち、リストは結合、`modelPicker` / `fallbackModel` / `extraKnownMarketplaces` / `managedMcpServers` は丸ごと置換）は本ドラフトの precedence 表とは別ルール。
- **`managedSourcesBehavior: "merge"`**: 既定の `first-wins` では「上位の managed source が 1 つでも policy key を持つと下位 source は丸ごと無視」される（L30541）。複数の配信経路を併用する組織では、意図せずポリシーが消える。
- **`--settings` が hooks 無効化の唯一の確実な手段**: 信頼できないリポジトリで `-p` を回す際、user settings に `disableAllHooks: true` を書いても project settings が上書きできる。`--settings '{"disableAllHooks": true}'` が必要（L81197, L74422）。CI 設計に直結。
- **`env` の適用タイミングと trust の関係**: project / local の `env` は trust 受諾後に適用されるが、**`-p` 実行では trust ダイアログが出ないため起動時に適用される**（L88489）。ヘッドレス実行のセキュリティ前提に影響。
- **`/cd` によるセッション移動**: v2.1.246 以降、`/cd` で移動先の project settings / hooks / MCP / plugins / skills / subagents / `env` が適用される（L81069–L81076）。`--add-dir` で足したディレクトリは保持されるが、`additionalDirectories` は移動先の設定のものに差し替わる（L81076）。
- **`settings.local.json` の JSON 破損の影響範囲**: BASE-D は「user / project / local ファイルの JSON が壊れると Settings Error ダイアログが出て、**そのファイル全体をスキップできる**」と記述している（L85747）。**ファイル単位でスキップされるということは、`permissions` の allow / deny も `additionalDirectories` もまとめて失われる**ということであり、症状は「設定が一部効かない」ではなく「そのスコープが丸ごと消える」になる。**共有 `settings.json` を配る運用では、編集後に JSON の妥当性検証を挟むこと。** 実機での挙動確認は本書の調査範囲外。

---

## 変更履歴

| 版 | 日付 | 内容 |
|---|---|---|
| **v1.0** | 2026-09-14 | 初版。**D-12**（公式 docs のページ再編に伴う v1.2 旧出典のページ名写像）への回答として §5 を作成し、あわせて **軸A（同じ設定を宣言できる場所と競合時の勝敗）**・**軸B（スコープ別の有効性）** を整理した。収録は全 237 キーではなく、①settings 系以外にも宣言場所がある ②スコープによって無視される ③`.claude/` の共有・配布設計に直接影響する のいずれかに当たるキーに絞っている（§1-1）。根拠は v2.0 と同じ **BASE-D 単一基準**。**実機検証は含まない** |
