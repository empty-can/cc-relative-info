# 実装テンプレート（層1+2）— 3チャネル構成の雛形

> 方針レポート（`reports/01.配布・統制方針調査/結論・構成案_…_v1.2.md`）の **§推奨** を、
> コピーして使える**ディレクトリ骨格**へ落とした実装雛形。スコープは作業指示者判断により
> **層1+2（テスト可能なコア）**。層3（Managed settings）は通常マシンで実機検証できないため
> 本雛形には含めず、レポート本文 **§解決案 層3系・案D** の記述に委ねる。

## この雛形の位置づけ

- **層1＝Git commit テンプレート**（`layer1-repo-template/`）: 利用先リポジトリの直下へ
  コピー／commit する最小骨格。**層2 で運べないガバナンス資産**（`CLAUDE.md` / `rules` /
  `permissions`）と、**層2 を起動するための装置**（`settings.json` の
  `extraKnownMarketplaces` / `enabledPlugins`）に絞る。
- **層2＝Plugin / Marketplace**（`layer2-plugin/`）: skills / subagents / hooks /
  output-styles などの**機能資産**を一元更新可能な plugin に集約する骨格。

実装の起点は既存の `<Share>` リポジトリ **`base-dev-kit-for-cc`**
（`empty-can/base-dev-kit-for-cc`・案1/README 隔離）。本雛形はその資産を層1+2 へ
振り分けた姿を示す（base-dev-kit は層1 単独の `<Share>` 実装、本雛形はそれを層2 集約へ進めた形）。

## レポート §推奨 との対応：base-dev-kit 資産の振り分け

| base-dev-kit の資産 | 寄せる先 | 雛形での所在 | 根拠（レポート） |
|---|---|---|---|
| skills（commit-and-pr / orchestrate / request-new-skill / review-skill-request） | **層2** | `layer2-plugin/plugins/base-dev-kit/skills/`（形式雛形 `example-skill/` のみ同梱・実 skill は配布時に追加） | 一元更新・版管理（マトリクス①） |
| `code-reviewer` subagent | **層2** | `layer2-plugin/plugins/base-dev-kit/agents/` | plugin 経由可（hooks/mcpServers/permissionMode 不使用＝①△に非該当） |
| `code-review` output-style | **層2** | `layer2-plugin/plugins/base-dev-kit/output-styles/` | 機能資産（マトリクス①） |
| SessionStart hook（`git status --short`） | **層2** | `layer2-plugin/plugins/base-dev-kit/hooks/hooks.json` | hooks は plugin で自己完結（①）。本例はインラインコマンドのみで同梱スクリプト不要。スクリプトを同梱する hook は `${CLAUDE_PLUGIN_ROOT}/...` で参照する |
| `CLAUDE.md`（共通ガバナンス） | **層1** | `layer1-repo-template/.claude/CLAUDE.md` | plugin で運べない（マトリクス②） |
| `rules/coding-standards.md` | **層1** | `layer1-repo-template/.claude/rules/` | 常時 rule は skill 化でも代替不可（②） |
| `permissions`（deny/allow） | **層1** | `layer1-repo-template/.claude/settings.json` | plugin で運べない（②） |
| **層2 起動装置**（extraKnownMarketplaces / enabledPlugins） | **層1** | `layer1-repo-template/.claude/settings.json` | 層2 有効化の前提・project commit（②） |
| README（リポ固有情報） | 層1（隔離先） | `layer1-repo-template/README.md.example` | README 隔離方式（README は memory ファイルでなく `--add-dir`+env でも非ロード） |

> **△回避の注記**: `hooks` / `mcpServers` / `permissionMode` を使う subagent は plugin 経由だと
> 当該設定が無視される（マトリクス①△）。そうした subagent は層1 commit か層3 managed へ。
> 本雛形の `code-reviewer` はこれらを使わないため層2 で問題ない。

## 起動装置が「のり」

層1 と層2 を繋ぐのは、層1 に commit する `settings.json` の 2 キー:

- `extraKnownMarketplaces` — plugin を取得する Marketplace を宣言（project スコープでチーム配布）
- `enabledPlugins` — どの plugin を有効化するかを宣言

これらを project（`.claude/settings.json`）に commit することで、clone したメンバー全員に
層2 plugin が誘導される。**user スコープ（`~/.claude/`）はチーム配布にならない**点に注意。
ただし「clone だけで即利用可」ではなく、trust 時のインストールプロンプト、fresh machine での
`claude plugin install` が必要になりうる（レポート §解決案 層2系の注意事項）。

> **コピー後の置換（必須）**: 雛形のプレースホルダを自組織の実値へ置換する——`.claude/settings.json` の `your-org/base-dev-kit-marketplace`（→ 実 Marketplace リポジトリ）、`marketplace.json`・`plugin.json` の `Your Team`・`team@example.com`（→ 実チーム名・連絡先）。未置換のままだと存在しない repo を参照し層2 が起動しない。

## ディレクトリ構成

```
03.実装テンプレート（層1+2）/
├── README.md                          # 本ファイル
├── layer1-repo-template/              # 層1: 利用先リポへ commit する骨格
│   ├── .claude/
│   │   ├── CLAUDE.md                  # 共通ガバナンス（README 隔離・--add-dir+env でロード）
│   │   ├── rules/coding-standards.md  # path-scoped 規約
│   │   ├── settings.json             # permissions ＋ 層2 起動装置 ★のり
│   │   └── settings.local.json.example
│   ├── .mcp.json
│   ├── .env.example
│   ├── .gitignore
│   ├── CLAUDE.md.example             # 方法A コピー展開用のリポ固有 CLAUDE.md 雛形
│   └── README.md.example             # リポ固有情報の隔離先 雛形
└── layer2-plugin/                     # 層2: plugin + marketplace 骨格
    │                                  #   ★このディレクトリ自体が「Marketplace ルート」
    ├── .claude-plugin/
    │   └── marketplace.json          # Marketplace 定義（plugin の所在を列挙）
    └── plugins/
        └── base-dev-kit/
            ├── .claude-plugin/
            │   └── plugin.json       # plugin メタデータ
            ├── skills/example-skill/SKILL.md
            ├── agents/code-reviewer.md
            ├── output-styles/code-review.md
            └── hooks/hooks.json      # SessionStart（インライン git status --short）
```

> Marketplace と plugin は本雛形では 1 リポジトリ内に併置しているが、実運用では
> Marketplace を独立リポジトリにして複数 plugin を集約する構成も採れる
> （レポート §解決案 層2系・案B/B'）。

> **⚠ `.claude-plugin/` の位置は「Marketplace ルート」を決める（2026-08-20 修正）**
>
> 公式仕様では **相対パスの `source` は「`.claude-plugin/` を含むディレクトリ」＝ Marketplace ルートを基準に解決**され、
> **`../` でルート外を参照することは禁止**されている（`plugin-marketplaces` §Relative paths・v2.1.235 版 2026-08-19）。
> 本雛形は当初 `layer2-plugin/marketplace/.claude-plugin/marketplace.json` と `layer2-plugin/plugins/` を**兄弟**に置いていたため、
> `"source": "./plugins/base-dev-kit"` が `layer2-plugin/marketplace/plugins/base-dev-kit`（実在しない）へ解決され、
> **そのままコピーして公開すると `/plugin install` が失敗する**状態だった。`.claude-plugin/` を `layer2-plugin/` 直下へ移して修正済み。
>
> **⚠ `claude plugin validate` はこの欠陥を検出しない**（実測）。修正前後の対照実験:
>
> | 検査 | 修正前（兄弟配置） | 修正後（現行） |
> |---|---|---|
> | `claude plugin validate .` | ✔ Validation passed（**見逃す**） | ✔ Validation passed |
> | `claude plugin validate . --strict` | ✔ Validation passed（**見逃す**） | ✔ Validation passed |
> | `claude plugin marketplace add` → `claude plugin install` | ✘ `Source path does not exist: …\plugins\base-dev-kit` | ✔ Successfully installed |
>
> したがって **相対パス `source` を使う Marketplace の検証は `validate` では足りず、`marketplace add` → `install` まで実際に通すこと**。
> （実測環境: CLI v2.1.237 / 2026-08-20。個人設定を汚さないよう `CLAUDE_CONFIG_DIR` を一時ディレクトリへ向けて実行した。
> 「守れた」を主張する検査には対照実験を付けるという方針は
> [レーンA 確定書 §10-bis](../04.資産インベントリ・統合/04.ランチャースクリプト実装/配布・リリース設計確定_レーンA.md) と同じ。）

## テスト手順への導線

本雛形の開発・テスト手順は既存の成果物に詳述済み。重複させず参照する:

- **層2（plugin）の開発・テスト**: `reports/02.配布物の開発・テスト/01.Plugin・Marketplace編/`
  - ローカルテスト = `claude --plugin-dir layer2-plugin/plugins/base-dev-kit`
  - 構造検証 = `claude plugin validate layer2-plugin/plugins/base-dev-kit`（＋ marketplace 側は `cd layer2-plugin && claude plugin validate .`）
  - **導線検証（必須・上記の ⚠ 参照）** = `claude plugin marketplace add layer2-plugin` → `claude plugin install base-dev-kit@base-dev-kit-marketplace`。
    **`validate` は相対パス `source` の解決失敗を検出しない**ため、install まで通して初めて「配れる」と言える
- **層1（Marketplace 外資産）の開発・テスト**: `reports/02.配布物の開発・テスト/02.Marketplace外資産編/`
  - ネイティブ起動スモーク（方法A）／`--add-dir` + env + `--settings` 結合検証（方法B）
  - 公開前ゲート = `check-assets`（衛生）＋ `/security-review`（脆弱性）
  - 検証コマンド = **`/context`（何が実際にロードされたかの正）**・`/memory`（置き場所の一覧）・`/status`・`/doctor`・`/skills`・`/plugin`
    - ⚠ **`/agents` は v2.1.198 以降 subagent の一覧を表示しない**（案内文言のみ）。subagent がロードされたかは **`/context`** で確認する（ロード元も併記される）。同様に **`/memory` は「ロード済み」ではなく「置き場所（未作成含む）」の一覧**に変わっている

## スコープ外（層3）

層3（Managed settings）はガバナンス資産の**強制**チャネルだが、server-managed は
Claude for Teams/Enterprise 契約、endpoint-managed は MDM／OS 管理者権限が前提で、
通常の開発マシンでは雛形を実機検証できない。設定キー・配置パス・選択軸（server-managed vs
gateway-managed vs endpoint-managed）はレポート **§解決案 層3系・案D** と **付録A** に整理済み。本雛形では扱わない。

---

## 変更履歴

- **2026-08-20（公式ドキュメント最新版 CLI v2.1.235 相当・2026-08-19 取込 との照合による最新化）**
  - **【CRITICAL 修正】`layer2-plugin/` のディレクトリ構成を変更** —— `marketplace/.claude-plugin/marketplace.json` を
    **`layer2-plugin/.claude-plugin/marketplace.json` へ移動**（`git mv`）し、空になった `marketplace/` を削除。
    相対パス `source` は「`.claude-plugin/` を含むディレクトリ」を基準に解決されるため、従来の兄弟配置では
    `"./plugins/base-dev-kit"` が実在しないパスへ解決され、**コピーして公開すると `/plugin install` が失敗する**状態だった。
    **`claude plugin validate`（`--strict` 含む）はこの欠陥を検出しない**ことを対照実験で実測し、
    §ディレクトリ構成に警告と検証手順（install まで通すこと）を追記した。
  - **`agents/code-reviewer.md` の `tools` を修正** —— `Bash(git status:*), Bash(git diff:*)` は subagent の `tools` では
    解釈されない（受け付けるのは厳密なツール名か `mcp__` パターンのみ）。`Bash` に直し、
    引数レベルで絞る正しい手段（`permissions.deny`／`PreToolUse` hook。**plugin 配布時は frontmatter の `hooks` が無視される**点も）を
    コメントで明記した。
  - **`rules/coding-standards.md` の `paths:` 14 行をブレース展開 1 行に集約**（展開後のパターン数上限にも言及）。
  - **用語を公式表記に統一** —— `sub-agent` → `subagent`（3 箇所）。
  - **検証コマンドの導線を更新** —— `/agents` は v2.1.198 以降 subagent 一覧を表示しないため **`/context`** を正とし、
    `/memory` の意味変化（ロード済み → 置き場所一覧）も注記。
  - **層3 の系統名を 3 系統へ更新**（server-managed / gateway-managed / endpoint-managed）。
  - **`layer1-repo-template/.env.example` の private Marketplace 認証コメントを全面的に書き換え** ——
    旧版は「`GITHUB_TOKEN` / `GH_TOKEN` / `GITLAB_TOKEN` / `GL_TOKEN` / `BITBUCKET_TOKEN` のいずれか」とだけ書いており、
    **変数を置けば自動更新の認証になると読めた**が、公式は
    *"Setting a provider token such as `GITHUB_TOKEN` in your environment doesn't by itself enable background authentication.
    Tokens take effect only through a configured credential helper."* と明記している（`plugin-marketplaces` §Private repositories・
    v2.1.235 版 2026-08-19）。**手動操作は credential helper を使うが、バックグラウンドの `git pull` は helper を無効化する**という
    非対称が要点なので、その差と実際の設定手順（`gh auth setup-git` ／ global な URL 書き換え ／ SSH remote ／
    `CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE=1`）へ置き換えた。
