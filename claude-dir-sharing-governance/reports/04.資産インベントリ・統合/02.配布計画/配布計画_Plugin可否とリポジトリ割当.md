# 配布計画 — Plugin 配布可否と統合・清書・テストのリポジトリ割当

> [配布可能資産インベントリ](../01.全マシン資産インベントリ/配布可能資産インベントリ.md)を入力に、各資産を **Plugin（層2）で配布できる/できない**に分類し、**どのリポジトリで統合・清書・テストするか**を割り当てる計画。略号は §0 インベントリ準拠（`C-`=cc-workspace／`W-`=workspace／`U-`=ユーザスコープ）。
>
> 根拠: 公式 docs（plugins / plugins-reference / skills、v2.1.195 相当）＋ 内部 v1.2 チャネルマトリクス。

## 1. Plugin が同梱できる/できないコンポーネント（確定）

公式 docs で確認済みの type-level の可否（本計画の前提）。

### Plugin で配布**できる**（層2 コンポーネント）
`skills/`（SKILL.md＋reference/examples/scripts 等のサポートファイル同梱可）／`commands/`（レガシー・新規は skills 推奨）／`agents/`（**`hooks`・`mcpServers`・`permissionMode` フロントマターキーは利用不可**）／`hooks/hooks.json`（参照スクリプトは `${CLAUDE_PLUGIN_ROOT}` で同梱）／`.mcp.json`／`output-styles/`／`.lsp.json`／`monitors/`(v2.1.105+)／`themes/`(experimental)／`bin/`／`settings.json`（**`agent` と `subagentStatusLine` キーのみ**・他は silently ignored）／**`workflows/`**（v2.1.235 版(2026-08-19) で plugin の正規コンポーネントに追加。plugin.json の `workflows` フィールドで既定 `workflows/` を上書き可）

> ⚠ **追記（2026-08-20・G5-003）**: `workflows/` は本計画の初版（2026-06-29）時点では plugin コンポーネントとして未定義だったため一覧から漏れていた。現行仕様での位置づけの正本は [v1.2 §核心マトリクス](../../01.配布・統制方針調査/結論・構成案_ポータブルな.claude共有_v1.2.md#matrix) ①（機能・拡張資産）に集約されている（v1.0〜v1.2 では④「層1 でのみ配布できる資産」に属していたが、v2.1.235 版で層2 へ移設済み）。本計画は v1.2 と矛盾しない形に追記したのみで、可否判定そのものは v1.2 を正とする。

### Plugin で配布**できない**（→ 層1 Git / 層3 Managed / `--add-dir`）
| 資産 | 理由 | 代替配布手段 |
|---|---|---|
| `CLAUDE.md` / project memory | plugin root の CLAUDE.md は**非ロード**（明示除外） | skill 化して同梱／層1 Git／`--add-dir`+env |
| `rules/*.md`（path-scoped） | plugin コンポーネント未定義 | **skill の `paths:` frontmatter**／層1 Git／managed `CLAUDE.md` 経由 |
| `settings.json` の `permissions`(allow/deny) | 非サポートキー（silently ignored） | **層3 managed settings**／層1 Git（強制力なし） |
| メインセッション `statusLine` スクリプト | plugin は `subagentStatusLine` のみ対応 | 層1 Git／ユーザ・プロジェクト settings |
| standalone な `templates/` | plugin コンポーネント未定義 | **skill のサポートファイルとして同梱**／層1 Git |
| plugin 外ファイル参照 | install 後 cache にコピーされない | plugin ディレクトリ内に内包 |

## 2. 本インベントリ資産の配布チャネル分類

インベントリの各クラスタを当てはめた結果。**汎用共有**（全チームに配る）と**テーマ特化**（特定調査専用・据え置き）を区別する。

### 2-A. Plugin（層2）で配布 — 汎用共有
| 資産 | 正本 | 備考 |
|---|---|---|
| `skills/commit-and-pr` | C-BDC（=多数一致） | そのまま |
| `skills/orchestrate` | C-BDC（=多数一致） | そのまま |
| `skills/request-new-skill` | C-BDC | **依頼書テンプレを skill サポートファイルへ同梱**（standalone templates/ は不可） |
| `skills/review-skill-request` | C-BDC | 同上（`skill-request/` の2テンプレを内包） |
| `skills/5-whys`（+examples/references） | C-CRI/C-RBC/W-RBC（一致） | サポートファイル同梱は plugin 正式対応 |
| `skills/check-model` | **C-CRI のみ**（⚠訂正・2026-08-20: 旧記載「C-CRI/C-RBC」は誤り。C-RBC/W-RBC 全ブランチに不在。01 全ブランチ走査で訂正済み） | そのまま |
| `skills/read-prompt-file`（+README+sh） | C-CRI/C-RBC | スクリプトは plugin 内へ |
| `skills/pre-compact` | **C-CRI(122)** | ⚠️96版でなく122版。`references/decision-flow.md` 同梱 |
| `agents/code-reviewer` | C-BDC（=多数一致） | `hooks`/`mcpServers`/`permissionMode` 不使用＝plugin 可 |
| `output-styles/code-review` | C-BDC（=多数一致） | そのまま |
| `hooks`（SessionStart: git status --short 等） | C-BDC settings | plugin では `hooks/hooks.json` 化（インラインコマンド） |

### 2-B. Plugin（層2）で配布可能だが**テーマ特化** — 別 plugin か据え置き
| 資産 | 所在 | 推奨 |
|---|---|---|
| `skills/generate-llms-txt` | C-CRI | docs テーマ。**C-CRI/C-LLM に据え置き**（汎用 plugin に入れない） |
| `skills/update-official-doc-summary` | **C-LLM(359 正式)** | docs パイプライン。**C-LLM 据え置き** |
| `agents/doc-summary-reviewer` | **C-LLM(94)** | 同上・C-LLM 据え置き |
| `agents/cc-docs-*-expert` ×4 | W-RBC（未追跡） | RAG/governance 専用。**据え置き**（配布対象外の公算大） |

### 2-C. Plugin 不可 — 層1 Git body（C-BDC）/ 層3 Managed へ
| 資産 | 正本 | チャネル |
|---|---|---|
| `CLAUDE.md`（チーム共通） | **C-BDC(50)** | 層1 Git body／`--add-dir`+env |
| `settings.json` の permissions | **C-BDC(39)**(+show/blame 検討) | 層1 Git／（強制は層3 managed） |
| `rules/coding-standards.md` | 全一致 | 層1 Git body |
| `rules/agent-delegation.md` / `git-workflow.md` / `research-source-routing.md` | W-RBC | 層1 Git body（無条件ロード系） |
| `rules/agent-permission-runtime.md` / `cross-review-runtime.md` / `skill-creation-guide.md` | C-CRI/C-RBC/W-RBC | 層1 Git body（path-scoped） |
| `templates/cross-review/` | **W-RBC(v3.0α-r2)** | 層1 Git body（または将来 cross-review skill のサポートファイル化） |
| `templates/inter-claude-communication/` | 一致 | 層1 Git body |
| `statusline`（メインセッション） | **C-RBC(162)+U-USR(145)**（⚠暫定・2026-08-20: 01 §6-5 参照。`tmp/ng_analyzing_optimize` の未push・199行改変が要現物確認のため正本確定は保留） | 層1 Git／ユーザ settings（plugin 不可） |

> **重要な含意**: 共有 `.claude` の中身は **2トラックに分かれる**。機能資産（skills/agents/output-styles/hooks）は Plugin 化できるが、ガバナンス資産（CLAUDE.md/rules/settings permissions/templates/statusline）は Plugin 化できず層1 Git（C-BDC body）が主経路。**Plugin だけでは共有 `.claude` を再現できない**——これは v1.2 の「単一手段では配れない／3チャネル併用」結論の再確認。

## 3. 統合・清書・テストのリポジトリ割当

### 3-1. 集約先（統合・清書を行う場所）
- **汎用共有資産は C-BDK（base-dev-kit-for-cc／`<Dev>`）に一元集約**する。C-BDK は既存 dev-flow の開発源（`.claude/` body ＋ `scripts/` 配布運用ツールを保持）。散在する正本（C-CRI/C-RBC/W-RBC 由来の 5-whys・check-model・read-prompt-file・rules・cross-review テンプレ・pre-compact等）を C-BDK へ取り込み・清書する。
- **テーマ特化資産（2-B）は各ホーム据え置き**（C-LLM=docs パイプライン、W-RBC=cc-docs-expert）。汎用配布に混ぜない。
- **（2026-08-20 追加）「公開前提で新規に作る単発・独立資産」の置き場所**: 全員に配る性格を持たない単発資産は、C-BDK の **`.claude/` の外**（例: `<C-BDK>/plugins/<name>/`）に開発エリアを置く。`publish-share` の payload は `.claude/` 配下だけなので、**層1（C-BDC→C-BCP）へは流れず、層2（C-MKT）だけで配れる**。`publish-plugin.{sh,ps1}` の既定 `--plugin plugin` はこの形を想定した既定値である。判断フロー（チーム共通資産か／単発独立か／専用リポジトリ新設か）は [Plugin/Skill 手順書 §2-1](../../02.配布物の開発・テスト/01.Plugin・Marketplace編/Plugin開発・テスト_手順書.md#b1) を正とする。

### 3-2. 2トラックの開発→テスト→配布

```
                 ┌─────────────────────────────────────────────┐
                 │   C-BDK  base-dev-kit-for-cc  （<Dev>＝集約・清書）   │
                 │   散在正本を取り込み・清書（汎用共有のみ）            │
                 └───────────────┬─────────────────────┬─────────┘
       層1（ガバナンス資産）         │                     │  層2（機能資産）
   CLAUDE.md/settings/rules/        │                     │  skills/agents/output-styles/hooks
   templates/statusline            │                     │
                                   ▼                     ▼
            ┌──────────────────────────┐   ┌──────────────────────────────┐
            │ テスト（層1 body）            │   │ テスト（層2 plugin）              │
            │ clean-test-env + check-assets│   │ claude --plugin-dir            │
            │ + --add-dir 実機(手順書v1.6) │   │ + claude plugin validate --strict│
            └────────────┬─────────────┘   │ + ローカル marketplace install 検証 │
                         │                  └────────────┬─────────────────┘
                         ▼ publish-share(Sync A)         │ git push
            ┌──────────────────────────┐   ┌──────────────────────────────┐
            │ C-BDC basic_dot_claude       │   │ C-MKT marketplace-for-cc        │
            │ （.claude body・submodule源）  │   │ （marketplace.json で配布）        │
            └────────────┬─────────────┘   └────────────┬─────────────────┘
                         ▼ submodule bump                ▼ /plugin marketplace add + install
            ┌──────────────────────────┐   ┌──────────────────────────────┐
            │ C-BCP basic_cc_project（雛型） │   │ 利用先プロジェクト                  │
            └──────────────────────────┘   └──────────────────────────────┘
```

| トラック | 統合・清書 | テスト | 配布 | 既存資産 |
|---|---|---|---|---|
| **層1 Git body** | C-BDK `.claude/` | clean-test-env / check-assets / `--add-dir` 実機 | publish-share → C-BDC → C-BCP submodule | 手順書 v1.6・scripts 6本（C-BDK） |
| **層2 Plugin** | C-BDK 内に plugin 開発エリア | `--plugin-dir` / `plugin validate --strict` / ローカル marketplace | push → C-MKT marketplace | layer2-plugin テンプレ（reports/03） |

## 4. 判断事項と確定結果（2026-06-29 確定）

| # | 論点 | 確定 |
|---|---|---|
| 1 | 機能資産（skills/agents/output-styles/hooks）のチャネル | **dual** — C-BDC body は完全 standalone を維持（`--add-dir`/コピー展開で plugin 無しでも動く）しつつ、marketplace 派向けに plugin も併発行。v1.2「3チャネル併用」と整合 |
| | ⚠ 更新（2026-08-20・実測・CLI v2.1.237） | **dual は維持するが「両方に*実体*を置く」必要はなくなった**。`.claude/skills/<name>/` に `plugin.json` を足し（案B''）、marketplace からは **`git-subdir`** でそのサブディレクトリを直接参照すれば、**実体 1 つ・参照 2 通り**に畳める（コピーも publish も不要）。`plugin.json` の付与は**既存利用者に非破壊**（素の skill としての呼び名 `/<name>` は project でも `--add-dir` でも不変）。**ただし層1 と層2 を同じ利用者に両方入れさせてはならない** ―― plugin どうしの衝突は CLI が抑止するが素の project skill は残り、同じ内容が二重に context へ載る。証跡は [Plugin編 調査結果 §9](../../02.配布物の開発・テスト/01.Plugin・Marketplace編/Plugin・Marketplace配布物の開発・テスト_調査結果.md#single-entity)、実務手順は [手順書 §4](../../02.配布物の開発・テスト/01.Plugin・Marketplace編/Plugin開発・テスト_手順書.md#publish-forms) |
| 2 | Plugin 開発リポジトリのトポロジ | **multi-repo** — C-BDK（`<Dev>`）で開発・validate → C-MKT は marketplace.json で参照する薄い配布リポ |
| | ⚠ 注記（2026-08-20・G5-006・確信度medium） | `.claude/skills/<name>/.claude-plugin/plugin.json` を置くだけで marketplace 無しに project-scope plugin として自動ロードされる「**skills-directory plugins**」機構があり、**C-BDC を直接 clone/submodule 化する利用者**に対しては層1 body 自体が project-scope plugin としても機能しうる（C-MKT 経由の marketplace 派には非適用）。層1/層2 の境界を一部の利用形態で単純化できる可能性があるという補足的な検討材料であり、本表の multi-repo 確定を覆すものではない。 |
| | ⚠ 更新（2026-08-20・実測） | **multi-repo 確定は維持され、むしろ強化された**。`git-subdir` により **C-MKT は `.claude-plugin/marketplace.json` 1 ファイルだけで成立**し、plugin の実体を持つ必要がない（「薄い配布リポ」を文字どおり薄くできる）。さらに **plugin の引っ越しコストが下がる** ―― 資産を独立リポジトリへ移しても marketplace エントリの `url`/`path` を書き換えるだけで済み、利用者の `plugin install <name>@<mp>` は変わらないため、**「どのリポジトリで開発するか」の初期判断を後から取り消せる**。 |
| 3 | テーマ特化資産（2-B） | **据え置き** — C-LLM(docs)/W-RBC(cc-docs)/C-CRI(generate-llms-txt) に残置。将来必要時に別 plugin 化を再検討 |
| 4 | rules / templates の plugin 化 | **当面 層1 Git body のまま**（`--add-dir`+env 経路あり）。主要 rule の skill `paths:` 化は将来オプション |
| 5 | pre-compact の正本 | **C-CRI 122版**を配布採用（W-RBC 96版・未追跡は破棄） |

> 含意: dual 採用により、機能資産は「C-BDC body（層1）」と「plugin（層2）」の**両方に存在**する。両者の同期は C-BDK を単一集約源とすることで担保する（C-BDK の `.claude/` 正本 → body は publish-share、plugin は同じ正本から組成）。

## 5. 推奨実行順序（次フェーズ）

1. **層1 body の統合・清書**（C-BDK）: rules 群・cross-review テンプレ(W-RBC正本)・CLAUDE.md・settings(+show/blame)・statusline を C-BDK `.claude/` に取り込み清書 → clean-test-env/check-assets → publish-share で C-BDC へ。
2. **層2 plugin の組成**（C-BDK）: layer2-plugin テンプレに汎用 skills（pre-compact=122版・request/review はテンプレ同梱）＋code-reviewer＋code-review＋hooks を実装 → `plugin validate --strict` → C-MKT へ push。
   - （オプション・2026-08-20追記・G5-005）テーマ特化資産（2-B）を独立 plugin 化した上で、`name`＋`dependencies` のみで構成する **bundle plugin**（例: `cc-full-toolkit`）を C-MKT に併設し、汎用 plugin とテーマ特化 plugin を「1 install でまとめて導入」できないか検討の余地がある。§4 #3「据え置き」と §4 #1「dual 採用」の間で妥協していた設計を緩められる可能性があるが、**今回は方針決定までは行わず、将来の再検討トリガーとして記録するに留める**（確信度: medium）。
3. **C-MKT marketplace.json 整備**（greenfield からの新規構築）。
   - **（2026-08-20 実測）現状の確認結果**: 素の C-MKT に `claude plugin marketplace add` を実行すると `Marketplace file not found at …\.claude-plugin\marketplace.json` で失敗する ―― **層2 レールはまだ 1 度も通っていない**。また実 `publish-plugin.sh` は `.claude/skills/<name>` をそのまま指定すると `plugin.json が無い` で中止するため、**現行 skills を層2 に乗せるには `plugin.json` の付与（案B'' 形状）が前提**になる。`plugin.json` を付けた ref では `validate --strict` → ミラー → commit → push まで完走し、`marketplace.json` を置けば `marketplace add` → `install` まで通ることを作業用クローンで確認済み（実リポジトリ・GitHub には未接触）。詳細は [Plugin編 調査結果 §9(5)](../../02.配布物の開発・テスト/01.Plugin・Marketplace編/Plugin・Marketplace配布物の開発・テスト_調査結果.md#single-entity)。
   - **⚠ 併せて記録（本テーマのスコープ外）**: `publish-plugin.sh` は `/security-review` 実行確認の `read -r -p` を持つため、**非対話（CI・ヘッドレス）ではそこでハングする**。C-BDK 側の実装課題として残す。
4. テーマ特化資産は据え置き（必要時に別 plugin 化を再検討）。

---

## 変更履歴

- 初版（2026-06-29）: Plugin 配布可否（公式docs v2.1.195＋v1.2 マトリクス照合で確定）を本インベントリ資産に適用。汎用共有/テーマ特化を区別し、層1 Git body（C-BDK→C-BDC）と層2 Plugin（C-BDK→C-MKT）の2トラックで統合・清書・テスト・配布のリポジトリを割当。判断点5件と実行順序を提示。
- **層2 レールの実測反映（2026-08-20・CLI v2.1.237 実機）**: [Plugin/Skill 手順書 v2.0](../../02.配布物の開発・テスト/01.Plugin・Marketplace編/Plugin開発・テスト_手順書.md) の刷新に伴い、§3-1 に「公開前提の単発・独立資産の置き場所（C-BDK の `.claude/` 外の開発エリア）」を追加。§4 #1（dual）に「**両方に実体を置く必要はない** ―― 案B''＋`git-subdir` で実体 1 つ・参照 2 通りに畳める。ただし層1 と層2 を同じ利用者に両方入れさせない」を追記。§4 #2（multi-repo）に「`git-subdir` により C-MKT は `marketplace.json` 1 ファイルで成立し、plugin の引っ越しコストが下がる＝初期のリポジトリ選択を後から取り消せる」を追記。§5 手順3 に **C-MKT が現在も `marketplace.json` 不在で層2 レール未開通**であること、**現行 skills は `plugin.json` 無しでは `publish-plugin` に乗らない**こと、`publish-plugin.sh` が非対話でハングすること（スコープ外の実装課題）を実測結果として追記。
- 横断整合性レビュー反映（2026-08-20・v2.1.235 版(2026-08-19) 照合）: G5-001（statusline 行に「⚠暫定・正本確定前に要現物確認」注記を追加。01 §6-5 と足並みを揃える）／G5-002（`skills/check-model` の所在を「C-CRI/C-RBC」→「C-CRI のみ」に訂正。01・03 の全ブランチ走査結果に合わせる。旧記載は据え置きのまま更新漏れていた）／G5-003（§1「Plugin で配布できる」列挙に `workflows/` を追加。v2.1.235 版(2026-08-19) で plugin の正規コンポーネントに追加されたため。正本は v1.2 §核心マトリクスとし本計画はそれに矛盾しない形で追記）／G5-005（§5 手順2に bundle plugin（`name`+`dependencies`のみ）によるロール別一括導入のオプション検討を追記・将来の再検討トリガーとして記録）／G5-006（§4 #2 に skills-directory plugin 機構と層1/層2 境界の部分的重複を注記・multi-repo 確定は維持）。G5-004（claude-security）は本書スコープ外のためレーンA確定書側で処理（重複回避のため本書には転記しない）。
