# Plugin / Skill 開発・テスト手順書（v2.0）

> - **目的**: Claude Code で配布する plugin / skill を開発・テスト・公開する際の **全体フロー・起動オプション・コマンド例**を、手を動かす順に把握できる実務手順書。
> - **位置づけ**: [調査結果報告書](./Plugin・Marketplace配布物の開発・テスト_調査結果.md) の派生（実務オペレーション版）。**根拠・出典・制約の理由は報告書側**にあり、本書は手順に絞る（二重管理を避ける）。
> - **v2.0 の変更点**: **開発シナリオを 2 つに分けた**。旧版（v1.3 まで）は「既存リポジトリの活動の中で必要になって作り、整えて公開する」入口だけを前提にしていたが、実際には「公開前提で思いついたものを、その開発自体を作業として一気に公開まで持っていく」入口もある。両者は**入口と最初の判断だけが違い、途中から共通**なので、§1／§2 で入口を分け、§3 で合流させる構成にした。あわせて、**公開形態を 3 つから選ぶ**という判断（§4）と、**導線検証（`marketplace add` → `install`）の必須化**（§3-6）を追加した。
> - **前提環境**: Claude Code CLI（本書の実測は **v2.1.237**）。コマンドは PowerShell / bash いずれでも同形。
> - **作成日**: 2026-06-21（v2.0 改訂: 2026-08-20）

---

## 0. 全体像

<a id="scenarios"></a>

### 0-1. 2 つの開発シナリオ（入口が違う）

| | **シナリオ A: 派生型** | **シナリオ B: 公開先行型** |
|---|---|---|
| きっかけ | 既存リポジトリでの作業中に必要になって作った | 「こういう Skill／スクリプトが要る」と着想した |
| 開始時点の実体 | **すでに動くものがある**（既存リポの `.claude/` 配下） | **何も無い**。要件から起こす |
| 開発の場所 | 生まれた場所（既存リポジトリ） | **どこで開発するかを最初に決める必要がある**（§2-1） |
| 公開の位置づけ | 作った後に「これは配れるのでは」と気付いて整える | **最初から公開が目的**。開発そのものが作業 |
| 主なリスク | **切り出しで壊れる** ―― cwd 依存の相対パス・リポ固有の前提・plugin 外への参照が、生まれた場所では偶然動いていた（→ §1-2 / §8） | **使われないものを作る** ―― 実運用の裏付けが無いまま公開しうる（→ §2-3） |
| 動作の裏付け | 既存リポでの**実使用実績**がある（強い） | **意図的に作る必要がある**（dogfooding / eval） |

> **どちらでもない場合**: 「既存リポで作ったが、そのリポの中だけで使い続ける」なら公開工程は不要で、[§6 skill 単体](#skill-only-dev)だけで完結する。本書の §1 以降は**配る意思が固まってから**の手順。

<a id="core-flow"></a>

### 0-2. 共通コアと分岐点

```
シナリオ A（派生型）                     シナリオ B（公開先行型）
既存リポの .claude/ に実体あり            着想のみ
      │                                        │
 [A-1] 生まれた場所で動く状態にする         [B-1] 開発リポジトリを決める      ← §2-1
      │                                        │
 [A-2] 「配れるか」を棚卸しする             [B-2] 最初から公開レイアウトで作る
      │  （汎用性 / リポ固有依存 / 秘匿）         │
 [A-3] 公開形態を選ぶ  ────────────────┬─── [B-3] 実運用の裏付けを取る
      │        （§4: 3 形態から）           │        （dogfooding / eval）
      └────────────────┬────────────────┘
                              ▼
                    ═══ 共通コア（§3）═══
        ① plugin 化（.claude-plugin/plugin.json）
        ② ローカルでテスト（claude --plugin-dir）
        ③ 反映ループ（/reload-plugins）
        ④ 公開前バリデーション（claude plugin validate --strict）
        ⑤ 導線検証【必須】（marketplace add → plugin install）  ← validate では検出できない
        ⑥ 公開・版タグ（git push / claude plugin tag）
```

**原則**: 開発・テストは**手元で完結**させる。Marketplace は**配布の器であり、開発の場ではない**。この原則は両シナリオに共通で、シナリオ B で「専用の開発リポジトリを立てるべきか」を考えるときの前提でもある（§2-1）。

<a id="repos"></a>

### 0-3. 登場するリポジトリ

| 記号 | リポジトリ | 役割 |
|---|---|---|
| **(A)** | **開発・テストリポジトリ** | plugin の中身を作り込み、ローカルでテストする場所。**plugin 化はここで行う**。シナリオ A では「資産が生まれた既存リポ」、シナリオ B では §2-1 で決める |
| **(B)** | **配布専用リポジトリ（Marketplace）のローカルクローン** | 公開先。完成品を受け取るだけで、**ここでは開発しない** |
| **(C)** | **ローカル marketplace（"見なし公開"）** | 配布形態（install 挙動）を手元で検証するための `marketplace.json` 入りディレクトリ。(A) を兼ねてもよいし、検証用に別ディレクトリを作ってもよい |

> **(A) と (B) の関係はリポジトリ構成で変わる**:
> - **monorepo** … 1 リポジトリが開発・テストも配布も兼ねる。**(A) = (B)**（同一リポのローカル作業コピーと remote の関係）。ローカルではそれを `--plugin-dir` / `marketplace add .` でテストし、`git push` で公開。
> - **multi-repo** … plugin 開発リポ (A)（複数可）と、薄い marketplace リポ (B) を分離。開発・テストは各 (A) でローカルに行い、(B) は参照を束ねるだけ。
>
> **`git-subdir` source（→ §4）を使うと (B) は `marketplace.json` 1 ファイルだけで成立する** ―― plugin の実体を (B) にコピーする必要が無くなり、multi-repo の「薄い配布リポ」を文字どおり薄くできる。

<a id="publish-forms-quick"></a>

### 0-4. 公開形態は 3 つある（早見）

同じ資産でも、**どういう形で配るか**は 3 通りあり、開発の進め方が変わる。詳細と選び方は **[§4](#publish-forms)**。

| 形態 | 実体の置き場所 | 利用者の導入操作 | 主な用途 |
|---|---|---|---|
| **① 層1 直配り（素の skill）** | `<repo>/.claude/skills/<name>/` | リポジトリを clone / submodule / `--add-dir` | リポジトリと運命を共にする資産 |
| **② `@skills-dir`（案B''）** | 同上に `.claude-plugin/plugin.json` を**足すだけ** | 同上（**install 不要・ネットワーク不要**） | ①のまま hooks / agents / MCP も束ねたいとき |
| **③ Marketplace plugin** | 任意（`git-subdir` で ①②の現物を直接指せる） | `plugin marketplace add` → `plugin install` | 版管理して配りたい・リポジトリを配りたくない |

---

## 1. シナリオ A ―― 既存リポジトリの活動から派生させて公開する

> 現行の資産（`.claude/skills/<name>/` 等）が**すでに動いている**ところから始める。旧版 v1.3 の①がここに相当する。

<a id="a1"></a>

### 1-1. 生まれた場所で動く状態にする

> ここでの **「standalone」は「plugin にしていない素の構成」という状態の呼称**（公式語 "standalone configuration in `.claude/`"）。`.claude/` は**任意のローカル開発リポジトリ (A) の直下**に置くフォルダを指す。

通常の `.claude/` 配下に資産を置いて動かし、素早く試行錯誤する。**この段の「試行錯誤」には、plugin 化前の動作検証（編集→実行→確認の反復で「共有・配布できるレベル」に仕上げるテスト）が含まれる**。skill であれば後述の `skill-creator` で eval を回すのもこの段。

```
my-tool/                     # 手元の開発リポジトリ（=作業ディレクトリ）
└── .claude/
    ├── skills/hello/SKILL.md
    ├── commands/foo.md
    └── agents/bar.md
```

この段階では `claude` を `my-tool/` で起動すれば資産はそのまま有効。skill は `SKILL.md` を編集すると**セッション内で即時反映**される。

<a id="a2"></a>

### 1-2. 「配れるか」を棚卸しする（シナリオ A 固有・最重要）

シナリオ A の資産は**生まれた場所の前提に無自覚に依存している**。公開形態を決める前に、次を機械的に洗い出す。ここを飛ばすと「手元では動くのに配ると壊れる」が必ず起きる。

- [ ] **cwd 依存の相対パス**（`./scripts/…`・`../shared/…`）が無いか → **§8-1**。生まれた場所では cwd＝リポジトリルートなので偶然動く。
- [ ] **リポジトリ固有の前提**が本文・スクリプトに埋まっていないか（そのリポのブランチ規約・フォルダ構成・特定ファイル名の存在を前提にした処理）。**残すなら「前提」として明示**し、汎用化するなら引数・設定に外出しする。
- [ ] **plugin ディレクトリの外への参照**が無いか（`templates/` や共通スクリプトを skill フォルダの外に置いていないか）→ **§8-1**。
- [ ] **書き込み先が自分のフォルダ配下になっていないか**（ナレッジ蓄積・キャッシュ）→ **§8-2**。
- [ ] **秘匿情報・マシン固有パス**が混じっていないか（個人の絶対パス・トークン・社内ホスト名）。
- [ ] **依存する他の資産**（同じリポの rule / CLAUDE.md / 別 skill）が無いか。**`CLAUDE.md` と `rules/` は plugin では配れない**（[配布計画 §1](../../04.資産インベントリ・統合/02.配布計画/配布計画_Plugin可否とリポジトリ割当.md)）。依存があるなら skill 本文へ内包するか、配布対象から外す。
- [ ] **そのリポジトリでしか意味を持たない資産ではないか**（テーマ特化資産は据え置きが原則。[配布計画 §2-B](../../04.資産インベントリ・統合/02.配布計画/配布計画_Plugin可否とリポジトリ割当.md)）。

<a id="a3"></a>

### 1-3. 公開形態を選ぶ

**[§4](#publish-forms)** の判断表で ①／②／③ を選ぶ。シナリオ A では、**資産を今の場所から動かさずに済む ② と ③（`git-subdir`）が第一候補**になることが多い ―― 既存の利用者（そのリポを clone / `--add-dir` している人）の呼び名 `/<name>` を壊さずに、plugin としての配布経路を**足す**ことができる（実測: [調査結果 §9(2) セル 4・5](./Plugin・Marketplace配布物の開発・テスト_調査結果.md#single-entity)）。

③のうち「別の plugin ツリーへコピーして配る」形を選ぶ場合は、**元の場所に原本を残すか消すかを必ず決める**。両方残すと、両方を導入した利用者の context に同じ内容が二重に載る（[§4-3](#dual-warning)）。

<a id="a4"></a>

### 1-4. 実装規約へのレトロフィット

§1-2 で洗い出した依存を、**[§8 の実装規約](#impl-rules)** に合わせて直す。特に:

- パス参照を `${CLAUDE_SKILL_DIR}` / `${CLAUDE_PLUGIN_ROOT}` へ置き換える（§8-1）
- 書き込み先を `${CLAUDE_PLUGIN_DATA}` かプロジェクト側へ逃がす（§8-2）
- 利用者に読ませる README は `homepage` / リポジトリで見せる導線にする（§8-3）

直したら**元の場所でもう一度動かして回帰が無いことを確認する**（`${CLAUDE_SKILL_DIR}` は素の skill でも解決されるので、置き換えても層1 利用は壊れない）。

<a id="a5"></a>

### 1-5. 呼び名の変化を利用者へ伝える

**plugin 経由で入れた利用者の呼び名は `/<plugin>:<skill>` になる**（frontmatter の `name` が最終セグメント。衝突が無ければ bare の `/<skill>` も併用できる）。層1 のまま使う利用者は `/<name>` のまま。**両方の呼び名を README に併記する**。

そのまま §3 の共通コアへ進む。

---

## 2. シナリオ B ―― 公開前提で新規に開発し、公開まで一気に実施する

> 「公開したい Skill／スクリプトを思いついた。その開発自体が作業」という入口。実体がゼロなので、**最初の判断は「どこで開発するか」**になる。

<a id="b1"></a>

### 2-1. 開発リポジトリを決める（判断フロー）

**新しいリポジトリを立てる前に、まずこの 3 問に答える。**

```
Q1. その資産は「チーム共通の .claude/ の一部」になるか？
    （＝配布キット利用者全員に無条件で入ってよいものか）
      YES → <Dev>（配布開発源リポジトリ）の .claude/skills/<name>/ で開発する。
             以後はシナリオ A の出口と同じレールに合流する
             （層1 body ＋ 層2 を §4 の②③で単一実体化）。
      NO  ↓
Q2. 単発・独立の資産か？（特定の人・特定の用途向け。全員には要らない）
      YES → <Dev> の「配布 payload の外」に開発エリアを作る。
             例: <Dev>/plugins/<name>/  ← .claude/ 配下ではないので層1 には流れない。
             配布は Marketplace（層2）だけ。
      NO  ↓
Q3. 独自のリリースサイクル・外部コントリビュータ・大きなコードベースを持つか？
      YES → その資産専用のリポジトリを新設する。
             Marketplace からは git-subdir / url source で参照する。
```

> **判断は後から取り消せる。最初は軽い選択でよい。** `git-subdir`（→ §4）は**任意のリポジトリの任意のサブディレクトリ**を plugin として参照できるため、資産が育って独立リポジトリへ引っ越しても、**marketplace エントリの `url` / `path` を書き換えるだけ**で済み、利用者の `plugin install <name>@<mp>` は変わらない。**「最初に専用リポジトリを新設するか」を重い判断にしない**こと。

> **⚠ 配布雛型リポジトリ（利用者が clone する側）を開発ワークスペースにしてはならない。** そこは利用者側の入口であり、開発の作業ブランチや中間成果物が混ざると配布物の性格が濁る。本テーマにおける各リポジトリの役割は [インベントリ §0](../../04.資産インベントリ・統合/01.全マシン資産インベントリ/配布可能資産インベントリ.md) と [配布計画 §3](../../04.資産インベントリ・統合/02.配布計画/配布計画_Plugin可否とリポジトリ割当.md) を正とする。

<a id="b2"></a>

### 2-2. 最初から公開レイアウトで作る

シナリオ A と違い、**最初から plugin の形で作れる**のがシナリオ B の利点。§1-2 の棚卸しを後追いでやらずに済むよう、**§8 の実装規約を最初から適用する**。

雛形生成（scaffold）を使うと早い:

```bash
claude plugin init my-tool
# → ~/.claude/skills/my-tool/ に plugin.json + starter SKILL.md を生成
#   次セッションで my-tool@skills-dir として自動ロード（install 不要）
```

`claude plugin init` は **personal scope（`~/.claude/skills/`）** に作る。そこで骨格を固めてから §2-1 で決めたリポジトリへ移す運用が扱いやすい（personal scope には workspace trust のゲートが無いため、試作の反復が軽い）。

より本格的に、対話で設計を詰めながら作りたい場合は **[§7 の `plugin-dev`](#plugin-dev)**（純正ツールキット）の `/plugin-dev:create-plugin` が使える。

<a id="b3"></a>

### 2-3. 実運用の裏付けを取る（シナリオ B 固有・最重要）

シナリオ A が持っている「既存リポでの実使用実績」が、シナリオ B には**無い**。ここを埋めないまま公開すると、動きはするが使われないものが出来る。少なくとも次のどれかを通す:

- **dogfooding**: 開発リポジトリまたは自分の実作業で `--plugin-dir` 経由で実際に使い、**現実的なプロンプト**で回す。
- **eval**: skill なら **[§6 の `skill-creator`](#skill-only-dev)** で test case・grading・benchmark を回す。**skill 有り／無しの baseline 比較**が公式の検証法。`claude plugin eval` は plugin・`@skills-dir` plugin のどちらも target に取れ、no-plugin の baseline arm を自動で足す。
- **description のチューニング**: 自動発火させたい skill は、`skill-creator` の description tuning で should-trigger / should-not-trigger の発火率を測る。

> **「動いた」と「意図どおり動いた」は別**。発火したことの確認だけで完了にしない。

<a id="b4"></a>

### 2-4. 公開まで一気に通す

シナリオ B は「公開まで一気に実施する」ことが前提なので、**公開経路が実際に通ることを先に確かめる**。§3 の共通コア、特に **§3-6 の導線検証を省略しない**こと ―― `claude plugin validate` は相対 `source` の解決失敗を検出しないため、validate だけを根拠に「配れる」と判断すると、公開してから利用者の `install` が落ちる。

---

## 3. 共通コア ―― plugin 化 → テスト → 検証 → 公開

> ここから先はシナリオ A / B 共通。

<a id="c1"></a>

### 3-1. plugin 化

共有・配布する段になったら、plugin のマニフェストを付与して plugin ディレクトリ化する。**この作業は開発・テストリポジトリ (A) の中で行う**（配布専用リポのクローン (B) で開発しない。(B) は完成品を受け取るだけ）。

```
my-plugin/
├── .claude-plugin/
│   └── plugin.json          # name / version / description / author などのメタdata
├── skills/my-skill/
│   ├── SKILL.md             # ユーザー起動コマンドも新規はここ（skills/）に作る
│   ├── README.md            # 利用者向け説明（※cache 内は UI から閲覧不可 → §8-3）
│   ├── references/          # skill が処理中に参照するナレッジ（読み取り専用前提 → §8-2）
│   ├── templates/           # skill が生成する成果物のひな型
│   └── scripts/*.py         # skill が呼ぶスクリプト（パスは ${CLAUDE_SKILL_DIR} 解決 → §8-1）
├── agents/bar.md
└── hooks/hooks.json         # 必要なら（スクリプト本体は ${CLAUDE_PLUGIN_ROOT} 参照で同梱）
```

> 補足（**v2.1.235 版(2026-08-19)**）: skill が1つだけの plugin なら、`skills/<name>/SKILL.md` を作らず `SKILL.md` を plugin ルート直下に置くだけでもよい（frontmatter の `name` が呼び出し名になる。`docs/plugins`「Plugin structure overview」）。**この形は §4 の②（`@skills-dir`）と同じ形**なので、`.claude/skills/<name>/` をそのまま plugin にしたいときに使う。また、`hooks/hooks.json` と並ぶ正式なコンポーネントとして `workflows/`（バックグラウンドで動く dynamic workflow のスクリプト置き場）も plugin root 直下に置ける（`docs/plugins-reference`）。

`plugin.json` の最小例（**`author` はオブジェクト型**で書く点に注意。文字列だと `claude plugin validate` が `expected object, received string` で失敗する）:

```json
{
  "name": "my-plugin",
  "version": "0.1.0",
  "description": "...",
  "author": { "name": "チーム名" }
}
```

> ⚠️ **plugin ディレクトリの外を参照しない**こと。install 時に plugin ディレクトリだけがキャッシュへコピーされるため、`../shared/...` のような外部参照は配布後に壊れる。共有したいファイルは plugin 内に収める。
>
> 📌 **`commands/` はレガシー形式**: 公式の `plugin-dev` は「新規のユーザー起動スラッシュコマンドは `commands/*.md` ではなく `skills/<name>/SKILL.md` で作る」ことを推奨する（両者はロード挙動が同一で、差はファイルレイアウトのみ。`commands/` は既存 plugin 保守時の許容レガシー）。新規 plugin では `skills/` に寄せる。

> 🧩 **配布前提のスクリプト・同梱ファイル（references/ templates/ scripts/ README）には実装規約がある**: plugin 化すると実行場所が `<repo>\.claude` でなく cache（`~/.claude/plugins/cache/…`）になり、パス解決・書き込み先・README 提示に制約がつく（cwd 依存の相対パスは壊れる）。**新規に skill＋スクリプトを作る前に §8 を必読**。

<a id="c2"></a>

### 3-2. ローカルでテスト: `--plugin-dir`（marketplace 登録なしで直接ロード）

```bash
# 単体
claude --plugin-dir ./my-plugin

# 複数同時
claude --plugin-dir ./plugin-one --plugin-dir ./plugin-two

# .zip アーカイブ
claude --plugin-dir ./my-plugin.zip

# CI ビルド成果物などの URL から
claude --plugin-url https://example.com/builds/my-plugin.zip
```

- インストール済みの同名 plugin があっても、**`--plugin-dir` のローカルコピーがそのセッションで優先**される（アンインストール不要で変更をテストできる）。
- **`.claude/skills/<name>/`（②の形）をそのまま `--plugin-dir` に渡してもよい**（実測: [調査結果 §9(2) セル 6](./Plugin・Marketplace配布物の開発・テスト_調査結果.md#single-entity)）。plugin 化のために場所を移す必要はない。
- 起動後、`/plugin-name:skill-name` で skill を試す、`/context` の Custom Agents 欄で agent が登録されているか確認する（または `@plugin-name:agent-name` で明示的にメンションする）、hook は対象イベントを実際に発火させて効果を確認する（`claude --debug` の記録と合わせて確認）。
  > ⚠️ **`/agents` は動作確認に使えない（v2.1.235 版(2026-08-19)）**: v2.1.198 以降、`/agents` は subagent の一覧・管理インタフェースではなく、単なる案内メッセージを表示するだけになった（`docs/commands`「All commands」）。plugin agent のロード確認は上記の `/context` か @-mention を使う。

> **非対話でロード状況だけを確認したいとき**: `claude -p "x" --debug` を走らせ、`~/.claude/debug/<session-id>.txt`（`CLAUDE_CONFIG_DIR` を設定していればその配下）の起動ログを見る。`Loaded N unique skills (… project: N, additional: N …)` / `Found N plugins` / `Total plugin skills loaded: N` の行が、**どの経路から何個ロードされたか**をモデル出力に依存せず示す。**設定ロードは認証より前に走る**ため、隔離した `CLAUDE_CONFIG_DIR` で `Not logged in` になっても証跡は取れる（[調査結果 §9](./Plugin・Marketplace配布物の開発・テスト_調査結果.md#single-entity) の手法）。

<a id="c3"></a>

### 3-3. ローカル marketplace（配布形態ごと検証）

配布したときの install 挙動まで確認したい場合は、ローカルディレクトリを marketplace 化する。

```
my-mp/                       # ローカル marketplace
├── .claude-plugin/
│   └── marketplace.json     # name + owner(必須) + plugins
└── plugins/
    └── my-plugin/ …
```

> ⚠️ **`.claude-plugin/` は marketplace のルート直下に置く**。相対 `source` は「`.claude-plugin/` を含むディレクトリ」を起点に解決されるため、`marketplace/.claude-plugin/` と `plugins/` を兄弟に置くと `source: "./plugins/..."` が解決できない。**この誤りは `claude plugin validate --strict` を通過する**（実装テンプレートで実際に起きた。[実装テンプレート README](../../03.実装テンプレート（層1+2）/README.md)）。

`marketplace.json` の最小例（**`owner` は必須・オブジェクト型**。欠けると `claude plugin validate` が `owner: expected object, received undefined` で失敗する）:

```json
{
  "name": "my-mp",
  "owner": { "name": "チーム名" },
  "plugins": [{ "name": "my-plugin", "source": "./plugins/my-plugin" }]
}
```

```bash
# CLI から
claude plugin marketplace add ./my-mp
claude plugin install my-plugin@my-mp

# もしくはセッション内コマンド
/plugin marketplace add ./my-mp
/plugin install my-plugin@my-mp
```

> `source: "./..."` の相対参照は**git 経由の追加**または**ローカルディレクトリとしての追加**でのみ機能する（直接 URL で `marketplace.json` を追加する URL-based marketplace では不可）。**v2.1.235 版(2026-08-19)**: 非git配布の新しい source 種別 `archive`（v2.1.224+）・`command`（v2.1.229+）も追加された。**サブディレクトリを直接指す `git-subdir` については §4 を参照**。詳細は[調査結果報告書 §3(3)](./Plugin・Marketplace配布物の開発・テスト_調査結果.md#repo-relation)。

> **個人環境を汚さずに検証したいとき**: `CLAUDE_CONFIG_DIR` を作業用ディレクトリに向けてから `marketplace add` / `install` する。marketplace 登録・install 済み plugin・cache がすべてそこに閉じるので、検証後はディレクトリごと捨てられる。**ただし認証情報は引き継がれない**（対話セッションは使えない。ロード確認だけなら §3-2 の起動ログで足りる）。

<a id="c4"></a>

### 3-4. 反映（編集 → 確認のループ）

| 変更した対象 | 反映方法 |
|---|---|
| skill の `SKILL.md` | **即時**（操作不要） |
| plugin の hooks / `.mcp.json` / agents / output-styles | `/reload-plugins` |
| plugin / skill / agent / hook / MCP / LSP 全般 | `/reload-plugins`（再起動不要で全再読込） |

> ⚠️ **既知の表示上の癖（v2.1.235 版(2026-08-19)）**: `/reload-plugins` 実行後のサマリに出る「skills」件数は plugin の `commands/` ディレクトリのみをカウントしており、`skills/` ディレクトリの再読込結果を反映しない（`docs/plugins`「Create your first plugin」）。そのため `skills/` だけで作った skill しか無い plugin では、実際は再読込に成功していても `0 skills` と表示されることがある。件数表示だけで「反映されていない」と誤診断せず、実際に `/plugin-name:skill-name` を呼んで動作確認すること。

<a id="c5"></a>

### 3-5. 公開前バリデーション

```bash
# plugin 単体を検証（plugin.json + skill/agent/command/hook の frontmatter・hooks.json 構文）
claude plugin validate ./my-plugin

# marketplace を検証（marketplace.json の schema・重複名・source パストラバーサル・バージョン不整合）
claude plugin validate ./my-mp

# CI 用: 警告もエラー扱い（未承認フィールド・メタデータ欠落等で exit 1）
claude plugin validate ./my-plugin --strict
```

- **公開審査のある Marketplace（本家 `claude-plugins-official` / コミュニティ）へ提出する場合は必須**。レビューパイプラインが提出ごとに同じ検査＋自動セーフティスクリーニングを回すため、ローカルで通しておくのが提出の前提。
- **private な独自 Marketplace（チーム内に閉じる）では審査パイプラインが無いので必須ではない**。ただし schema・構造・バージョン不整合をローカルで弾けるので**実行を推奨**（CI に組み込むと安全）。
- **⚠ `validate` は「配れること」を保証しない**。相対 `source` の解決失敗（§3-3 の構造誤り）は `--strict` でも通過する。→ **§3-6 を必ず通す**。
- ロードがうまくいかない時のデバッグ:

```bash
claude --debug                  # デバッグログ（ファイル出力）。出力先は ~/.claude/debug/<session-id>.txt
claude --debug='mcp,startup'    # カテゴリを絞る場合は = 結合＋カンマ区切りが必須（スペース区切りはフィルタとして機能しない）
# hook の評価を詳しく見たい場合は CLAUDE_CODE_DEBUG_LOG_LEVEL=verbose を併用
# /plugin の Errors タブでも LSP パスエラー等を確認できる
```

> ⚠️ **v2.1.235 版(2026-08-19)**: `--debug` のカテゴリフィルタは `=` で結合した形（例: `--debug='mcp,startup'`）のときだけ機能し、`claude --debug mcp` のようにスペース区切りで渡すとフィルタとして機能せず単にデバッグモードを有効化するだけになる（`docs/cli-reference`「CLI flags」）。`hooks` という専用カテゴリの案内は現行 docs には無く、hook 評価の詳細は `CLAUDE_CODE_DEBUG_LOG_LEVEL=verbose` で粒度を上げて確認する。

<a id="c6"></a>

### 3-6. 導線検証【必須】 ―― `marketplace add` → `install` まで通す

**`claude plugin validate` をパスしただけでは「配れる」と言えない。** 公開前に、**利用者と同じ操作を最後まで実行**して初めて配布可能と判断する。

```bash
# 個人環境を汚さないよう隔離してから実施することを推奨
export CLAUDE_CONFIG_DIR=/tmp/cc-verify        # PowerShell: $env:CLAUDE_CONFIG_DIR="..."

claude plugin marketplace add <公開する marketplace のパス or URL>
claude plugin install <name>@<marketplace>
claude plugin list --json                       # id / version / scope / installPath を確認
claude plugin details <name>@<marketplace>      # コンポーネントが期待どおり入っているか
```

**確認すること**:

- [ ] `marketplace add` が成功する（`Marketplace file not found` なら `.claude-plugin/marketplace.json` の位置が誤り）
- [ ] `install` が成功する（ここで初めて相対 `source` / `git-subdir` の解決が試される）
- [ ] `plugin list` の **`version` が期待どおり**（版が付かない場合は §4-4 を参照）
- [ ] `plugin details` のコンポーネント一覧に skill / agent / hook が**期待の個数**で並ぶ
- [ ] cache に**必要なファイルが揃っている**（同梱スクリプト・references が落ちていないか）
- [ ] uninstall → 再 install しても同じ結果になる

<a id="c7"></a>

### 3-7. 公開と版管理

検証を通したら、配布専用リポジトリへ push する。

```bash
# 版タグを打つ（plugin.json と marketplace エントリの版が食い違っていないか検証してくれる）
claude plugin tag ./my-plugin --dry-run          # まず確認
claude plugin tag ./my-plugin -m "release %s"    # {name}--v{version} の tag を作成
claude plugin tag ./my-plugin --push             # tag を remote へ
```

利用者側:

```bash
/plugin marketplace add <github-repo-or-git-url>
/plugin install <name>@<marketplace>
```

> **リリースチャネル**（先行検証グループと本番グループを分けたい場合）は、同じリポジトリの別 ref を指す marketplace を 2 つ用意して managed settings でグループに割り当てる。**2 つの ref が同じ version 文字列に解決されると更新がスキップされる**罠があるため、ref ごとに version を変えること。詳細は [レーンA確定書 §6-bis](../../04.資産インベントリ・統合/04.ランチャースクリプト実装/配布・リリース設計確定_レーンA.md)。

---

<a id="publish-forms"></a>

## 4. 公開形態の選択（3 形態の比較）

> 本節の挙動はすべて **CLI v2.1.237 の実機で確認済み**。証跡と手法は [調査結果 §9](./Plugin・Marketplace配布物の開発・テスト_調査結果.md#single-entity)。

### 4-1. 3 形態の比較表

| | **① 層1 直配り（素の skill）** | **② `@skills-dir`（案B''）** | **③ Marketplace plugin** |
|---|---|---|---|
| 実体 | `<repo>/.claude/skills/<name>/SKILL.md` | ①に `.claude-plugin/plugin.json` を足すだけ | plugin ディレクトリ（②の現物を `git-subdir` で指してもよい） |
| 利用者の導入 | clone / submodule / `--add-dir` | 同左（**install もネットワークも不要**） | `marketplace add` → `plugin install` |
| 呼び名 | `/<name>` | `/<name>`（**①のまま変わらない**） | `/<plugin>:<skill>`（衝突が無ければ bare 形も可） |
| hooks / agents / MCP の同梱 | ✗ | **✓** | **✓** |
| 版管理（version） | リポジトリの ref | plugin.json の `version`（ロード時は使わない） | **✓ `plugin.json` の version・`claude plugin tag`** |
| 更新の届き方 | `git pull` / submodule bump | 同左 | `plugin update`（利用者操作） |
| 前提条件 | なし | **workspace trust の受諾が必要**（project scope）／**リポジトリルートから起動**／monitors は非ロード | ネットワーク（or ローカルパス）・marketplace の存在 |
| `--add-dir` 経由 | ✓ 素の skill としてロード | **✓ 素の skill としてロード**（plugin にはならない） | ― |

### 4-2. 選び方

- **既存資産を今の場所から動かしたくない** → **② または ③（`git-subdir`）**。②を足しても①の利用者の呼び名は変わらない（非破壊）。
- **hooks / agents / MCP も一緒に配りたいが、install はさせたくない** → **②**。
- **版を切って配りたい／利用者にリポジトリ自体は渡したくない** → **③**。
- **チーム全員に無条件で入れたい（統制寄り）** → ①＋②（層1）。managed settings で強制したいなら ③（`enabledPlugins`）。

<a id="git-subdir"></a>

### 4-3. `git-subdir` ―― 実体 1 つ・参照 2 通りに畳む

`git-subdir` source は、**任意の git リポジトリの任意のサブディレクトリ**を plugin として参照する。取得は sparse・partial clone なので、大きなリポジトリでもそのサブディレクトリだけが落ちてくる。

```json
{
  "name": "commit-and-pr",
  "source": {
    "source": "git-subdir",
    "url": "https://github.com/acme/base-dev-kit.git",
    "path": ".claude/skills/commit-and-pr",
    "ref": "v1.0.1"
  }
}
```

これにより、**`<repo>/.claude/skills/<name>/` という 1 つのディレクトリが、層1 body としても、`@skills-dir` plugin としても、Marketplace plugin としても消費される**。plugin ツリーへのコピーも、別リポジトリへの publish も要らない。配布専用リポジトリは `marketplace.json` 1 ファイルだけで成立する。

<a id="dual-warning"></a>

**⚠ ただし「単一の消費形態」にはならない。層1 と層2 の両方を同じ利用者に入れさせないこと。**

- plugin どうしの同名衝突は CLI が抑止する（marketplace 版が優先され、`@skills-dir` 版は自動で `enabled:false` になる）。
- **しかし素の project skill は残る**ため、リポジトリを checkout しつつ同名 plugin を install した利用者には、`/<name>`（素の skill）と `/<plugin>:<skill>`（plugin skill）が**同じ内容で二重に context へ載る**。
- 公式も「plugin へ移行したら `.claude/` 側の原本を削除せよ」と明記している。**配布側は「層1 で使うか層2 で使うか」を利用者に一つ選ばせる**設計にする（README とインストール手順で明示する）。

### 4-4. 実装上の注意

- **`plugin.json` を持たないディレクトリも `git-subdir` で install できてしまう**が、その場合 **version を持たない**（cache パスが commit SHA 由来になる）。`claude plugin tag` による版管理レールに乗らないので、**配るものには必ず `plugin.json` を置く**。
- **② の前提条件を README に書く**。project scope の `@skills-dir` plugin は (a) workspace trust の受諾が必要（**親フォルダの trust では不十分で、ダイアログも出ない**）、(b) **リポジトリルートから起動したときだけ**検出される（サブディレクトリからの起動では読まれない。`/reload-plugins` で回復可）、(c) **background monitors は読まれない**。
  - 対話ダイアログを出せない環境では、`~/.claude.json` の `projects["<リポジトリルート>"].hasTrustDialogAccepted` を `true` にする手動受諾が公式の回避策。
- **`.claude` が submodule でも、外側リポジトリの trust だけで project scope としてロードされる**（実測）。`.claude` を submodule 化した配布形態と② は両立する。

---

<a id="cheatsheet"></a>

## 5. 起動オプション・コマンド早見表

### 起動オプション（CLI フラグ）

| フラグ | 用途 |
|---|---|
| `--plugin-dir <path>` | plugin を marketplace 登録なしで直接ロード（**開発の主手段**）。`.zip` 可・反復指定で複数 |
| `--plugin-url <url>` | URL（CI 成果物等）から plugin をロード |
| `--add-dir <dir>` | 追加ディレクトリのファイルアクセスを付与。**`<dir>/.claude/skills/` は自動ロードされる**（skill テストの結合に有用）。**`.claude-plugin/plugin.json` があっても plugin にはならず、素の skill としてロードされる** |
| `--debug` | **汎用デバッグログ（`~/.claude/debug/<session-id>.txt` にセッション単位で出力）**。plugin の場合はロード詳細・manifest エラーを見られるが、**ロード時専用ではない**——ロード後の実行時イベントも対象。**v2.1.235 版(2026-08-19)**: カテゴリを絞る場合は**`=` 結合＋カンマ区切りが必須**（例: `--debug='mcp,startup'`）。スペース区切り（例: `--debug mcp`）は**フィルタとして機能せず**、単にデバッグモードを有効化するだけ。hook 評価の詳細確認は `CLAUDE_CODE_DEBUG_LOG_LEVEL=verbose` を併用する |

> `--add-dir` で渡すのは「`.claude/` を内包する親フォルダ」。フォルダ名自体を `.claude` にすると `<dir>/.claude/.claude/` を探して読まれないので注意。
> **`--add-dir`（フラグ／`/add-dir`）で `<dir>/.claude/` から自動ロードされる設定**（公式 `docs/permissions` の表）: **skills（`.claude/skills/`・live reload）／subagents（`.claude/agents/`・v2.1.178+。v2.1.165 までは非ロード）／commands（`.claude/commands/`・**v2.1.235 版(2026-08-19) で追加**。live reload なし。追加ディレクトリとプロジェクト側で同名 command がある場合はプロジェクト側が優先）**、および `settings.json` のうち **`enabledPlugins` / `extraKnownMarketplaces` のみ**。`CLAUDE.md` / `rules` / `CLAUDE.local.md` は環境変数 `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1` を付けた時だけ読まれる。`settings.json` のそれ以外のキー（permissions/hooks 等）・output-styles は読まれない。
> **正本**: 版依存の事実（subagents の版境界・commands の追加時期・`settings.local.json` を含む2キー例外）は [v1.2 付録B『`--add-dir` 例外ロード一覧（正本）』](../../01.配布・統制方針調査/結論・構成案_ポータブルな.claude共有_v1.2.md#adddir-exceptions) を正とする（本注記は運用早見。詳しい根拠は [調査結果報告書 §4](./Plugin・Marketplace配布物の開発・テスト_調査結果.md#skill-only)）。
> ⚠️ `permissions.additionalDirectories` 設定経由ではこれら例外は**一切**読まれず、ファイルアクセス付与のみ（自動ロードは `--add-dir` フラグ／`/add-dir` 限定）。

### セッション内 / CLI コマンド対応

| 操作 | セッション内 | CLI |
|---|---|---|
| marketplace 追加 | `/plugin marketplace add <source>` | `claude plugin marketplace add <source>` |
| marketplace 一覧 | `/plugin marketplace list` | `claude plugin marketplace list` |
| marketplace 更新 | — | `claude plugin marketplace update [name]` |
| plugin インストール | `/plugin install <name>@<mp>` | `claude plugin install <name>@<mp>` |
| plugin 一覧 | `/plugin` | `claude plugin list [--json] [--available]` |
| plugin の中身確認 | — | `claude plugin details <name>@<mp>`（コンポーネント一覧＋トークンコスト） |
| バリデーション | `/plugin validate <path>` | `claude plugin validate <path>` |
| 変更の再読込 | `/reload-plugins` | —（セッション内専用） |
| skill の雛形生成（scaffold） | — | `claude plugin init <name>` |
| 版タグ作成 | — | `claude plugin tag [path] [--dry-run\|--push]` |
| eval 実行 | — | `claude plugin eval [target]` |

> ⚠️ `/reload-plugins` のサマリに出る「skills」件数は plugin の `commands/` ディレクトリのみをカウントする既知の表示上の癖がある（詳細は §3-4 を参照）。`skills/` のみで作った plugin では実際は反映されていても `0 skills` と表示されうるため、件数だけで判断しないこと。
>
> **「scaffold（スキャフォールド）」= 雛形生成**。`claude plugin init <name>` は `~/.claude/skills/<name>/` に `.claude-plugin/plugin.json` と starter `SKILL.md`（土台一式）を自動生成し、次セッションで `<name>@skills-dir` として自動ロードする。ゼロからファイルを手書きせず、編集すればよい状態の雛形を作る操作。
>
> **`claude plugin validate` が具体的にチェックする内容**（出典は[調査結果報告書 §5](./Plugin・Marketplace配布物の開発・テスト_調査結果.md)）:
> - **marketplace ディレクトリ対象**: `marketplace.json` の schema、plugin 名の重複、`source` のパストラバーサル、各 `plugin.json` とのバージョン不整合
> - **plugin ディレクトリ対象**: skill / agent / command の YAML frontmatter、`hooks/hooks.json` の JSON 構文
> - **チェックしないもの**: **相対 `source` が実際に解決できるか**（→ §3-6 の導線検証が必要）

---

<a id="skill-only-dev"></a>

## 6. skill 単体を開発・テストする場合（plugin に包まない）

> **位置づけ**: 本セクションは2つの面を持つ。(1) plugin 化せず `.claude/skills/` 単体で skill を作り込む作業は、**シナリオ A の §1-1「生まれた場所で動く状態にする」に相当**する（ここで skill を仕上げ、配るなら §3 以降へ進む）。(2) 同時に、skill 単体は **plugin 化せず層1 commit でそのまま配る独立ルート（§4 の①）**でもあり、その場合は §3 以降に進まない。

plugin 化せず `.claude/skills/` 単体で配る skill は、開発がさらに軽い。

- **配置**: project `.claude/skills/` ／ `~/.claude/skills/` ／ `--add-dir` 配下の `.claude/skills/` のいずれかに置けば自動ロード。
- **反映**: `SKILL.md` の編集は**即時**（`/reload-plugins` 不要）。
- **呼び出し**: `/skill-name`（plugin 同梱だと `/plugin-name:skill-name` と名前空間が付く）。
- **動作確認の考え方**: skill が「発火した」ことと「意図どおり動いた」ことは別。**skill 有り／無効化の 2 セッションで同じ現実的プロンプトを流して baseline 比較**するのが公式の検証法。

### 支援ツール: `skill-creator` プラグイン（純正）

skill の eval ループを Claude Code 内で自動化する純正プラグイン。

```bash
# 初回対話起動前の CI・非対話環境では未登録のことがあるため、必要なら先に:
# claude plugin marketplace add anthropics/claude-plugins-official
/plugin install skill-creator@claude-plugins-official
/reload-plugins
# 例: 「evaluate my summarize-changes skill with skill-creator」と依頼すると eval ループが走る
```

> **v2.1.235 版(2026-08-19)**: `claude-plugins-official` はマシン初回の対話起動時に自動登録される。CI・非対話（ヘッドレス）環境で先に実行すると未登録のことがある（`docs/plugins`「Submit your plugin to the community marketplace」／`docs/discover-plugins`「Official Anthropic marketplace」）。

公式 docs（`docs/skills`）が挙げる具体機能:

| 機能 | 内容 | 生成物 |
|---|---|---|
| Test cases | プロンプト・入力ファイル・期待挙動を蓄積 | skill ディレクトリ内 `evals/evals.json` |
| Isolated runs | テストケースごとに subagent を spawn（クリーンな context で実行）、token 数・所要時間を記録 | — |
| Grading | 各アサーションを出力と照合し pass/fail を根拠付きで記録 | `grading.json` |
| Benchmark | skill 有り／無しの pass 率・時間・token を集計（改善幅とオーバーヘッドを比較） | `benchmark.json` |
| Version comparison | 2 バージョンを blind A/B し、編集が改善かをコミット前に確認 | — |
| Description tuning | should-trigger / should-not-trigger プロンプトを生成し発火率を測定、description 修正案を提示 | — |
| Review viewer | 各出力を確認し定性フィードバックを記録する HTML レポート | — |

**公開リソース（いずれも英語。日本語版は確認できず）**:
- プラグイン本体（公式リポ）: `https://github.com/anthropics/claude-plugins-official/tree/main/plugins/skill-creator`
- README: `https://github.com/anthropics/claude-plugins-official/blob/main/plugins/skill-creator/README.md`
- eval ファイル形式・反復ワークフロー: `https://agentskills.io/skill-creation/evaluating-skills`
- ベンチ／比較モードの背景（公式ブログ）: `https://claude.com/blog/improving-skill-creator-test-measure-and-refine-agent-skills`

> skill 単体は hooks / MCP を同梱できない。これらが必要なら plugin 化する（§4 の②で、場所を動かさずに plugin 化できる）。

---

<a id="plugin-dev"></a>

## 7. （推奨・任意）純正ツールキット `plugin-dev` で開発を加速

純正の **`plugin-dev`（"Plugin Development Toolkit"・author=Anthropic・README 記載 v0.1.0）** は、本手順書 §1〜§3 のフローを **AI 支援＋ベストプラクティス指南つき**で進める公式ツールキット。**本手順書のフローを置換するものではなく、その上に乗る accelerator**——`plugin-dev` 自身が最終フェーズで「テストは `cc --plugin-dir` / `claude --debug` / `/mcp` で」と案内しており、§3〜§6 の中核手段を**公式が裏打ち**している。

```bash
# 利用（marketplace から）
# 初回対話起動前の CI・非対話環境では未登録のことがあるため、必要なら先に:
# claude plugin marketplace add anthropics/claude-plugins-official
/plugin install plugin-dev@claude-plugins-official
# ※ README 上の表記は plugin-dev@claude-code-marketplace。marketplace エイリアスに表記差があるため
#   install 時に実際の marketplace 名を確認する（公式 docs カタログ文脈では claude-plugins-official）
/reload-plugins

# 開発時に直接ロード（plugin-dev 自体を試す/改変する場合）
cc --plugin-dir /path/to/plugin-dev
```

> **シナリオ B との相性がよい**。ゼロから作るときの設計 questioning と検証の自動化が効くため、§2-2 の代替として使える。シナリオ A（既存資産の切り出し）では、§1-2 の棚卸しは自分で行い、`plugin-validator` / `skill-reviewer` を検証段で使う形が噛み合う。

### 7.1 ガイド付き作成コマンド `/plugin-dev:create-plugin [説明]`

ゼロから plugin を作る **8 フェーズ**のワークフロー。各フェーズで確認質問を行い、必要な skill を自動ロードし、専用 agent と検証スクリプトを使う。**主要な意思決定点でユーザーの確認を待って進む**対話型。

| # | フェーズ | 何をするか | 自動ロード skill / agent |
|---|---|---|---|
| 1 | Discovery | plugin の目的・対象ユーザー・解く課題を確定（曖昧なら質問） | — |
| 2 | Component Planning | 必要コンポーネント（skills/agents/hooks/MCP/settings）を決め、表で提示し承認を得る | `plugin-structure` |
| 3 | Detailed Design & 質問 | 各コンポーネントを詳細設計し曖昧点を解消（**CRITICAL・省略禁止**） | — |
| 4 | Structure Creation | 名前（kebab-case）・配置場所を決め、ディレクトリ・`plugin.json`・README・`.gitignore`・git init を作成 | — |
| 5 | Component Implementation | 各コンポーネントをベストプラクティスで実装 | `skill-development` / `agent-development` / `hook-development` / `mcp-integration` / `plugin-settings`（必要分）＋ `agent-creator` |
| 6 | Validation & Quality | `plugin-validator` agent で manifest/構造/命名/コンポーネント/セキュリティを検査、`skill-reviewer` で skill 検査、検証スクリプト実行 | `plugin-validator` / `skill-reviewer` |
| 7 | Testing & Verification | `cc --plugin-dir <path>` で導入し、skill 発火・`/plugin-name:skill` 実行・agent 発火・hook（`claude --debug`）・MCP（`/mcp`）を確認 | — |
| 8 | Documentation & Next Steps | README 完成度確認、（公開時）`marketplace.json` エントリ追加、サマリ作成 | — |

> このコマンドの `allowed-tools` は Read / Write / Grep / Glob / Bash / TodoWrite / AskUserQuestion / Skill / Task。

### 7.2 提供される skill（7本・質問に応じて自動ロード）

| skill | 役割 |
|---|---|
| `plugin-structure` | plugin ディレクトリ構造・`plugin.json` manifest・auto-discovery |
| `skill-development` | skill 作成（progressive disclosure・強いトリガー記述）。`skill-creator` 方法論を plugin 向けに適応 |
| `agent-development` | subagent 作成（YAML frontmatter＋system prompt・AI 支援生成） |
| `hook-development` | 全 hook イベント・prompt/command hook・`${CLAUDE_PLUGIN_ROOT}` |
| `mcp-integration` | MCP サーバ統合（stdio/SSE/HTTP/WebSocket・認証） |
| `plugin-settings` | `.claude/<plugin-name>.local.md` でのプロジェクト別設定保存 |
| `command-development` | スラッシュコマンド作成（**レガシー `commands/` 形式専用**。新規は `skill-development` を使う） |

### 7.3 検証 agent（3本）と検証スクリプト（6本）

- **agent（3本）**: `agent-creator`（AI 支援で agent を生成＝identifier・whenToUse 例・systemPrompt）／`plugin-validator`（plugin 全体の検査）／`skill-reviewer`（skill の記述品質・progressive disclosure 検査）。
- **検証スクリプト（6本）**: `validate-hook-schema.sh` / `test-hook.sh` / `hook-linter.sh` / `validate-settings.sh` / `parse-frontmatter.sh` / `validate-agent.sh`。

### 7.4 使いどころ・棲み分け

- **使いどころ**: 「型に沿って・抜け漏れなく・対話で確認しながら」plugin を新規作成したい時。手で §1〜§3 を回すより、設計の questioning と検証の自動化が効く。
- **棲み分け**: `skill-creator` = **skill 単体**の eval・測定（test/measure/refine）／`plugin-dev` = **plugin 全体**の作成支援。詳細は[調査結果報告書 §6](./Plugin・Marketplace配布物の開発・テスト_調査結果.md)。

---

<a id="impl-rules"></a>

## 8. plugin 配布前提のスクリプト・同梱ファイル実装規約（重要）

> **なぜ重要か**: skills/ のように「フォルダごと配布可」とされる資産でも、**plugin 化して Marketplace 配布すると実行場所が `<repo>\.claude` ではなく cache（`~/.claude/plugins/cache/<mp>/<plugin>/<version>/`）になる**。`*.md` のようにパスがファイル固定の資産と違い、フォルダ配布資産は**構成要素ごとに「配布されても cache 先で使えない／書けない／ユーザに見えない」制約**を持つ。standalone（層1 直置き）では cwd＝`<repo>` 前提の相対パスが偶然動くが、plugin 化で必ず壊れる。配布前提のスクリプト・同梱ファイルは最初からこの規約で作る。（出典: 公式 plugins-reference / skills。根拠詳細は調査結果報告書へ別途追補）
>
> **シナリオ A では §1-4 のレトロフィット対象、シナリオ B では §2-2 の最初から適用する規約**にあたる。

### 8.1 パス解決（読み取り）— cwd 非依存で書く

- **skill 同梱ファイル（references/・templates/・scripts/）の参照は `${CLAUDE_SKILL_DIR}` を使う**。SKILL.md のあるディレクトリ（plugin の場合は plugin root でなく skill サブディレクトリ）に解決され、**personal / project / plugin のどこに置かれても正しく解決される**公式推奨変数。SKILL.md 本文に `python3 ${CLAUDE_SKILL_DIR}/scripts/foo.py` と書けば**実行前に絶対パスへインライン置換**される。
- **`${CLAUDE_SKILL_DIR}` は SKILL.md 本文だけでなく、frontmatter の `allowed-tools` の Bash ルールでも同様に置換される**（例: `allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/render.sh *)`。**v2.1.235 版(2026-08-19)**・`docs/skills`「Available string substitutions」）。本文と `allowed-tools` の双方で同じ変数を使うと、SKILL.md が指示するコマンドと `allowed-tools` のルールが完全一致するため、同梱スクリプトを permission プロンプト無しで実行できる。
- **plugin root 相対（複数 skill 横断・hook・MCP/LSP）の参照は `${CLAUDE_PLUGIN_ROOT}`**。`${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_SKILL_DIR}` / `${CLAUDE_PLUGIN_DATA}` は **skill 本文・agent 本文・hook command・monitor command・MCP/LSP config のいずれでもインライン置換**される。
- **スクリプト内部から env 変数で読めるか**は起動経路で異なる（**ここでの env は「起動された子プロセスの OS 環境変数」であり、settings.json の `env` 要素ではない**。これらの変数は Claude Code が実行時に注入する）:
  - **hook / MCP / LSP から起動**されたプロセス → `CLAUDE_PLUGIN_ROOT` 等が環境変数として export され `os.environ` / `process.env` で読める。
  - **skill の手順で Claude が Bash ツール実行**するスクリプト → env 注入は保証されない。**SKILL.md 側で `${CLAUDE_SKILL_DIR}` を置換させ引数で絶対パスを渡す**か、スクリプトが**自身位置から相対解決**（Python `Path(__file__).resolve().parent`／bash `cd "$(dirname "${BASH_SOURCE[0]}")" && pwd`）する。
- **禁止**: cwd 依存の相対パス（`./scripts/...`）／ハードコード絶対パス／plugin root 外への `../` 参照（cache にコピーされず壊れる）。

### 8.2 書き込み・蓄積先 — cache に書かない

- **`${CLAUDE_PLUGIN_ROOT}` 配下（cache）へ state を書いてはならない**。更新のたびにパスが変わり、旧バージョン dir は**約14日後に削除**（orphaned 化し Glob/Grep 対象からも除外）。公式も "treat it as ephemeral … do not write state here" と明記。**v2.1.235 版(2026-08-19)**: 削除猶予は旧版の約7日から**約14日へ倍増**し、さらに**最後の1個の plugin をアンインストールすると掃除処理自体が止まり、次に何か plugin を入れるまで orphaned dir が残り続ける**という条件が付いた。
- **永続させる書き込み（ナレッジ蓄積・生成物・キャッシュ、Python 依存等の手動インストールが必要な依存）は `${CLAUDE_PLUGIN_DATA}`**（`~/.claude/plugins/data/{id}/`・**更新をまたいで残る**・初回参照時に自動作成・最終スコープからの uninstall 時に削除〔`--keep-data` で保持〕）かプロジェクト側に置く。**例外（v2.1.235 版(2026-08-19)）**: npm/Bun の依存関係（`package.json`＋対応ロックファイル: `bun.lock`/`bun.lockb`/`npm-shrinkwrap.json`/`package-lock.json`）は、marketplace 経由の plugin なら Claude Code が cache 配置時に自動インストール（`--ignore-scripts`。lifecycle script は実行されない）するため、`${CLAUDE_PLUGIN_DATA}` への手動配置が不要な場合がある。Python 依存・yarn/pnpm ロックファイル・lifecycle script 必須の依存は引き続き手動（hook から `${CLAUDE_PLUGIN_DATA}` へ）。
- 「references/ のファイルに追記してナレッジ蓄積」は cache 配下では不可。**同梱 references/ は読み取り専用の初期データ**として扱い、可変分は `${CLAUDE_PLUGIN_DATA}`／プロジェクトへ分離する。

> **② `@skills-dir` は cache へコピーされず in place で読まれる**（実測）。そのため層1 のままなら cwd 依存でも偶然動いてしまうが、**同じ資産を ③ で配った瞬間に壊れる**。**②を選んだ場合も本節の規約は守る**こと（後から ③ へ広げられなくなる）。

### 8.3 README・references のユーザアクセス — cache 内ファイルに依存しない

- plugin 同梱の `README.md`・references/ は cache にコピーされるが、**`/plugin`・`claude plugin` 系から内容を閲覧する公式 UI は無い**（`claude plugin details`／Discover タブはコンポーネント一覧とトークンコスト表示で、本文表示ではない）。普段開かない cache パスを辿らせる運用は非現実的。
- **対応案**:
  1. **ユーザが読む README は配布元リポジトリに置き、`plugin.json` / `marketplace.json` の `homepage` / `repository` で URL を提示**する（公式想定経路・GitHub 上で閲覧）。← 推奨
  2. **skill が処理中に参照する references/ は、ユーザの手動アクセス前提にしない**。SKILL.md から参照され Claude がオンデマンドにロードする。
  3. **ユーザが読む／編集するファイル**は plugin 同梱（読み取り専用 cache）に不向き。プロジェクト側（層1）か `${CLAUDE_PLUGIN_DATA}` に置く設計へ寄せる。

### 8.4 フォルダ配布資産（skills/<name>/）の構成要素別チェック

| 構成要素 | cache へコピー | plugin 配布時の制約・実装規約 |
|---|:---:|---|
| `SKILL.md` | ○（ロード） | 本文のパスは `${CLAUDE_SKILL_DIR}` で書く（§8-1） |
| `references/`（読み取り） | ○ | 参照は `${CLAUDE_SKILL_DIR}` 経由。**追記先に使わない**（§8-2） |
| `templates/` | ○ | 読み取りは同上。生成物の出力先は cache でなくプロジェクト／PLUGIN_DATA |
| `scripts/*.py` 等 | ○ | cwd 非依存で実装（§8-1）、書き込みは §8-2 |
| `README.md` | ○ | **UI 閲覧不可**。ユーザ向けは `homepage`/repo で提示（§8-3） |
| plugin root `CLAUDE.md` | ○ | **コンテキストに自動ロードされない**。指示を載せるなら skill 化 |

> **要点**: 「skills/ は層2 配布可（v1.2 マトリクス §核心 ①）」は**フォルダが配布される**ことを意味するが、**中身が cache 先でそのまま機能する保証ではない**。配布前提の skill は本 §8 の規約で実装する。

---

## 9. 公開前チェックリスト

### 共通

- [ ] plugin ディレクトリ外への参照（`../...`）が無い（キャッシュコピーで壊れる）
- [ ] `plugin.json` の `author` がオブジェクト型／marketplace 配布なら `marketplace.json` に `owner`（オブジェクト・必須）がある
- [ ] `claude plugin validate ./my-plugin` がパスする（CI では `--strict` も）
- [ ] marketplace 配布なら `claude plugin validate ./my-mp` もパスする（schema・重複名・source・バージョン整合）
- [ ] `--plugin-dir` で起動し、skill / command / agent / hook が期待どおり動く
- [ ] **【必須】導線検証**: `marketplace add` → `install` → `list` → `details` まで通した（§3-6）。**validate だけで判断していない**
- [ ] `source` の種別（相対パス / git / `git-subdir` / 直接 URL / `archive` / `command`）と参照先の整合を確認した
- [ ] `--debug` でロードエラーが出ていない
- [ ] スクリプト/SKILL.md のパス参照が `${CLAUDE_SKILL_DIR}` / `${CLAUDE_PLUGIN_ROOT}` 解決（cwd 依存・絶対パス・`../` 不使用）（§8-1）
- [ ] 書き込み・蓄積先が `${CLAUDE_PLUGIN_DATA}` かプロジェクト側（cache=`${CLAUDE_PLUGIN_ROOT}` 配下に書いていない）（§8-2）
- [ ] ユーザが読む README は `homepage`/repo で参照可能（cache 内 README に依存しない）（§8-3）
- [ ] plugin root の `CLAUDE.md` に依存していない（自動ロードされない）（§8-4）
- [ ] **利用者向けの呼び名を README に明記**した（層1 なら `/<name>`、plugin なら `/<plugin>:<skill>`）

### シナリオ A（派生型）で追加

- [ ] §1-2 の棚卸しを全項目やった（cwd 依存・リポ固有前提・外部参照・秘匿情報・他資産への依存）
- [ ] レトロフィット後に**元の場所でも回帰が無い**ことを確認した
- [ ] **層1 の原本を残すか消すかを決めた**（残す場合、利用者が層1 と層2 の両方を入れないよう README で誘導した）（§4-3）

### シナリオ B（公開先行型）で追加

- [ ] §2-1 の判断フローで開発リポジトリを決めた（**配布雛型リポジトリを開発ワークスペースにしていない**）
- [ ] **実運用の裏付け**を取った（dogfooding / eval / description tuning のいずれか）（§2-3）
- [ ] `plugin.json` を置いた（無いと version を持たず版管理レールに乗らない）（§4-4）

---

## 変更履歴

- **v2.0（2026-08-20）**: **開発シナリオを 2 パターンに分けて全面改稿**。旧版は「既存リポジトリの活動の中で必要になって作り、整えて公開する」入口だけを前提にしており、「公開前提で思いついたものを、その開発自体を作業として一気に公開まで持っていく」入口が抜けていた。主な変更:
  - **構成の刷新**: §0 全体像（2 シナリオの対比・共通コアの図・リポジトリ・公開形態の早見）／**§1 シナリオ A（派生型）**／**§2 シナリオ B（公開先行型）**／**§3 共通コア**（旧 §1 の②〜⑤）という「入口を分けて途中で合流する」構成へ。旧 §2→§5、旧 §3→§6、旧 §4→§7、旧 §6→**§8**、旧 §5→§9 に繰り下げ（**他文書からの「手順書 §6」参照は §8 を指すよう更新済み**）。
  - **§1-2「配れるかの棚卸し」を新設**（シナリオ A 固有）。切り出しで壊れる原因（cwd 依存の相対パス・リポ固有の前提・plugin 外参照・秘匿情報・他資産への依存）を公開形態を決める前に洗い出す工程として明文化した。
  - **§2-1「開発リポジトリを決める判断フロー」を新設**（シナリオ B 固有）。Q1 チーム共通資産か → Q2 単発・独立か → Q3 独自のリリースサイクルを持つか、の 3 問で「配布開発源の `.claude/` 配下」「配布 payload の外の開発エリア」「専用リポジトリ新設」を選ぶ。**`git-subdir` により後から引っ越せる**ため、この判断を重くしないことを明記した。あわせて**配布雛型リポジトリ（利用者が clone する側）を開発ワークスペースにしない**という禁止を置いた。
  - **§2-3「実運用の裏付けを取る」を新設**（シナリオ B 固有）。シナリオ A が持つ「既存リポでの実使用実績」が B には無いため、dogfooding / eval / description tuning のいずれかを通す工程として明文化した。
  - **§3-6「導線検証【必須】」を新設**。`claude plugin validate` は**相対 `source` の解決失敗を検出しない**ため、`marketplace add` → `install` → `list` → `details` まで通して初めて「配れる」と判断する。§3-5・§5・§9 にも「validate がチェックしないもの」を明記した。
  - **§4「公開形態の選択」を新設**（①層1 直配り／②`@skills-dir`／③Marketplace plugin の比較・選び方・`git-subdir`・注意点）。**CLI v2.1.237 の実機計測**（[調査結果 §9](./Plugin・Marketplace配布物の開発・テスト_調査結果.md#single-entity)）に基づき、**②の追加は既存利用者に非破壊**（呼び名 `/<name>` は project でも `--add-dir` でも変わらない）、**`git-subdir` で実体 1 つ・参照 2 通りに畳める**、**層1 と層2 を同時に入れさせてはならない**（素の project skill と plugin skill が二重に context へ載る）ことを確定事項として記述した。
  - **§3-7 に `claude plugin tag`（版タグ）とリリースチャネルを追加**。§5 の早見表に `plugin list --json` / `plugin details` / `plugin marketplace update` / `plugin tag` / `plugin eval` を追加。
  - **§3-2・§3-3 に非対話の検証手法を追加** ―― `claude -p … --debug` の起動ログ（`Loaded N unique skills (… project/additional …)` / `Found N plugins`）と、`CLAUDE_CONFIG_DIR` による隔離。
  - **§3-3 に marketplace の構造誤りの警告を追加**（`.claude-plugin/` はルート直下。`marketplace/.claude-plugin/` と `plugins/` を兄弟に置くと相対 `source` が解決できず、しかも `validate --strict` を通過する）。
  - 前提環境の CLI 版を **v2.1.237** に更新。

- **v1.3（2026-08-20）**: 公式ドキュメント最新版（CLI v2.1.235 相当・2026-08-19 取込）との横断整合性照合（検出タスク G2・[調査結果報告書](./Plugin・Marketplace配布物の開発・テスト_調査結果.md)とあわせ計17件検出）を反映。本書側の適用は10件（G2-002, G2-004, G2-005, G2-007, G2-009, G2-010, G2-012, G2-013, G2-015, G2-016）。**あわせて H1 の版番号が v1.1〜v1.2 の間 "v1.0" のまま更新されていなかった不備を本版で訂正**（変更履歴は進んでいたが見出しが追随していなかった）。主な変更:
  - **【CRITICAL 訂正】§1④・§2 の `--debug` コマンド例**: `claude --debug mcp` / `claude --debug hooks`（スペース区切り）というカテゴリ絞り込みの書き方は現行仕様では機能しない。カテゴリを絞るには **`=` 結合＋カンマ区切り**（例: `claude --debug='mcp,startup'`）が必須で、スペース区切りはフィルタなしでデバッグモードを有効化するだけと訂正。hook 評価の詳細確認は `CLAUDE_CODE_DEBUG_LOG_LEVEL=verbose` を案内する形に改めた。あわせて現行 `docs/cli-reference` で確認できない `--mcp-debug` 非推奨への言及を削除（旧記述のまま実行すると意図した絞り込みができない CRITICAL 案件）。
  - **§1③「動作確認」から `/agents` を削除**: v2.1.198 以降 `/agents` は案内メッセージを表示するだけの機能に変わり、plugin agent の動作確認に使えない。代替として `/context` の Custom Agents 欄・@-mention・hook は実発火確認を案内。
  - **§6.2 plugin cache の旧バージョン dir 削除猶予を約7日→約14日に訂正**。最後の plugin をアンインストールすると掃除処理自体が止まる新条件も追記。
  - **§6.2 node_modules 等の依存記述を訂正**: marketplace 経由 install の plugin は npm/Bun の依存を cache 配置時に自動インストールするようになったため、手動配置が必要なのは yarn/pnpm・lifecycle script 必須の依存・Python 依存に限定されると明記。
  - **§2 `--add-dir` 早見表に commands（`.claude/commands/`）の自動ロードを追加**（live reload なし・同名時はプロジェクト側優先）し、正本 [v1.2 付録B『--add-dir 例外ロード一覧（正本）』](../../01.配布・統制方針調査/結論・構成案_ポータブルな.claude共有_v1.2.md#adddir-exceptions) への参照リンクを新設（本書はこれまで正本を参照していなかった）。
  - **§3・§4 の `claude-plugins-official` install 例に自動登録の注意を補記**: マシン初回の対話起動時に自動登録される仕様のため、CI・非対話環境で先に動かすと未登録になりうる。
  - **前提環境・§1③ の `.zip` 対応の版限定注記を軟化**: v2.1.128+ という版注記が現行 docs には見当たらず、現行版では標準機能として記載されていることを明記（誤りと断定はせず、版注記が確認できなくなった旨の注記に留めた）。
  - **§1② plugin ディレクトリ例に補足を追加**: skill が1つだけの plugin は `SKILL.md` を plugin root 直下に置ける軽量パターン、および `workflows/` が正式コンポーネントとして追加された点を追記。
  - **§1③「副: ローカル marketplace」・§5 公開前チェックリストの `source` 相対参照の説明を訂正**（本書に該当する G2 finding はなかったが、[調査結果報告書 G2-014 の訂正](./Plugin・Marketplace配布物の開発・テスト_調査結果.md)と同一の「git 経由配布でのみ」「git / URL」という誤った二値的な説明が本書側にも残っていたため、姉妹文書との整合のため同時に修正）: git 経由の追加とローカルディレクトリとしての追加の両方で機能する旨に訂正し、`archive`/`command` の新 source 種別への言及を追加。
  - **§6.1 に `${CLAUDE_SKILL_DIR}` が frontmatter `allowed-tools` の Bash ルールでも置換される点を追記**（同梱スクリプトを permission プロンプト無しで実行できる）。
  - **§1③・§2 に `/reload-plugins` の既知の表示上の癖を追記**: サマリの「skills」件数は plugin の `commands/` ディレクトリのみをカウントしており、`skills/` だけの plugin では実際に反映されていても `0 skills` と表示されうる。
  - 本書は「根拠・出典は報告書側」の位置づけのため出典表は新設せず、各記述にページ名＋版タグ（**v2.1.235 版(2026-08-19)**）をインライン記載する従来方式を踏襲。
- **v1.2（2026-06-29）**: 横断整合性レビュー反映。§2 の `--add-dir` 自動ロード注記の subagents（`.claude/agents/`）に版境界「v2.1.178+。v2.1.165 までは非ロード」を補い、v1.2 報告書 errata [75]・他編と統一。
- **v1.1（2026-06-25）**: §6「plugin 配布前提のスクリプト・同梱ファイル実装規約」を新設（実 skill の plugin 化テストで判明したパス解決・書き込み先・README アクセスの制約を反映）。パス解決は `${CLAUDE_SKILL_DIR}`／`${CLAUDE_PLUGIN_ROOT}` のインライン置換と起動経路別の env 注入、書き込みは cache 禁止・`${CLAUDE_PLUGIN_DATA}` 利用、README は UI 非閲覧で `homepage` 提示を明記。§②のディレクトリ例を references/templates/scripts/README 付きの実構成へ拡張し §6 への必読ポインタを追加、§5 チェックリストに 4 項目追加。（出典の行番号付き根拠は調査結果報告書へ別途追補予定）
- **v1.0（2026-06-21）**: 初版。[調査結果報告書 v1.0](./Plugin・Marketplace配布物の開発・テスト_調査結果.md) を実務手順に落とし込み。レビュー反映として全体フロー図のローカルリポ明示（A/B/C）、standalone の語義・①の動作検証・②の実施リポ・④ validate の必須/推奨条件・`--debug` の実行時範囲・scaffold の語義・`skill-creator` の機能/URL を補強。`commands/` レガシー指針（§1②）を追記し、純正 `plugin-dev` の節（§4）を `create-plugin` 8 フェーズ表・7 skill・3 agent・6 検証スクリプトまで踏まえて拡充。**Sonnet 動作検証（実機 `claude plugin validate` v2.1.185）反映**: `plugin.json` の `author`＝オブジェクト・`marketplace.json` の `owner`＝必須の最小例追加、`--add-dir` 注記を skills＋subagents に訂正、`--debug` 出力先 `~/.claude/debug/<session-id>.txt` 明記、`validate --strict` 追加。
