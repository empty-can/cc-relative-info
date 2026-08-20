# Plugin・Marketplace 配布物の開発・テスト — 調査結果（v1.5）

> - **想定読者**: 層2（Plugin / Marketplace）で資産を配布するチームの開発担当者。「配布専用リポジトリに載せる plugin / skill を、どこで・どうやって開発しテストするのが Claude Code の標準/推奨なのか」を知りたい読み手。
> - **位置づけ**: 「ポータブルな `.claude/` のチーム共有・統制」調査（[結論・構成案 v1.2](../../01.配布・統制方針調査/結論・構成案_ポータブルな.claude共有_v1.2.md)）の **層2（Plugin / Marketplace）実務続編**。v1.2 が「**何を**どのチャネルで配れるか（資産×チャネル マトリクス）」を確定したのに対し、本書は「層2 で配ると決めた資産を **どこで・どう開発しテストするか**」を扱う。
> - **作成日**: 2026-06-21
> - **根拠ドキュメント**: Claude Code 公式ドキュメント（ローカル DL 版 `llms-full.txt`）。担当ページは `docs/plugins` / `docs/plugin-marketplaces` / `docs/plugins-reference` / `docs/skills`。本書の出典は**ページ名＋セクション**を主アンカーとする（行番号は snapshot 依存のため [§出典](#sources) に参考値として併記）。原文照合は `cc-docs-plugins-marketplace-expert`（公式 docs 原文忠実 agent）による。

---

<a id="summary"></a>

## エグゼクティブサマリ（結論の先出し）

**問い**: Marketplace（配布専用リポジトリ）で配る plugin / skill を、どこで・どのように開発・テストするのが Claude Code の標準/推奨パターンか。

**結論**: 公式は **一本道のフロー**を推奨している。

> **「まず `.claude/` のスタンドアロン設定で素早くイテレーションし、共有準備ができたらプラグイン化する」**（`docs/plugins`）

ポイントは、**開発・テストの主戦場はローカルであり、Marketplace への登録は配布段階で初めて行う**こと。開発中はマーケットプレイス登録すらせず、`--plugin-dir` フラグで plugin を直接ロードして検証する。すなわち **「開発・テスト環境」と「配布専用リポジトリ（Marketplace）」は役割が別物**であり、両者を分離するのが公式フローの前提になっている。

- **開発の主手段** = `claude --plugin-dir ./my-plugin`（marketplace 登録・install 不要でプラグインを直接ロード）
- **イテレーション** = `/reload-plugins`（再起動なし反映）／skill の `SKILL.md` はライブ変更検出
- **配布形態の検証** = ローカルディレクトリを `claude plugin marketplace add ./local-mp` で「ローカル marketplace」化し、install〜uninstall を実地確認
- **公開前ゲート** = `claude plugin validate`（提出前必須・レビューパイプラインが同じ検査を回す）

本書冒頭で確認した制約 ——「plugin が運べるのはプラグインディレクトリ単位で、`CLAUDE.md` / `rules/` / `settings.json` 等のリポジトリ統制設定そのものは plugin 配布の対象外」—— は、**層2 を選んだ時点での当然の帰結**であり（v1.2 [§マトリクス](../../01.配布・統制方針調査/結論・構成案_ポータブルな.claude共有_v1.2.md) ②と整合）、Marketplace 開発手順のスコープでは問題にならない。これらの「Marketplace で配れない資産」の開発・テストは**別調査**（本タスクの後続フェーズ）で扱う。

---

## 問い・スコープ

- **問い**: 配布専用リポジトリ（Marketplace）で配布する plugin / skill を、どこで・どのように開発・テストするのが一般的か。Claude Code としての標準・推奨パターンは存在するか。
- **スコープ内**: 層2 で配布できる資産（plugin、plugin 同梱の skills / commands / agents / hooks / MCP / LSP / bin 等、および skill 単体）の開発・テストのワークフロー・コマンド・起動オプション・検証手段。
- **スコープ外**: 層2 で配れない資産（`CLAUDE.md` / `rules/` / `settings.json` 等のガバナンス資産）の開発・テスト → 本タスクの後続フェーズで扱う。各資産がどのチャネルで配れるかの判断は v1.2 マトリクスに委譲。

---

<a id="flow"></a>

## 1. 公式が示す開発・テストフロー（全体像）

公式ドキュメントは、配布物の作成を以下の段階で説明している（`docs/plugins`）。

```
① standalone .claude/ で素早くイテレーション
        │   （まだ plugin 化しない。最速で試行錯誤する段階）
        ▼
② 共有準備ができたら plugin 化（plugin.json を付与）
        │
        ▼
③ ローカルで開発テスト
        │   主: claude --plugin-dir ./my-plugin   （marketplace 登録なしで直接ロード）
        │   副: claude plugin marketplace add ./local-mp → /plugin install   （配布形態の検証）
        │   反映: /reload-plugins ／ skill は SKILL.md ライブ検出
        ▼
④ 公開前バリデーション
        │   claude plugin validate .   （提出前必須。レビューパイプラインも同じ検査）
        ▼
⑤ 配布専用リポジトリ（Marketplace）へ push
            利用者: /plugin marketplace add <repo> → /plugin install
```

**設計上の含意**: ③ の開発テストは**ローカルで完結**し、Marketplace（⑤）は配布の器でしかない。したがって「開発・テストリポジトリ（ローカル）」と「配布専用リポジトリ（公開）」を分けるのが自然な構成になる。公式は両者の分離を明示的に強制も否定もしていないが、フロー全体がこの分離を前提に組まれている。

---

<a id="means"></a>

## 2. 開発・テストの具体手段（主 → 副）

公式が「主たる開発手段」として説明しているのは **`--plugin-dir` フラグ**であり、ローカル marketplace 登録はその次（配布形態まで含めた検証）に位置づけられる。

| 手段 | 何をするか | 主な特性 | 出典ページ |
|---|---|---|---|
| **`claude --plugin-dir ./my-plugin`**（主） | marketplace 登録・install なしでプラグインを直接ロードしてテスト | `.zip` アーカイブも可（v2.1.128+）／フラグ反復で複数 plugin 同時ロード／`--plugin-url` で CI ビルド成果物 URL からもロード可 | `docs/plugins` |
| **`claude plugin init my-tool`** | `~/.claude/skills/my-tool/` を生成し、次セッションで `my-tool@skills-dir` として自動ロード | install / marketplace 不要。`--plugin-dir` と違い毎回のフラグ指定も不要 | `docs/plugins` |
| **`claude plugin marketplace add ./local-mp`**（副） | ローカルディレクトリを marketplace として登録し、配布形態ごと検証 | `marketplace.json` 込みで install→uninstall→reinstall の実地確認に使う。`/plugin marketplace add ./...` のセッション内コマンドも等価 | `docs/plugin-marketplaces` |

### イテレーション（編集 → 反映 → 確認）

| 機構 | 反映対象 | 反映トリガ | 出典ページ |
|---|---|---|---|
| **`/reload-plugins`** | plugin・skills・agents・hooks・plugin MCP / LSP サーバ | コマンド実行（再起動不要） | `docs/plugins` |
| **skill のライブ変更検出** | `SKILL.md` の追加・編集・削除 | セッション内で**即時**（`~/.claude/skills/`・project `.claude/skills/`・`--add-dir` 配下の `.claude/skills/`） | `docs/skills` |
| （上の例外） | skill が plugin でもある場合の `hooks/`・`.mcp.json`・`agents/`・`output-styles/` 変更 | `/reload-plugins` が必要 | `docs/skills` |

### `--plugin-dir` の優先度（インストール済み plugin の上書きテスト）

同名のインストール済み marketplace plugin がある場合、**`--plugin-dir` のローカルコピーがそのセッションで優先**される。アンインストールせずに、配布中の plugin への変更をテストできる（`docs/plugins`）。
※ ただし managed settings で force-enable / force-disable された plugin はこの方法で上書きできない。

---

<a id="repo-relation"></a>

## 3. 配布専用リポジトリと開発・テスト環境の関係

### (1) standalone → plugin への昇格

公式の昇格判断（`docs/plugins`／v1.2 とも整合）:

- **standalone `.claude/`** … イテレーションが速い。試行錯誤段階・単一リポジトリ内利用に最適。
- **plugin 化** … versioned / shareable / marketplace 配布が必要になった段階で行う。

つまり「開発・テストリポジトリ（ローカル・standalone `.claude/` ベース）」で機能を作り込み、固まったら plugin 化して「配布専用リポジトリ（Marketplace）」へ載せる、という二段構えが公式の想定線。

### (2) キャッシュコピー挙動（配布時の最重要制約）

> 利用者が plugin をインストールすると、Claude Code は plugin ディレクトリを**キャッシュ場所（`~/.claude/plugins/cache`）へコピー**して使う（in-place では使わない）。（`docs/plugin-marketplaces` / `docs/plugins-reference`）

この挙動から導かれる制約:

- **配布可能な単位は「プラグインディレクトリ単位」**。plugin ディレクトリの外にあるファイル（例: `../shared-utils`）への相対参照は、コピーされないため**配布後に壊れる**。
- 従って `.claude/settings.json` / `CLAUDE.md` / `rules/` 等の**プロジェクト設定全体は plugin 配布の対象外**。
  → これは v1.2 [§マトリクス](../../01.配布・統制方針調査/結論・構成案_ポータブルな.claude共有_v1.2.md) ②（ガバナンス資産は層2 で運べない）の**裏付け**であり、Marketplace 開発手順のスコープでは制約ではなく**前提**。

### (3) monorepo / multi-repo と source 参照

- `marketplace.json` の `source: "./plugins/..."` のような相対パス参照は、**git 経由の追加**または**ローカルディレクトリとしての追加**（`claude plugin marketplace add ./my-mp` のような場合を含む）でのみ機能し、**直接 URL で `marketplace.json` を追加する URL-based marketplace では不可**（Claude Code がそのファイル単体しかダウンロードしないため）。**v2.1.235 版(2026-08-19)**: git を使わずに配布する新しい手段として、**`archive`（zip を HTTPS 配信。v2.1.224+）**と**`command`（ローカルツールが plugin ディレクトリを生成。v2.1.229+）**という source 種別も追加されている（出典 [S25](#sources)）。
- `source` フィールドは**外部リポジトリ参照**も取れるため、薄い「配布専用 marketplace リポジトリ」が、別々のプラグイン開発リポを指す **multi-repo 構成**も可能。
- 反対に全 plugin を 1 リポにまとめる **monorepo** も可。ドメイン混在・保守責任の曖昧化というトレードオフがある（公式は monorepo 向けに `git-subdir` ソース / `--sparse` 取得を用意。v1.2 案B 補足参照）。

---

<a id="skill-only"></a>

## 4. スキル単体（plugin に包まない `.claude/skills/`）の開発・テストとの差異

skill は plugin に同梱せず `.claude/skills/` 単体でも配布できる（v1.2 マトリクス①）。開発・テストの観点で plugin 同梱版と異なる点:

| 観点 | スキル単体（`.claude/skills/`） | plugin 同梱スキル |
|---|---|---|
| 開発時のロード | project / `~/.claude/` / `--add-dir` 配下に置けば自動ロード | `--plugin-dir` またはローカル marketplace install |
| ライブ変更検出 | あり（`SKILL.md` の編集は**即時反映**） | `/reload-plugins` が必要 |
| 呼び出し名 | `/hello`（短いコマンド名） | `/plugin-name:hello`（名前空間付き） |
| hooks / MCP の同梱 | 不可 | 可能 |
| 配布チャネル | バージョン管理へ commit（層1） | Marketplace 経由（層2） |

### skill 開発を支援する純正ツール

- **`skill-creator` プラグイン**（純正）… skill の eval ループを自動化（テストケース `evals/evals.json` 蓄積／テストケース毎に subagent を spawn する隔離実行／アサーション照合の採点 `grading.json`／skill 有無の pass 率・時間・token を比較する `benchmark.json`／2 版の blind A/B＝version comparison／description tuning／HTML の review viewer）。`/plugin install skill-creator@claude-plugins-official`（`docs/skills`）。**v2.1.235 版(2026-08-19)**: `claude-plugins-official` はマシン初回の**対話起動時**に自動登録される。CI・非対話（ヘッドレス）環境で先に実行すると未登録のことがあり、その場合は `claude plugin marketplace add anthropics/claude-plugins-official` で事前登録する（出典 [S23](#sources)）。
  - 公開リソース（英語・日本語版未確認）: 本体 `https://github.com/anthropics/claude-plugins-official/tree/main/plugins/skill-creator`／README `https://github.com/anthropics/claude-plugins-official/blob/main/plugins/skill-creator/README.md`／eval 形式 `https://agentskills.io/skill-creation/evaluating-skills`／公式ブログ `https://claude.com/blog/improving-skill-creator-test-measure-and-refine-agent-skills`
- **`claude plugin init <name>`** … `~/.claude/skills/<name>/` を scaffold（雛形生成。`.claude-plugin/plugin.json` ＋ starter `SKILL.md` を生成、次セッションで `<name>@skills-dir` ロード）。

### `--add-dir` と skill の関係（テスト時に有用）

`--add-dir` / `/add-dir` は本来「ファイルアクセス権の付与」であり設定の自動探索はしないが、**いくつかの構成要素は例外として `<dir>/.claude/` から自動ロードされる**（`docs/permissions` の表）:

| 構成 | `--add-dir` から自動ロード |
|---|---|
| skills（`.claude/skills/`） | ✅ live reload |
| **subagents（`.claude/agents/`）** | ✅（v2.1.178+。v2.1.165 までは非ロード） |
| **commands（`.claude/commands/`）** | ✅（**v2.1.235 版(2026-08-19) で追加**。ライブリロードなし。追加ディレクトリとプロジェクト側で同名 command がある場合はプロジェクト側が優先される） |
| `settings.json` の `enabledPlugins` / `extraKnownMarketplaces` | ✅（この2キーのみ） |
| `CLAUDE.md` / `.claude/rules/` / `CLAUDE.local.md` | △ `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` を付けた時のみ |
| `settings.json` のそれ以外（permissions/hooks 等）・output-styles | ❌ |

> **正本**: 版依存の事実（subagents の版境界・commands の追加時期・`settings.local.json` を含む2キー例外）は [v1.2 付録B『`--add-dir` 例外ロード一覧（正本）』](../../01.配布・統制方針調査/結論・構成案_ポータブルな.claude共有_v1.2.md#adddir-exceptions) を正とする（本表は運用早見）。

※ これら例外は **`--add-dir` フラグ／`/add-dir` コマンド限定**。`permissions.additionalDirectories` 設定経由では一切ロードされず、ファイルアクセス付与のみ。
→ 開発・テストリポジトリ（ローカル）と作業リポジトリを**結合してテスト**する際、**skill と subagent** はこの `--add-dir` 例外で結合できる。`CLAUDE.md` / `rules` は環境変数併用、`settings.json` の大半は別経路（v1.2 案C）。

---

<a id="validate"></a>

## 5. 検証・デバッグ（公式の注意点）

| 手段 | 用途 | 検出内容 | 出典ページ |
|---|---|---|---|
| **`claude plugin validate .`**（`/plugin validate .`） | 公開前バリデーション（**公開審査のある Marketplace への提出時は必須／private な独自 Marketplace では推奨**） | marketplace ディレクトリ対象時: `marketplace.json` の schema・重複 plugin 名・source のパストラバーサル・各 `plugin.json` とのバージョン不整合／plugin ディレクトリ対象時: skill・agent・command・hook の frontmatter、`hooks/hooks.json` の JSON 構文 | `docs/plugins` / `docs/plugin-marketplaces` |
| **`claude --debug`** | 汎用デバッグログ（**ロード時専用ではない**） | plugin の場合はロード詳細（どの plugin がロードされたか・manifest エラー・skill/agent/hook 登録・MCP 初期化）。加えてロード後の実行時イベントも対象。**v2.1.235 版(2026-08-19)**: カテゴリを絞る場合は**`=` 結合形が必須**（例: `--debug='mcp,startup'`）。スペース区切り（例: `--debug mcp`）は**フィルタとして機能せず、単にデバッグモードを有効化するだけ**。hook 評価の詳細は `CLAUDE_CODE_DEBUG_LOG_LEVEL=verbose` で粒度を上げて確認する。出力先は **`~/.claude/debug/<session-id>.txt`**（セッション単位のファイル） | `docs/plugins-reference` ほか／`docs/cli-reference`「CLI flags」 |
| **`/plugin` の Errors タブ** | ロードエラーの確認 | LSP サーバのパスエラー等 | `docs/plugins-reference` |

> **validate の必須/推奨の別**: 公開審査のある Marketplace（本家 `claude-plugins-official` / コミュニティ）では、レビューパイプラインが提出ごとに `claude plugin validate` と同じ検査＋自動セーフティスクリーニングを回す（`docs/plugins`）ため、ローカルで通しておくことが提出の前提＝**実質必須**。一方 **private な独自 Marketplace（チーム内に閉じる）には審査パイプラインが無いため必須ではない**が、schema・構造・バージョン不整合をローカル/CI で弾けるので**推奨**。
>
> **`--strict` オプション（実機確認）**: `claude plugin validate <path> --strict` は警告をエラー扱いにし（未承認フィールド・メタデータ欠落等で exit 1）、CI に組み込む用途に向く。
>
> **実機で確認した manifest の必須事項（写経で詰まりやすい点）**: `plugin.json` の `author` は**オブジェクト型**必須（`{"name": ...}`。文字列だと `expected object, received string` で失敗）。`marketplace.json` の `owner` は**必須・オブジェクト型**（欠けると `expected object, received undefined` で失敗）。

---

<a id="plugin-dev"></a>

## 6. 純正の plugin 開発支援ツールキット: `plugin-dev`

公式マーケットプレイスリポジトリ `anthropics/claude-plugins-official` に **`plugin-dev`（"Plugin Development Toolkit"）** が同梱されている。manifest（`plugin.json`）の author は **Anthropic**（README の author 表記は Daisy Hollman〔Anthropic〕、README 記載 version 0.1.0。manifest に version フィールドは無い）。**公式 docs にはカタログ掲載レベルの言及はある**——`discover-plugins` ページの "Development workflows" に「**plugin-dev**: Toolkit for creating your own plugins」と1行、`plugins-reference` に名前空間の例 `plugin-dev:agent-creator`。**ただし機能の詳細を解説したページは docs に無く、以下の内容の出所は plugin 同梱の README とコマンド/agent 定義ファイル**（`https://github.com/anthropics/claude-plugins-official/tree/main/plugins/plugin-dev`）である。

**位置づけ**: hooks / MCP 統合 / plugin 構造 / marketplace 公開のベストプラクティスを与える**純正の plugin 開発支援ツールキット**。前回「未裏取り」としたコミュニティ説（"plugin-development"）の実体。

**構成（実ファイルで確認）**: `commands/create-plugin.md`（8 フェーズ workflow 本体）／`agents/`（`agent-creator`・`plugin-validator`・`skill-reviewer` の3本）／`skills/`（7本）。

**7つの専門 skill**（関連する質問をすると自動ロード＝progressive disclosure）: `plugin-structure`（構造・manifest・auto-discovery）／`skill-development`（skill 作成・skill-creator 方法論を適応）／`agent-development`（AI 支援生成）／`hook-development`（全 hook イベント・prompt/command hook）／`mcp-integration`（stdio/SSE/HTTP/WebSocket・認証）／`plugin-settings`（`.claude/<plugin-name>.local.md` での設定保存）／`command-development`（**レガシー `commands/` 形式専用**）。

**ガイド付きワークフローコマンド `/plugin-dev:create-plugin [説明]`** — plugin をゼロから作る **8 フェーズ**の対話型。主要な意思決定点でユーザー確認を待つ（`allowed-tools`: Read/Write/Grep/Glob/Bash/TodoWrite/AskUserQuestion/Skill/Task）:

| # | フェーズ | 要点 |
|---|---|---|
| 1 | Discovery | plugin の目的・対象・課題を確定 |
| 2 | Component Planning | 必要コンポーネントを表で提示し承認（`plugin-structure` をロード） |
| 3 | Detailed Design & 質問 | 各コンポーネント詳細設計（**CRITICAL・省略禁止**） |
| 4 | Structure Creation | 名前・配置場所決定、`plugin.json`/README/`.gitignore`/git init 作成 |
| 5 | Component Implementation | コンポーネント別 skill をロードして実装（`agent-creator` で agent 生成） |
| 6 | Validation & Quality | `plugin-validator`／`skill-reviewer` agent ＋検証スクリプトで検査 |
| 7 | Testing & Verification | **`cc --plugin-dir <path>` で導入**し、skill 発火・`/plugin-name:skill`・agent・hook（`claude --debug`）・MCP（`/mcp`）を確認 |
| 8 | Documentation & Next Steps | README 完成度確認、（公開時）`marketplace.json` エントリ追加、サマリ |

**検証 agent（3本）**: `agent-creator`（identifier・whenToUse 例・systemPrompt を生成）／`plugin-validator`（manifest・構造・命名・コンポーネント・セキュリティを検査）／`skill-reviewer`（description 品質・progressive disclosure・writing style を検査）。
**検証スクリプト（6本）**: `validate-hook-schema.sh` / `test-hook.sh` / `hook-linter.sh` / `validate-settings.sh` / `parse-frontmatter.sh` / `validate-agent.sh`。

**install / 開発**: README は `/plugin install plugin-dev@claude-code-marketplace`、開発時は `cc --plugin-dir /path/to/plugin-dev`。**※ marketplace 名は公式 docs（skill-creator）の `claude-plugins-official` と README の `claude-code-marketplace` で表記差があり、install 時に要確認**（docs のカタログ文脈は `claude-plugins-official`）。**`claude-plugins-official` の自動登録条件（マシン初回の対話起動時。CI・非対話環境は要事前登録）は [§4](#skill-only) を参照**。

**重要な副次知見（`commands/` のレガシー化）**: `create-plugin` の Phase 2/5 は明示的に「**`commands/` ディレクトリはレガシー形式。新規のユーザー起動スラッシュコマンドは `skills/<name>/SKILL.md` で作るべき**（両者はロード挙動が同一でファイルレイアウトのみ差。`commands/` は既存 plugin 保守時の許容レガシー）」と述べる。v1.2 の「新規は skills 推奨」を純正ツールが裏付ける。

**本書フローへの含意**: plugin-dev は**本書 §1 の開発・テストフローを置換しない**。`create-plugin` の Phase 7 自身が「ローカルテストは `cc --plugin-dir`」「hook は `claude --debug`」「MCP は `/mcp`」と案内しており、`--plugin-dir` / `--debug` / `validate` という本書の中核手段を**前提に、その上に AI 支援のスキャフォールドとベストプラクティス指南・対話的 questioning を載せる accelerator**である。標準フローは §1 のままで、plugin-dev は「より速く・型に沿って・抜け漏れなく作る」任意の上位ツール。

> **`skill-creator` との棲み分け**: `skill-creator` = **skill 単体**の eval・測定（test / measure / refine）。`plugin-dev` = **plugin 全体**の作成支援（hooks / MCP / 構造 / command / agent / skill を横断）。両者は補完関係。

---

<a id="cache-constraints"></a>

## 7. plugin 配布時のパス解決・可変状態・同梱物アクセス（実装制約）

> 本節は §3(2) のキャッシュコピー挙動を **skill 同梱の補助ファイル（references/・templates/・scripts/・README）** へ敷衍し、**「フォルダごと配布可」でも構成要素ごとに cache 先で使えない／書けない／ユーザに見えない制約がある**ことを原文照合で確定する。実 skill の plugin 化テストで顕在化した論点で、[手順書 §8](./Plugin開発・テスト_手順書.md#impl-rules) の根拠。出典はページ名＋セクション主体（行番号は現行 snapshot の参考値・[§出典](#sources) S16〜S20）。

### (1) パス解決 — `${CLAUDE_SKILL_DIR}` / `${CLAUDE_PLUGIN_ROOT}`

- 公式は **3 つのパス変数 `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_SKILL_DIR}` / `${CLAUDE_PLUGIN_DATA}`** を提供し、**skill 本文・agent 本文・hook command・monitor command・MCP/LSP config のいずれでもインライン置換**され、さらに **hook プロセス・MCP/LSP サーバ subprocess には環境変数として export** される（`docs/plugins-reference`「path variables」）。
- **skill 同梱ファイル（references/・templates/・scripts/）の参照は `${CLAUDE_SKILL_DIR}` が公式推奨**。SKILL.md のあるディレクトリ（plugin skill では plugin root でなく skill サブディレクトリ）に解決され、**personal / project / plugin のどこに置かれても正しく解決**される。SKILL.md 本文に `python3 ${CLAUDE_SKILL_DIR}/scripts/foo.py` と書けば実行前に絶対パスへ置換される（`docs/skills`「Available string substitutions」／codebase-visualizer 例）。
- **スクリプト内部から env で読めるのは hook / MCP / LSP 起動プロセスに限る**（上記 export 対象）。**skill 手順で Claude が Bash ツール実行**するスクリプトは env 注入が保証されないため、SKILL.md 側の `${CLAUDE_SKILL_DIR}` 置換で絶対パスを引数に渡すか、スクリプトが自身位置（`__file__` 等）から相対解決する。※この env は **子プロセスの OS 環境変数**であり `settings.json` の `env` 要素ではない（`env` は OS 環境変数でも settings.json でも設定可・前者が唯一の採用元ではない）。
- plugin root 外への `../` 参照は cache にコピーされず壊れる（`docs/plugins-reference`「Path traversal limitations」。§3(2) と整合）。

### (2) 書き込み・可変状態 — cache は ephemeral、`${CLAUDE_PLUGIN_DATA}` を使う

- **`${CLAUDE_PLUGIN_ROOT}` 配下（cache）に state を書いてはならない**。更新でパスが変わり、旧バージョン dir は**約14日後**に削除（orphaned 化し Glob/Grep 対象からも除外）。公式が "treat it as ephemeral … do not write state here" と明記（`docs/plugins-reference`「Plugin caching and file resolution」）。**v2.1.235 版(2026-08-19)**: 削除猶予は旧版の約7日から**約14日へ倍増**し、加えて**最後の1個の plugin をアンインストールすると掃除処理自体が止まり、次に何か plugin を入れるまで orphaned dir が残り続ける**という条件が付いた（出典 [S21](#sources)）。
- 永続させる可変データ（ナレッジ蓄積・生成物・キャッシュ等）は **`${CLAUDE_PLUGIN_DATA}`（`~/.claude/plugins/data/{id}/`・更新をまたいで残る・初回参照時に自動作成・最終スコープからの uninstall 時に削除〔`--keep-data` で保持〕）**かプロジェクト側に置く。**ただし Node.js の依存（npm/Bun）は例外（v2.1.235 版(2026-08-19)）**: `package.json` と対応するロックファイル（`npm-shrinkwrap.json`/`package-lock.json`/`bun.lock`/`bun.lockb`）を plugin ルートに同梱しておけば、marketplace 経由の install/update 時に Claude Code が cache 配置時に自動インストールする（`--ignore-scripts`・lifecycle script は実行されない）。yarn/pnpm ロックファイルや lifecycle script が必要な依存、Python の依存は自動化の対象外のため、従来どおり hook から `${CLAUDE_PLUGIN_DATA}` へインストールする（出典 [S24](#sources)）。
- 含意: skill が「同梱 references/ に追記してナレッジ蓄積」する設計は cache では成立しない。**同梱 references/ は読み取り専用の初期データ**とし、可変分は分離する。

### (3) 同梱ドキュメント（README・references）のユーザアクセス

- plugin 同梱の `README.md`・references/ は cache にコピーされるが、**`/plugin`・`claude plugin` 系から本文を閲覧する公式 UI は無い**。`claude plugin details` はコンポーネント一覧とトークンコスト表示、Discover タブの詳細ペインも "commands and skills it provides" の一覧で、本文ではなく **homepage URL の参照を案内**する（`docs/discover-plugins`）。README は同梱を推奨されるが（`docs/plugins`）、**閲覧導線は plugin の `homepage`/`repository` フィールド（配布元リポジトリ）**が公式想定。
- 含意: ユーザが読む README は配布元リポジトリ（`homepage`/`repository` で提示）に置く。skill が処理中に使う references/ は Claude がオンデマンドロードするのでユーザ手動アクセスは原則不要。**ユーザが読む／編集するファイルは plugin 同梱（読み取り専用 cache）に不向き**で、プロジェクト側（層1）か `${CLAUDE_PLUGIN_DATA}` へ寄せる。

### (4) `skills/<name>/` 構成要素別の配布挙動

plugin ディレクトリ全体が cache にコピーされるため、`skills/<name>/` 配下のサブフォルダ（references/・templates/・scripts/）や `README.md` はコピーされ実行時に参照可能。ただし構成要素で扱いが異なる:

| 構成要素 | cache コピー | 制約 |
|---|:---:|---|
| `SKILL.md` | ○（ロード） | パスは `${CLAUDE_SKILL_DIR}` で記述 |
| `references/`・`templates/` | ○ | 参照のみ（読み取り）。追記先に使わない（(2)） |
| `scripts/*` | ○ | cwd 非依存で実装、書き込みは `${CLAUDE_PLUGIN_DATA}`／プロジェクト |
| `README.md` | ○ | UI 閲覧不可。ユーザ向けは `homepage`/repo（(3)） |
| plugin root `CLAUDE.md` | ○ | **コンテキスト自動ロードされない**（`docs/plugins-reference`）。指示は skill 化 |

> **v1.2 マトリクスへの含意**: [§マトリクス](../../01.配布・統制方針調査/結論・構成案_ポータブルな.claude共有_v1.2.md) ① の「`skills/` ✅ 層2」は**フォルダが配布される**ことを示すが、**中身が cache 先でそのまま機能する保証ではない**。本節の制約を v1.2 側にも脚注として反映済み。

---

<a id="implications"></a>

## 8. v1.2（層2）との接続・含意

- 本書のフロー（standalone で開発 → 固まったら plugin 化 → ローカル `--plugin-dir` でテスト → validate → Marketplace へ push）は、v1.2 が「層2 へ寄せる」と判断した**機能・拡張資産**の実装・配布ライフサイクルそのものに対応する。v1.2 案B〜B'''（marketplace 型／インライン宣言型／`@skills-dir` 型／seed 焼き込み型）の**どれを選ぶかに依らず、開発・テスト段階は共通してローカル `--plugin-dir` / ローカル marketplace で回す**。
- **最大の制約 = 配布単位はプラグインディレクトリ単位**で、`CLAUDE.md` / `rules/` / `settings.json` 等のリポジトリ統制設定は plugin 配布外、という点は v1.2 マトリクス②の裏付けであり、Marketplace 開発スコープでは前提。これら「Marketplace で配れない資産」の開発・テストは、本タスクの**後続フェーズ（`02.Marketplace外資産編` 想定）**で扱う。
- 後続フェーズの**作業仮説**（本書の知見からの推測・要検証）: 「公開の配布用リポジトリと開発・テストリポジトリは別（後者はローカル）」「テストは `--add-dir` 等で配布用リポと開発・テストリポを結合して実施」という構図は、**skill と subagent については本書で裏付け済み**（`--add-dir` 配下の `.claude/skills/`・`.claude/agents/` は自動ロード）。一方 `CLAUDE.md` / `rules/` / `settings.json`（の大半）は `--add-dir` 単体では結合されず、別経路（環境変数 / `--settings` / clone 後の物理配置）になる（v1.2 案A パターン2・案C）。後続フェーズはこの差を軸に整理する。
- **補足（改善機会・v2.1.235 版(2026-08-19)）**: `name` と `dependencies` のみを持つ「バンドル plugin」（他 plugin への依存だけを宣言する空の plugin）を作ることで、複数の plugin を 1 回の `claude plugin install` にまとめて配布できる。チームのロール別標準ツールセット（例: backend-standard = secrets-vault + deploy-kit + db-migrate + oncall-runbook）を組むのに使え、`enabledPlugins`（managed settings）でロールアウトも可能。本テーマ（.claude 共有・統制）の目的に直結する層2 実装の選択肢として、後続フェーズで検討する価値がある（出典 [S26](#sources)）。

---

<a id="single-entity"></a>

## 9. 実測: 資産形態 × 消費チャネルのロード挙動 ―― 層1 body と plugin を単一実体に畳めるか（2026-08-20）

> **問い**: v1.2 [§推奨](../../01.配布・統制方針調査/結論・構成案_ポータブルな.claude共有_v1.2.md) の 2026-08-20 追記が提起した「**層1 に body を commit しつつ同じ資産を plugin としても発行する二重管理を、単一の実体に畳めるか**」（[公式ドキュメント最新化レポート](../../01.配布・統制方針調査/レビュー/公式ドキュメント最新化レポート_2026-08-20.md) の判断事項 D-4）を、推論ではなく**実測**で確定する。あわせて同レポート D-2（実体リポの導線が実際に通るか）も本節の手法で検証した（→ (5)）。
>
> **手法**: CLI **v2.1.237**。`CLAUDE_CONFIG_DIR` を作業用ディレクトリへ向けて個人設定から隔離した（実行後に実 `~/.claude` が無汚染であることを確認済み）。証跡は **モデル出力に依存しないもの**だけを使う ―― plugin 側は `claude plugin list --json` / `claude plugin details`、skill 側は `claude -p … --debug` の**起動ログ**。**設定・plugin・skill のロードは認証より前に走るため、隔離環境が `Not logged in` で終了しても起動ログは完全に残り、API 呼び出しは発生しない**（非対話で取れる権威ある証跡）。
>
> project scope の trust ゲートは対話必須なので、公式が案内する手動 trust（`~/.claude.json` の `projects["<リポジトリルート>"].hasTrustDialogAccepted` を `true` にする。出典 [S29](#sources)）で pre-seed した。**未 trust のセルを対照に残し、pre-seed の前後で挙動が変わることを positive control として確認**している（[レーンA確定書 §10-bis](../../04.資産インベントリ・統合/04.ランチャースクリプト実装/配布・リリース設計確定_レーンA.md)「守れたを主張する検査には対照実験を付ける」に従う）。

<a id="three-forms"></a>

### (1) 資産の 3 形態

| 形態 | 実体 | 備考 |
|---|---|---|
| **素の skill** | `<skills-dir>/<name>/SKILL.md` | 層1 でそのまま配る形。呼び名は `/<name>` |
| **案B''（`@skills-dir`）** | 上に `.claude-plugin/plugin.json` を**足しただけ** | ディレクトリは移動しない。`<name>@skills-dir` として **marketplace も install もネットワークも不要**でロードされる |
| **plugin ツリー** | 独立した `<plugin>/` に `skills/` `agents/` `hooks/` 等を持つ | 従来の層2 の形。marketplace / `--plugin-dir` で配る |

### (2) ロード挙動マトリクス（実測・CLI v2.1.237）

| # | 資産形態 | 消費チャネル | 実測結果 |
|---|---|---|---|
| 1 | 素の skill | project（cwd 直下の `.claude/skills/`） | 素の skill としてロード（`project: 1`）。呼び名 `/<name>` |
| 2 | 素の skill | `--add-dir` | 素の skill としてロード（`additional: N`） |
| 3 | **案B''** | project・**未 trust** | **plugin としてロードされない**。`claude plugin list` は `(suppressed)@skills-dir` / `enabled:false` と、trust 受諾後に `/reload-plugins` せよという明示 note を返す |
| 4 | **案B''** | project・**trust 済** | `<name>@skills-dir` が `enabled:true`。`installPath` は**現物のパス**（cache へコピーされず **in place** で読まれる）。**同時に SKILL.md は素の project skill としてもロードされる**（`project: 2`）＝**呼び名 `/<name>` は変わらない** |
| 5 | **案B''** | `--add-dir` | **plugin としてはロードされない**（`Found 0 plugins`）。一方 SKILL.md は `additional` として**素の skill のままロードされる** ＝ **manifest の追加は `--add-dir` 経路を壊さない（非破壊）** |
| 6 | **案B''** | `--plugin-dir <そのフォルダ>` | plugin としてロード（開発ループはそのまま使える） |
| 7 | **案B''** | marketplace install（`git-subdir` で `<repo>/.claude/skills/<name>` を直接参照） | **成功**。cache には sparse clone で**その サブディレクトリだけ**が入る（`.claude-plugin/plugin.json` と `SKILL.md` のみ）。version は `plugin.json` の値 |
| 8 | manifest 無しのフォルダ | marketplace install（`git-subdir`） | **install 自体は成功する**が **version を持たない**（cache パスが commit SHA 由来の `<sha>-<hash>` になる）→ `claude plugin tag` による版管理レールに乗らない |
| 9 | **案B''** | `.claude` が**ネストした git リポジトリ**（＝ C-BDC を submodule にした利用形態） | **外側リポジトリの trust だけで project scope としてロードされる**（`enabled:true`）。submodule 用の別 trust は要らなかった |
| 10 | **案B''** | 層1（リポジトリを checkout）と層2（同名 plugin を install）を**同時に**持つ | `@skills-dir` 側が **`enabled:false` に自動抑止される**（同名衝突）。**ただし素の project skill は残る**ため、`/<name>`（素）と `/<name>:<skill>`（plugin）が**同じ内容で二重に context へ載る** |

### (3) D-4 の結論 ―― 「単一実体には畳める。単一の消費形態にはならない」

- ✅ **物理的な二重化は解消できる**。`.claude/skills/<name>/` に `plugin.json` を 1 個足し、marketplace 側は `git-subdir`（出典 [S27](#sources)）でその**サブディレクトリを直接指す**ことで、**plugin ツリーへのコピーも、別リポジトリへの publish も不要**になる（セル 7）。同じ 1 ディレクトリが層1 body・`@skills-dir` plugin・marketplace plugin の**3 通りに消費される**。
- ✅ **既存利用者に対して非破壊**。`plugin.json` の追加後も、素の skill としての呼び名 `/<name>` は project 経路でも `--add-dir` 経路でも変わらない（セル 4・5）。**ランチャー（パターン2）の `--add-dir` レールは壊れない**。
- ⚠ **`@skills-dir` としての恩恵は「trust 済みの project」でしか得られない**（セル 3）。未 trust では plugin 扱いにならず、`--add-dir` 経由では plugin にならない（セル 5）。したがって **B'' は「素の skill の上位互換」であって「素の skill の置き換え」ではない**。
- ⚠ **層1 と層2 を同時に入れさせてはならない**（セル 10）。plugin 同士の衝突は CLI が抑止するが、**素の project skill と plugin skill は共存してしまう**。公式も「plugin へ移行したら `.claude/` 側の原本は消せ」と明記している（出典 [S30](#sources)）。**配布側は「層1 で使うか層2 で使うか」を利用者に一つ選ばせる設計にする**。
- ⚠ **呼び名は消費形態で変わる**。層1 なら `/<name>`、marketplace 経由なら `/<plugin>:<skill>`（frontmatter の `name` が最終セグメントになり、衝突が無ければ bare 形も併用できる。出典 [S28](#sources)）。ドキュメント・教育資料は**両方の呼び名を併記**する必要がある。

> **含意（dual 判断への影響）**: [配布計画 §4 判断 #1](../../04.資産インベントリ・統合/02.配布計画/配布計画_Plugin可否とリポジトリ割当.md) の **dual（body と plugin の両方に存在させる）は維持できるが、「両方に**実体**を置く」必要はなくなった**。実体は 1 つ、参照が 2 通り、という形に畳める。

### (4) `git-subdir` が変えるトポロジ

- `git-subdir`（出典 [S27](#sources)）は **任意の git リポジトリの任意のサブディレクトリ**を plugin として参照でき、sparse・partial clone でその部分だけを取得する。つまり **「plugin がどのリポジトリに住むか」と「どの marketplace から配るか」が完全に分離**される。
- 結果として、**配布専用 marketplace リポジトリは `.claude-plugin/marketplace.json` 1 ファイルだけでも成立する**（`plugins/` の実体を持たなくてよい）。[配布計画 §4 判断 #2](../../04.資産インベントリ・統合/02.配布計画/配布計画_Plugin可否とリポジトリ割当.md) の「C-MKT は薄い配布リポ」という確定を、**コピーを一切伴わない形で**実現できる。
- **plugin の引っ越しコストが下がる**点も重要。資産が育って独立リポジトリへ移したくなったら、marketplace エントリの `url` / `path` を書き換えるだけで済み、利用者側の `plugin install` 名は変わらない。**「どのリポジトリで開発するか」の判断を後から取り消せる**ということで、初期の選択を軽くする。

### (5) D-2 の実測 ―― 実体リポジトリの層2 レールは「まだ通っていない」

同じ隔離環境で、**実体リポジトリの現物**（`base-dev-kit-for-cc` の `scripts/publish-plugin.sh` と `marketplace-for-cc`）を対象に導線を通した。**push 先は作業用の bare クローンで、実リポジトリと GitHub には一切触れていない。**

| 検証 | 結果 |
|---|---|
| 素の C-MKT に `marketplace add` | **失敗**。`Marketplace file not found at …\.claude-plugin\marketplace.json` ＝ **C-MKT はまだ marketplace として成立していない**（骨格のみ・greenfield という [インベントリ §0](../../04.資産インベントリ・統合/01.全マシン資産インベントリ/配布可能資産インベントリ.md) の記述と一致） |
| `publish-plugin.sh --plugin .claude/skills/commit-and-pr` | **中止**。`plugin.json が無い（plugin ではない?）` ＝ **現行の skills は publish-plugin にそのままでは乗らない**。`plugin.json` の付与（＝**案B'' 形状**）が前提になる |
| `plugin.json` を付与した ref で再実行 | `validate --strict` パス → ミラー → commit → push まで**完走**（7 点の防御は現状のまま機能した） |
| ただし非対話実行 | **ハングする**。§4 の `read -r -p "→ … /security-review を実行済みなら y で続行: "` が対話必須で、CI・ヘッドレスでは stdin に `y` を流さない限り止まる |
| `marketplace.json`（相対 source `./plugins/commit-and-pr`）を置いて再試行 | `marketplace add` → `install commit-and-pr@<mp>`（version 1.0.1）まで**成功** |

> **結論**: 実体リポジトリに [§3(3)](#repo-relation) と同型の**構造欠陥（相対 `source` の解決失敗）は無かった**が、そもそも **C-MKT に `marketplace.json` が無く層2 レールは未開通**であり、**現行 skills は plugin.json を持たないため copy 型レール（`publish-plugin`）にも乗らない**。C-MKT の立ち上げは [配布計画 §5 手順3](../../04.資産インベントリ・統合/02.配布計画/配布計画_Plugin可否とリポジトリ割当.md) の作業として残る。`publish-plugin.sh` の非対話ハングは**本テーマのスコープ外の実装課題**として記録に留める（本タスクでは C-BDK のスクリプトを変更していない）。

---

<a id="sources"></a>

## 出典

根拠は Claude Code 公式ドキュメントのローカル DL 版 `llms-full.txt`（`docs/` 配下を 1 ファイルに連結したもの。実体パスは `CLAUDE.local.md` 参照）。本書は**ページ名＋セクション**を主アンカーとし、行番号は snapshot 依存のため参考値として併記する（v1.2 の出典一覧とは snapshot/行番号が一致しない可能性があるため、ページ名で照合すること）。原文照合は `cc-docs-plugins-marketplace-expert` agent による。

| # | 主張 | ページ | 参考行 |
|---|---|---|---|
| S1 | `--plugin-dir` で marketplace 登録なし直接ロード／`.zip`（v2.1.128+）／複数指定／`--plugin-url` | `docs/plugins` | 27839・27845・27867 |
| S2 | `claude plugin init` → `~/.claude/skills/<name>/` 生成 → `<name>@skills-dir` 自動ロード | `docs/plugins` | 27708 付近 |
| S3 | `claude plugin marketplace add ./local-mp`／ローカル marketplace の事前テスト | `docs/plugin-marketplaces` | 26991 付近・13669 付近 |
| S4 | `/reload-plugins` の反映対象（plugin/skill/agent/hook/MCP/LSP） | `docs/plugins` | 27853 付近 |
| S5 | skill の `SKILL.md` ライブ変更検出と、plugin 同梱時の例外（`/reload-plugins` 要） | `docs/skills` | 32741・32744 |
| S6 | `--plugin-dir` の優先度（インストール済み同名 plugin の上書きテスト・managed は不可） | `docs/plugins` | 27851 付近 |
| S7 | 「standalone `.claude/` で素早く反復、共有準備で plugin 化」 | `docs/plugins` | 27567 付近 |
| S8 | install 時に plugin を `~/.claude/plugins/cache` へコピー／`../` 外部参照不可 | `docs/plugin-marketplaces` / `docs/plugins-reference` | 26557・63470 付近 |
| S9 | `source: "./..."` 相対参照は git 経由のみ（URL-based 不可）（**v2.1.235 版でローカルディレクトリ追加でも可と明確化・`archive`/`command` 新設 → S25**） | `docs/plugin-marketplaces` | 26710 付近 |
| S10 | skill の配布スコープ（project commit / plugin / managed） | `docs/skills` | 33231 付近 |
| S11 | `skill-creator` プラグイン（eval ループ自動化） | `docs/skills` | 33208 付近 |
| S12 | `--add-dir` 配下の `.claude/skills/` は自動ロード（`additionalDirectories` 設定は対象外） | `docs/skills` | 32771 付近 |
| S13 | `claude plugin validate`（提出前必須・検査内容・レビューパイプライン） | `docs/plugins` / `docs/plugin-marketplaces` | 27914・27423・27425 |
| S14 | `claude --debug` / `/plugin` Errors タブ | `docs/plugins-reference` | 63864・63017 付近 |
| S15 | `plugin-dev` の docs カタログ掲載（"Development workflows"）＋名前空間例 | `docs/discover-plugins`（13524 付近）／`docs/plugins-reference`（13210 付近） | — |
| S16 | パス変数3種（`CLAUDE_PLUGIN_ROOT`/`CLAUDE_SKILL_DIR`/`CLAUDE_PLUGIN_DATA`）は skill/agent 本文・hook/monitor command・MCP/LSP config でインライン置換＋hook/MCP/LSP subprocess へ env export | `docs/plugins-reference`（path variables） | 63695 付近 |
| S17 | `${CLAUDE_SKILL_DIR}` で skill 同梱スクリプト/ファイルを参照（personal/project/plugin で解決） | `docs/skills`（Available string substitutions / codebase-visualizer 例） | 32800・33163・33181 付近 |
| S18 | cache は ephemeral・"do not write state here"・旧版は約7日後に削除（**v2.1.235 版で約14日に変更・最後の plugin アンインストール時は掃除停止 → S21**）・Glob/Grep 除外／`../` 外部参照不可 | `docs/plugins-reference`（Plugin caching and file resolution / Path traversal limitations） | 63695-63697・63776・63778・63784 付近 |
| S19 | `${CLAUDE_PLUGIN_DATA}` = `~/.claude/plugins/data/{id}/`・更新をまたいで永続・初回参照で自動作成・最終スコープ uninstall で削除（`--keep-data` で保持） | `docs/plugins-reference`（persistent data directory） | 63701・63724 付近 |
| S20 | README 同梱は推奨だが UI 閲覧導線なし→`homepage`/Discover で案内／`claude plugin details` はコンポーネント一覧表示／plugin root の `CLAUDE.md` は非ロード | `docs/plugins`・`docs/discover-plugins`・`docs/plugins-reference` | 27807・13706・64098・63855 付近 |
| S21 | plugin cache の旧バージョン dir 削除猶予は**約14日**（orphaned 化後の background sweep）。最後の1個の plugin をアンインストールすると sweep が停止し、次に plugin を入れるまで orphaned dir が残る（S18 の「約7日」から変更） | `docs/plugins-reference`「Plugin caching and file resolution」 | **v2.1.235 版(2026-08-19)**（ページ＋見出し参照。行番号なし） |
| S22 | `--debug` のカテゴリフィルタは `=` 結合形（例: `--debug='mcp,startup'`）のときだけ機能し、スペース区切り（例: `--debug mcp`）はフィルタなしでデバッグモードを有効化するだけ | `docs/cli-reference`「CLI flags」 | **v2.1.235 版(2026-08-19)**（ページ＋見出し参照。行番号なし） |
| S23 | `claude-plugins-official` はマシン初回の対話起動時に自動登録される。CI・非対話環境で先に実行すると未登録のことがあり、その場合は `claude plugin marketplace add anthropics/claude-plugins-official` で自分から登録する | `docs/plugins`「Submit your plugin to the community marketplace」／`docs/discover-plugins`「Official Anthropic marketplace」 | **v2.1.235 版(2026-08-19)**（ページ＋見出し参照。行番号なし） |
| S24 | marketplace 経由 install の plugin は、`package.json` ＋対応ロックファイル（`bun.lock`/`bun.lockb`/`npm-shrinkwrap.json`/`package-lock.json`）があれば cache 配置時に Claude Code が自動で `--ignore-scripts` install する（yarn/pnpm ロックファイル・lifecycle script 必須の依存・Python 依存は対象外） | `docs/plugins-reference`「Node.js package dependencies」 | **v2.1.235 版(2026-08-19)**（ページ＋見出し参照。行番号なし） |
| S25 | marketplace の相対path `source` は git 経由の追加とローカルディレクトリとしての追加の両方で機能し、直接 URL 追加では不可。非git配布の新 source 種別として `archive`（zip HTTPS配信・v2.1.224+）と `command`（ローカルコマンド生成・v2.1.229+）が追加された | `docs/plugin-marketplaces`「Relative paths」／「Zip archives」／「Command sources」 | **v2.1.235 版(2026-08-19)**（ページ＋見出し参照。行番号なし） |
| S26 | plugin manifest は `name` と `dependencies` 配列のみでも成立し、複数 plugin を1回の install にまとめる「バンドル plugin」を作れる | `docs/plugin-dependencies`「Bundle plugins for a team」 | **v2.1.235 版(2026-08-19)**（ページ＋見出し参照。行番号なし） |
| S27 | `git-subdir` source は git リポジトリの**サブディレクトリ**を plugin として参照する。`url`（GitHub `owner/repo` 短縮形・SSH 可）と `path` が必須、`ref`/`sha` で固定可。取得は sparse・partial clone でそのサブディレクトリのみ | `docs/plugin-marketplaces`「Git subdirectories」 | **v2.1.235 版(2026-08-19)**（ページ＋見出し参照。行番号なし） |
| S28 | skill の呼び名の決まり方 ―― personal/project の skill は**ディレクトリ名**、plugin の `skills/<dir>/SKILL.md` は frontmatter `name` かディレクトリ名を **plugin 名で名前空間化**、**plugin ルート直下の `SKILL.md`** は frontmatter `name`（無ければ plugin ディレクトリ名）が最終セグメントになる。plugin skill は名前空間形に加え、他コマンドと衝突しない限り bare 形でも呼べる（v2.1.216 で挙動変更） | `docs/skills`「How a skill gets its command name」 | **v2.1.235 版(2026-08-19)**（ページ＋見出し参照。行番号なし） |
| S29 | project scope の `@skills-dir` plugin・project subagent の frontmatter hooks・リポジトリや `--add-dir` 由来の `extraKnownMarketplaces` は、**親フォルダの trust では使われず、trust ダイアログも出ない**。対処は `~/.claude.json` の `projects["<パス>"].hasTrustDialogAccepted` を手動で `true` にすること | `docs/permissions`「What runs before you trust a folder」 | **v2.1.235 版(2026-08-19)**（ページ＋見出し参照。行番号なし） |
| S30 | plugin skill は `/plugin-name:skill-name` に名前空間化されるため、**元の `/skill-name` と plugin 版が両方残る**（片方が上書きしない）。移行後は重複を避けるため `.claude/` 側の原本を削除せよ | `docs/plugins`「Migrate existing configurations」 | **v2.1.235 版(2026-08-19)**（ページ＋見出し参照。行番号なし） |
| S31 | `claude plugin tag` は `{name}--v{version}` の git tag を作り、**`plugin.json` と marketplace エントリの版が一致しているかを検証**する（`--dry-run`／`--push`／`--remote` あり） | `claude plugin tag --help`（CLI v2.1.237 実機） | 実機（docs 未確認） |

> **`plugin-dev` の機能詳細の出所**: 上記 S15 は docs 側の「言及」のみ。7 skill・`/plugin-dev:create-plugin` の 8 フェーズ・3 agent・6 検証スクリプトといった機能詳細は docs に無く、根拠は plugin 同梱の `README.md` および `commands/create-plugin.md` / `agents/*.md` / `.claude-plugin/plugin.json`（`anthropics/claude-plugins-official` の `plugins/plugin-dev/`、GitHub MCP で取得・精読）。

> **`plugin-dev` の裏取り（完了）**: web discovery 段階で観測したコミュニティ説 "plugin-development" は、**公式リポジトリの純正プラグイン `plugin-dev` が実体**であることを README 精読で確定した（[§6](#plugin-dev)）。ただしコミュニティ説の具体（`/plugin-development:init` / `:validate` でスラッシュコマンド／dev marketplace 生成）は**不正確**で、実際の主コマンドは **`/plugin-dev:create-plugin`（8 フェーズのガイド付き作成ワークフロー）**であり、専用の "dev marketplace" を生成する機能は README に記載が無い（テストは `--plugin-dir` / `claude --debug`）。公式 docs には `discover-plugins` の1行カタログ掲載と `plugins-reference` の名前空間例としての言及はあるが、**機能の詳細解説は無く、知見の出所は plugin-dev の README** である点に留意。

## 変更履歴

- **v1.5（2026-08-20）**: **[§9](#single-entity)「実測: 資産形態 × 消費チャネルのロード挙動」を新設**。[手順書 v2.0](./Plugin開発・テスト_手順書.md) の刷新（開発シナリオ 2 パターン化）の根拠として、CLI v2.1.237 の実機で 10 セルのロード挙動マトリクスを取得した。主な確定事項:
  - **案B''（`.claude/skills/<name>/` に `plugin.json` を足す）は既存利用者に非破壊** ―― 追加後も素の skill としての呼び名 `/<name>` は project 経路でも `--add-dir` 経路でも変わらない。`--add-dir` 経由では plugin にはならず素の skill のままロードされる。
  - **`git-subdir` により、層1 body と層2 plugin を「実体 1 つ・参照 2 通り」に畳める**（コピー不要・publish 不要）。配布計画 §4 判断 #1 の dual は「両方に実体を置く」必要が無くなった。
  - **層1 と層2 を同時に入れると素の project skill と plugin skill が二重に載る**（plugin 同士の衝突は CLI が抑止するが、素の skill は残る）。公式も移行後の原本削除を明記（[S30](#sources)）。
  - **D-2 の実測**: 実体 C-MKT は `.claude-plugin/marketplace.json` 不在で `marketplace add` に失敗し、**層2 レールは未開通**。実 `publish-plugin.sh` は現行 skills をそのままでは publish できず（`plugin.json` 必須）、また非対話では `read` プロンプトでハングする。
  - 出典 [S27](#sources)〜[S31](#sources) を追加（`git-subdir` / skill 呼び名の決まり方 / trust の手動受諾 / 移行時の重複 / `claude plugin tag`）。
- **v1.4（2026-08-20）**: 公式ドキュメント最新版（CLI v2.1.235 相当・2026-08-19 取込）との横断整合性照合（検出タスク G2・本書＋[手順書](./Plugin開発・テスト_手順書.md)の2文書で計17件検出）を反映。本書側の適用は7件（G2-001, G2-003, G2-006, G2-008, G2-011, G2-014, G2-017）。**あわせて H1 の版番号が v1.1〜v1.3 の間 "v1.0" のまま更新されていなかった不備を本版で訂正**（変更履歴は進んでいたが見出しが追随していなかった）。主な変更:
  - **【CRITICAL 訂正】§5 検証・デバッグ表 `claude --debug` の検出内容**: カテゴリを絞るには **`=` 結合形が必須**（例: `--debug='mcp,startup'`）で、スペース区切り（`--debug mcp` 等）はフィルタとして機能せずデバッグモードを有効化するだけと訂正。hook 評価の粒度は `CLAUDE_CODE_DEBUG_LOG_LEVEL=verbose` で上げる旨を追記（出典 [S22](#sources)。旧記述のまま実行すると意図した絞り込みができない CRITICAL 案件）。
  - **§7(2) plugin cache の旧バージョン dir 削除猶予を約7日→約14日に訂正**。加えて「最後の plugin をアンインストールすると掃除処理自体が止まり、次に plugin を入れるまで残り続ける」という新条件を追記。S18 に転送注記を追加し、新事実は行番号でなくページ＋見出しで参照する [S21](#sources) として追加（S18 自体の行番号は据え置き）。
  - **§4 `--add-dir` 早見表に commands（`.claude/commands/`）の自動ロード行を追加**（v2.1.235 版で追加・ライブリロードなし・同名時はプロジェクト側優先）。正本は引き続き [v1.2 付録B『--add-dir 例外ロード一覧（正本）』](../../01.配布・統制方針調査/結論・構成案_ポータブルな.claude共有_v1.2.md#adddir-exceptions)（既に同期済み）。
  - **§4・§6 の `claude-plugins-official` install 例に自動登録の注意を補記**: マシン初回の対話起動時に自動登録される仕様のため、CI・非対話環境で先に動かすと未登録になりうる（出典 [S23](#sources)）。
  - **§7(2) node_modules 等の依存記述を訂正**: marketplace 経由 install の plugin は npm/Bun の依存（`package.json`＋対応ロックファイル）を cache 配置時に自動インストールするようになったため、手動配置が必要なのは yarn/pnpm ロックファイル・lifecycle script 必須の依存・Python 依存に限定されると明記（出典 [S24](#sources)）。
  - **§3(3) marketplace の相対 path 参照の説明を拡張**: 「git 経由配布でのみ機能」という二値的な説明を改め、ローカルディレクトリ追加でも機能する旨を明記。非git配布の新 source 種別 `archive`（v2.1.224+）・`command`（v2.1.229+）を追記（出典 [S25](#sources)）。S9 に転送注記を追加。
  - **§8 に「バンドル plugin」（`name`＋`dependencies` 配列のみの manifest で複数 plugin を1install にまとめる新パターン）を改善機会として追記**（出典 [S26](#sources)）。
  - 出典を S20→S26 まで拡張。新規 S21〜S26 は snapshot 依存の行番号でなく**ページ名＋セクション見出し＋版タグ**で参照する方式に統一（既存 S1〜S20 の行番号は据え置き）。
- **v1.3（2026-06-29）**: 横断整合性レビュー J1 反映。§4 `--add-dir` 例外表に、版依存事実の**正本＝[v1.2 付録B『--add-dir 例外ロード一覧（正本）』](../../01.配布・統制方針調査/結論・構成案_ポータブルな.claude共有_v1.2.md#adddir-exceptions)** への参照注記を追加（本表は運用早見と位置づけ）。
- **v1.2（2026-06-29）**: 横断整合性レビュー反映。§4 表の subagents×`--add-dir` を **「✅（v2.1.178+。v2.1.165 までは非ロード）」** と版境界付きに統一（v1.2 報告書 errata [75]・Marketplace外資産編 C9 と整合）。従来は本編のみ無条件 ✅ で版境界が欠落し、版を跨ぐ読者に「常時ロード」と誤読される恐れがあった。
- **v1.1（2026-06-25）**: §7「plugin 配布時のパス解決・可変状態・同梱物アクセス（実装制約）」を新設（実 skill の plugin 化テストで顕在化）。`${CLAUDE_SKILL_DIR}`／`${CLAUDE_PLUGIN_ROOT}` の置換範囲と env export、cache の ephemeral 性（書込禁止・約7日 orphan）と `${CLAUDE_PLUGIN_DATA}` への可変状態退避、README/references のユーザアクセス制約（UI 非閲覧→`homepage`）、`skills/<name>/` 構成要素別挙動を原文照合で確定。§出典に S16〜S20 を追加。[手順書 §8（当時 v1.1 §6）](./Plugin開発・テスト_手順書.md#impl-rules) の根拠。旧§7「v1.2との接続・含意」は §8 へ繰り下げ。原文照合は `cc-docs-plugins-marketplace-expert` agent。
- **v1.0（2026-06-21）**: 初版。公式 docs（plugins / plugin-marketplaces / plugins-reference / skills）の原文照合に基づき、層2 配布物の開発・テストフロー・手段・制約・検証を整理。レビュー指摘反映として `--debug` の実行時カバー範囲、`validate` の必須/推奨条件、`skill-creator` の機能詳細・公開 URL を補強。純正 `plugin-dev` を README＋`create-plugin.md`／agent 定義／manifest の精読で裏取りし [§6](#plugin-dev) を追加（8 フェーズ詳細・3 agent・6 スクリプト・`commands/` レガシー指針・docs カタログ掲載の確認を含む）。**Sonnet 動作検証（実機 `claude plugin validate` v2.1.185）の反映**: `plugin.json` の `author` ＝オブジェクト型・`marketplace.json` の `owner` ＝必須、`--add-dir` は skills だけでなく **subagents（`.claude/agents/`）も自動ロード**（§4 訂正）、`--debug` 出力先 `~/.claude/debug/<session-id>.txt`、`validate --strict`。
