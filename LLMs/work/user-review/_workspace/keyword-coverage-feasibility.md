# narrative キーワード網羅性の技術的可能性調査（B-10pre）

調査実施日: 2026-05-28
調査スコープ: 段階 1（文献レビュー）+ 段階 2（保証レベル整理）
（段階 3 実証 / 段階 4 設計指針への変換 は本調査範囲外）

---

## エグゼクティブサマリ

- **「指定キーワード集合が必ず含まれる narrative」の 100% hard guarantee は、Anthropic API 単独では現時点で不可能**である。Structured Outputs / Strict tool use は grammar-constrained sampling を提供するが、対象は **JSON Schema 構造に限定**され、自由文 (free-form text) のレベルで「特定の単語列が必ず出現する」ことを物理的に保証する手段は API として公開されていない（2026 年 5 月時点）。
- 自由文に対するキーワード必出を物理的に保証するには、**Outlines / lm-format-enforcer / guidance / llguidance** などの token-level constrained decoding ライブラリと、それらを許容する **オープンウェイトモデル**（ローカル推論または対応プロバイダ）の組み合わせが必要。Anthropic は logits / token サンプリング層を公開していないため、これらの手法は適用できない。
- 一方、**B（生成 → 検証 → 不足なら再生成）レベルは Anthropic API + 軽量バリデータの構成で確実に実装可能**で、コストもキーワード平均充足率次第で 1.1〜1.5x 程度に収まる見込み（学術文献の典型値からの推定）。
- prompt engineering 単独（リトライなし）の保証は学術ベンチマーク（IFEval / 関連研究）の数値から **およそ 85〜95%（キーワード単独 5〜10 個程度・自由文短文）**。「99% を境にコストが急増する」非連続性に注意。
- cc-relative-info の現実的な採用候補は **B（retry + validation）または F（hybrid: 自由生成 + 不足キーワードの後段補完配置）**。コスト・自動運用・品質ともに 47 ターゲット規模で耐えうるレベル。

---

## 段階 1: 文献・公式情報レビュー

### 1.1 Constrained generation の state-of-the-art

#### 主要なアプローチ系列

| 系列 | 代表的技術 | 仕組み | 保証強度 |
|---|---|---|---|
| **Grammar-constrained decoding (GCD)** | XGrammar, llguidance, Outlines, lm-format-enforcer | スキーマ・正規表現・CFG を grammar に compile し、各トークン生成時に **token mask** を適用して invalid token を logits 上で塞ぐ | 構造的制約は **100% hard** |
| **Logit biasing (forced inclusion)** | OpenAI `logit_bias`, prefix-tuned decoding | 特定トークンの確率を強制的に持ち上げる / 下げる | キーワード単位では中程度。文法構造保証はなし |
| **NeuroLogic A\*esque** | NeuroLogic 系（Lu et al. 2021, NAACL 2022） | predicate logic 形式のキーワード制約 + A\* 風 lookahead heuristic で beam search を誘導 | hard constraint（学術領域では high success rate）。実装は LM 内部にフックが必要 |
| **Iterative refinement** | LLM-driven constrained copy generation（Bagal et al. 2025） | LLM 自身に「不足キーワードを補って書き直す」工程を繰り返させる | best-effort、収束は経験的 |
| **Future-constrained / lookahead** | Anticipatory text generation（Liu et al. 2023） | 残りステップで制約を満たせるかを推定して decoding を導く | hard ではないが高い達成率を報告 |

> 出典: arXiv 2312.06149, 2504.10391, 2403.06988, 2310.16343, 2112.08726, 2411.15100

#### キーワード制約に対する研究知見

- **GPT-4 ですらキーワード指示遵守は 85% 程度**（Sun et al., 2023, "Evaluating, Understanding, and Improving Constrained Text Generation"）。length 73%、punctuation 68%。
- **IFEval ベンチマーク**（Google / Hugging Face Open LLM Leaderboard 採用）: 25 種の verifiable instruction を 541 prompt で評価。キーワード必出・出現回数・禁止語・word count 等が含まれる。最新の Claude Sonnet 4 系は instruction-following で best-in-class（accuracy 0.86 程度の報告）だが、**100% は誰も達成していない**。
- **粗粒度制約**（topic / sentiment / "keyword 群を含む"）は LLM がよく従う一方、**細粒度制約**（数値、回数 N、長さ N 文字）は失敗率が上がるという系統的傾向。

### 1.2 Anthropic API の能力範囲

#### Structured Outputs（GA、2026 年）

- **対応モデル**: Claude Opus 4.5/4.6/4.7、Sonnet 4.5/4.6、Haiku 4.5 ほか（Mythos Preview 含む）
- **仕組み**: JSON Schema を **CFG に compile** し、トークン生成時に grammar-constrained sampling を適用。初回 100〜300ms のコンパイル overhead、24h schema cache
- **ベータヘッダー**: `anthropic-beta: structured-outputs-2025-11-13`（旧式）/ `output_config.format`（GA 後の新形式）
- **JSON Schema サポート**: 基本型、`enum`, `const`, `anyOf`, `allOf`, `$ref`, format（date, email, uri 等）。**`pattern`（正規表現）は限定サポート**: `^...$`, `*+?`, 文字クラス, グループは可。**backreference / lookahead / `\b` / 大きな `{n,m}` 等は非対応**
- **JSON Schema 非対応**: 数値範囲 (`minimum/maximum`), 文字列長 (`minLength/maxLength`), 複雑な配列制約, `additionalProperties: false` 以外

#### Strict tool use

- `strict: true` を tool 定義に付けると、tool input が JSON Schema に **grammar-constrained sampling で適合保証**される（Structured Outputs と同じパイプライン）
- 保証対象は **tool の `input` フィールド構造のみ**。**自由文 (assistant text) には適用されない**

#### Anthropic API 固有の重大な制約（自由文制御に関して）

1. **logit_bias 相当の API が存在しない**（OpenAI とは異なる）。特定トークンを「必ず使う / 使わない」と直接指示する手段がない
2. **token mask / grammar を assistant 自由文に適用する API がない**。Structured Outputs は JSON 出力専用
3. **prefill（assistant 先頭固定）が Sonnet 4.6 / Opus 4.6 / Opus 4.7 等の最新モデルでサポート廃止**（2026 年 4 月以降）。以前は擬似的にスタート部分を制御できたが、最新モデルでは使えない
4. **stop_sequences** はあるが、これは出現抑止用であり、必出を保証する手段にはならない
5. tool input の `pattern` で正規表現を書ければ自由文に近い制約は可能だが、(a) backreference 不可、(b) 「複数の任意キーワードのうち全てを含む」を単一正規表現で書くのは非現実的（指数的に長い regex になる）

#### 「JSON 出力の中に narrative 文字列フィールドを置く」アプローチの限界

- narrative を `{"narrative": "..."}` 型 JSON で生成させ、`pattern` で「キーワード必出」を書こうとしても、上記の正規表現制約により **「N 個のキーワード全てが順不同で出現する」を pattern で表現することは事実上不可能**（5 個で約 5! = 120 通り、10 個で 10! = 3,628,800 通りの順列を OR で書く必要がある）
- → JSON ラッピングしてもキーワード必出は構造的に保証できない

### 1.3 他社 API（OpenAI 等）との比較

| 機能 | Anthropic | OpenAI | オープンウェイト + Outlines/llguidance |
|---|---|---|---|
| JSON Schema 構造保証 | あり (Structured Outputs / Strict tool use) | あり (Structured Outputs) | あり |
| 自由文への regex 制約 | 不可 | 不可（直接）。`response_format` は JSON のみ | **可（pattern / regex 直接指定）** |
| **特定トークン必出（自由文）** | **不可** | 限定的（`logit_bias` で確率操作。必出保証ではない） | **可（grammar に "must contain X" を仕込める）** |
| logit_bias | なし | あり | あり |
| Grammar (CFG / GBNF) 指定 | JSON のみ間接的 | JSON のみ | **可** |
| prefill / assistant 先頭固定 | 旧モデルのみ、最新は不可 | あり (response prefill) | 可 |

> 結論: **自由文に対する hard guarantee の道具は、Anthropic API では現状提供されていない**。OpenAI も自由文 hard guarantee は提供せず、`logit_bias` も「確率を ±100 操作する」までで必出保証ではない。**100% hard guarantee は事実上オープンウェイト + 専用ライブラリの世界**。

### 1.4 既存補助ライブラリ

| ライブラリ | コア機能 | キーワード必出に対する適用 | Anthropic API での利用 |
|---|---|---|---|
| **Outlines** (dottxt-ai/outlines) | 正規表現 / CFG / JSON Schema を automaton に変換、token mask 適用 | 可（regex で `(?=.*keyword1)(?=.*keyword2)` 型の lookahead は内部実装次第） | 不可（logits 直接アクセスが必要） |
| **lm-format-enforcer** (noamgat) | JSON / regex に decode-time 適合保証 | 可（同上） | 不可 |
| **guidance** / **llguidance** | DSL で生成プロセスを記述、token forcing 含む | 可（"select" / "gen with stop / pattern" 等） | 不可（モデル内部フック必須） |
| **instructor** (jxnl/instructor) | Try-Reject-Repeat（Pydantic 検証＋ retry） | **可。これは API 側の logits アクセス不要で Anthropic でも使える** | **可（Anthropic SDK サポート有り）** |
| **Pydantic + 自前 validator** | スキーマ検証 + 失敗時 retry | 可（最も汎用） | 可 |

> instructor / Pydantic ベースの retry は Anthropic API でも問題なく使える。本調査の文脈では **B レベル（retry）の実装基盤として instructor が最有力**。

### 1.5 学術・業界事例

- **IFEval** (Zhou et al., 2023): 25 種 verifiable instructions。キーワード関連サブセット（"include keyword X N times", "include any of these keywords"）に対し、当時の GPT-4 ですら 85% 前後
- **InFoBench** (Qin et al., 2024): instruction following を細粒度に分解。Decomposed Requirements Following Ratio (DRFR) を提案。キーワードレベルは比較的高スコア、複合制約は劇的に低下
- **AGENTIF** (Tsinghua, 2024–2025): agent 文脈での instruction following。turn 数が増えるほど PIF（Per-Instruction-Following ratio）低下（turn 1 で 0.81 → turn 20 で 0.64 という代表値）
- **「The Instruction Gap」** (arXiv 2601.03269): instruction が多くなるほど LLM は脱落しやすい。1 命令あたりの follow rate は 95% 超でも 10 命令で複合命中率は 60% 程度に落ちる例示
- **業界事例**: SEO/コンテンツ生成系で Anthropic XML タグ＋キーワード列挙のテンプレが広く使われている（aipromptlibrary.app 等）。保証はソフトで、validation + retry を併用する運用が標準

> 出典: arXiv 2401.03601 (InFoBench), 2601.03269, 2409.18216, IFEval (Hugging Face Open LLM Leaderboard), AgentIF (Tsinghua KEG)

### 1.6 prompt engineering 単独の限界

- **キーワード数とサイズの依存性**: 1〜3 個のキーワード必出 + 短文 (1〜2 文) では Sonnet/Opus 4.x で経験的に 95% 以上。**5〜10 個に増えるとリトライなしで 80〜90% 程度に低下**（IFEval / InFoBench / 関連研究の傾向からの推定）
- **典型的な失敗パターン**:
  1. キーワード A は使ったが B を忘れる（特に B が珍しい固有名詞のとき）
  2. キーワードを使ったが意味的に微妙にずれる訳語に置換（例: "Kubernetes" → "k8s クラスタ"）
  3. 「カノニカル」のような表記揺れを起こしやすいカタカナ語
  4. 1〜2 文の制約と多数キーワードが両立しないため、モデルが要約圧縮で一部を落とす
- **temperature=0 の効果**: 出力の決定性は上がるが、**プロンプト改善なき限り命中率は上がらない**（同じ失敗が決定的に再現するだけ）。retry 時には必ず温度を上げるか、フィードバックを与える必要がある
- **XML タグ + 強い指示の効果**: Anthropic は XML タグ認識に最適化されており、`<required_keywords>` を明示する手法は経験的に有効。それでもなお 100% 保証はできない（保証するなら検証が必須）

---

## 段階 2: 保証レベルの整理

### 2.1 保証レベル定義表

| Lv | 名称 | 技術手段 | Anthropic API での実現 | コスト | 既存事例 | 備考 |
|---|---|---|---|---|---|---|
| **A** | 100% hard guarantee (token-level) | grammar-constrained decoding + 自由文向け CFG / regex constraint | **不可**（logits 非公開、JSON 以外への grammar 適用 API なし） | (該当ライブラリ前提) 中 | Outlines + ローカル Llama、guidance + open-weight | Anthropic API では原理的に不可能。実現にはモデル変更が必須 |
| **A'** | JSON 内文字列の pattern 制約 | Structured Outputs の `pattern` | 部分的に可能。ただし「N 語のうち全部を順不同で含む」は非現実的 | 低（grammar コンパイル 100〜300ms 初回のみ） | Anthropic Structured Outputs docs | キーワード必出に対しては事実上 D〜E 相当に劣化 |
| **B** | 100% via retry | 生成 → validator（grep / 正規表現で各キーワード検査）→ 不足キーワードを次の system プロンプトに明示して再生成。max_retries 制限 | **完全に可能**。instructor / 自前 retry で実装 | 低〜中（平均 1.1〜1.5x コール数）。「再現性ある失敗パターン」での retry loop poisoning に注意 | 多数（pithycyborg.substack, futureagi 2026 等）。標準パターン | **最有力**。検証が grep レベルで決定的なため、retry loop の hallucination poisoning リスクが低い |
| **C** | 〜99% soft（単発検証付き） | 強力な prompt（XML タグ・"必ず全て使う" 等）+ temperature=0 + 単発 validator。失敗時はログ通知のみ | 可能 | 最低（1.0x） | SEO content generation | キーワード数 ≤ 5 なら現実的。> 5 では失敗率が許容範囲を超える可能性 |
| **D** | best-effort（プロンプトのみ） | プロンプト内でキーワード列挙のみ。validator なし | 可能 | 最低 | 現状の cc-relative-info | **現状の挙動。3 日違いで 2〜5 語が出入りする問題の起点** |
| **E** | テンプレート埋め込み | 構造化テンプレ（"プロジェクト名 X は Y のために A・B・C をサポートする"）+ LLM スロット埋め | 可能 | 低 | discharge summary 生成、通知メッセージ生成（arXiv 2605.16264）等 | **キーワード 100% 含有が template 構造で物理保証される**。自然言語の柔軟性は低下するが、cc-relative-info の narrative のような短文には現実的選択肢 |
| **F** | ハイブリッド | 自由生成 → 検証 → 不足キーワードを末尾に補足配置（"関連: X, Y, Z" 等）。または 2 段階生成（narrative + keyword line） | 可能 | 低（補足配置は LLM 不要 or 1 追加コール） | プロダクト説明文生成、メタデータ補完 | **narrative の自然さを保ちつつキーワード必出を保証**できる。grep ヒットは保証、ただし narrative 本文の意味的網羅は保証しない |

### 2.2 cc-relative-info における各レベルの実現性

本リポジトリ固有の前提:
- Anthropic API（Claude Opus / Sonnet / Haiku）ベース
- 47 ターゲットを定期再生成（運用は CI / 手動 / バッチ）
- 自動運用前提（人手レビュー前提にはしたくない）
- llms.txt の冒頭 blockquote は 1〜2 文（80〜200 字程度）
- キーワード数は推定 5〜10 個（シナリオごとに変動）

| Lv | 実現性評価 |
|---|---|
| A | **不採用**。Anthropic API では原理的に不可能。モデルを差し替えればローカル Llama + Outlines で可能だが、品質・コスト・運用負荷が現状を上回る |
| A' | **限定採用候補**。JSON 出力構造とすれば一部キーワードを enum / const で固定でき、自然文部分は別フィールド化できる。テンプレート化に近づくため E に近い |
| **B** | **採用候補（第 1）**。grep ベース validator は決定的・高速。retry 上限 3 回程度、平均 1.2x コール数で 100% 保証が現実的。47 ターゲット定期更新の運用負荷も低い |
| C | **採用候補（妥協案）**。99% は許容できる用途であれば最安。ただし失敗ターゲットが「特定の珍しい固有名詞」に偏ると毎回同じターゲットで失敗するため、結局 B が必要 |
| D | **不採用**（現状の問題そのもの） |
| **E** | **採用候補（第 2）**。1〜2 文の narrative は構造が単純で、テンプレ化の品質劣化が小さい。ただし「47 リポジトリそれぞれの個性的な narrative」という従来のコンセプトと相性が悪い可能性 |
| **F** | **採用候補（第 3、軽量補完案）**。narrative 本文は自由生成のまま、不足キーワードを別行（例: "関連キーワード: X, Y, Z"）に append。grep ヒットは 100% 保証され、本文の自然さも維持。シナリオ別のキーワード集合を別行管理可能 |

### 2.3 シナリオ別の必要保証レベル（仮説）

P0.1 round 2 で確立した 7 シナリオに対し、本調査だけで推定できる範囲で必要保証レベルを示す（実証は P0.2 以降）:

| シナリオ | 利用者の発見手段 | 必要保証レベル仮説 | 理由 |
|---|---|---|---|
| **Scenario 1**: Claude Code が SDK 索引として llms.txt 利用 | LLM の semantic 把握主体（grep ではない） | **C〜D で可** | LLM は意味的近接で拾えるため、キーワード完全一致必須ではない |
| **Scenario 2**: 人起点 + Claude 自律参照（H/P 境界） | 同上（参照は Claude） | **C〜D で可** | 同上 |
| **Scenario 3**: 人が llms-full.txt を貼って Claude に質問 | llms.txt 冒頭の判断（人または Claude） | **C で可** | 「概要把握」目的。網羅性より読みやすさが優先 |
| **Scenario 4**: 自動投入パイプライン（CI / RAG / 社内同期） | **多くは grep / keyword index で初期スクリーニング** | **B 必須** | RAG embedding 前段の keyword filter で漏れると永久にヒットしない |
| **Scenario 5**: 版固定（保守 / 移行 / FT データセット） | バージョン文字列・API 名で grep | **B 必須**（特に固有名詞） | 「特定のクラス名・関数名・バージョン」が narrative になければ発見不能 |
| **Scenario 6**: コレクション横断（H ライブラリ選定 / P 定期監視） | **エンジニアが grep でカテゴリ判定**することが想定される | **B 必須**（少なくとも分類カテゴリ語は） | 横断比較の入口でキーワード網羅性が決定的 |
| **Scenario 7**: 同居非メンテナー利用 | 人間が冒頭読んで判断（コレクションナビ） | **C〜B**（What-is 理解語は B） | 「これは何のリポジトリか」を即座にわかる語は必出 |

→ **少なくとも Scenario 4 / 5 / 6 では B レベル保証が必要**。これらは grep / keyword index ベースの発見が前提のため、ソフトな保証では不十分。
→ Scenario 1〜3, 7 は C で許容できる可能性が高いが、シナリオを分離せず一括運用するなら **全体を B 基準で実装するのが合理的**。

---

## 推奨される次の調査ステップ

段階 3（実証実験）でまず試すべき優先順位:

1. **【最優先】B レベル（retry + validation）の実装と命中率測定**
   - 47 ターゲットに対し、シナリオ別に 5〜10 個の必出キーワード集合を仮置き
   - 初回生成 → grep validator → 不足あれば「不足キーワード一覧」を system に付加して再生成
   - 測定: 平均リトライ回数、最終成功率、品質（リトライ済み narrative が初回より不自然になっていないか）
2. **【次点】F レベル（ハイブリッド）のプロトタイプ**
   - narrative 本文は自由生成、validator で不足キーワードを検出し別行に append
   - 測定: 本文の自然さ（人による評価 + LLM-as-judge）と grep ヒット率の両立度
3. **【参考】C レベル（プロンプト改善単発）の限界点測定**
   - XML タグ + temperature=0 + 強い指示を最適化した場合に、リトライなしで何 % まで届くか
   - キーワード数を 3 / 5 / 7 / 10 と振った場合の degradation curve
4. **【捨て】A レベル**: Anthropic API ベースで現状不可能なので、モデル変更前提の調査は P0.2 以降の判断（cc-relative-info がモデル非依存運用を採るかどうかの方針決定が先）

---

## 制約と未解明事項

- **実証で測定すべき項目**:
  - cc-relative-info の現実のキーワード集合サイズ（推定 5〜10 個だが、シナリオ × ターゲットでばらつきあり）
  - B レベルでの平均リトライ回数（コスト試算の精度）
  - C レベルの実測命中率（学術文献からの推定は 85〜95% だが、Anthropic 最新モデル + XML タグ最適化の最良値は未測定）
  - retry loop hallucination poisoning の発生率（実運用での再現可能な失敗パターンの有無）
- **本調査だけでは判断できない点**:
  - シナリオ別キーワード集合の確定的定義（P0.2 以降の作業）
  - narrative の品質劣化を許容する閾値（人手レビューが入る前提の運用かどうか）
  - F レベル（ハイブリッド）の本文末尾補足配置が、Scenario 1〜3（Claude が semantic に読む）で逆効果にならないか（追加トークンがコンテキストを汚す可能性）
- **Anthropic API の今後の動向**:
  - 自由文への grammar 制約 API は現状未提供だが、Structured Outputs の拡張として将来追加される可能性はゼロではない（要 watch）
  - prefill のサポート復活も将来あり得るが、最新モデル群では明示的に廃止されているため当面は当てにできない

---

## 参照リンク・出典

### Anthropic 公式ドキュメント
- [Structured outputs - Claude API Docs](https://platform.claude.com/docs/en/build-with-claude/structured-outputs)
- [Strict tool use - Claude API Docs](https://platform.claude.com/docs/en/agents-and-tools/tool-use/strict-tool-use)
- [Increase output consistency - Claude API Docs](https://docs.anthropic.com/en/docs/test-and-evaluate/strengthen-guardrails/increase-consistency)
- [Use XML Tags to Structure Prompts - Claude API Docs](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/use-xml-tags)

### 学術論文
- NeuroLogic A*esque Decoding: Constrained Text Generation with Lookahead Heuristics (Lu et al., NAACL 2022) - [arXiv 2112.08726](https://arxiv.org/abs/2112.08726)
- Evaluating, Understanding, and Improving Constrained Text Generation for LLMs (Sun et al.) - [arXiv 2310.16343](https://arxiv.org/pdf/2310.16343)
- Unlocking Anticipatory Text Generation (Liu et al.) - [arXiv 2312.06149](https://arxiv.org/html/2312.06149)
- Guiding LLMs The Right Way: Fast, Non-Invasive Constrained Generation - [arXiv 2403.06988](https://arxiv.org/pdf/2403.06988)
- LLM-driven Constrained Copy Generation through Iterative Refinement - [arXiv 2504.10391](https://arxiv.org/html/2504.10391v1)
- XGrammar: Flexible and Efficient Structured Generation - [arXiv 2411.15100](https://arxiv.org/pdf/2411.15100)
- InFoBench: Evaluating Instruction Following Ability - [arXiv 2401.03601](https://arxiv.org/pdf/2401.03601)
- The Instruction Gap: LLMs get lost in Following Instruction - [arXiv 2601.03269](https://arxiv.org/pdf/2601.03269)
- AGENTIF: Benchmarking Instruction Following of LLMs (Tsinghua KEG) - [pdf](https://keg.cs.tsinghua.edu.cn/persons/xubin/papers/AgentIF.pdf)
- LLM-Based Intelligent Notification Composition - [arXiv 2605.16264](https://arxiv.org/html/2605.16264)

### ライブラリ・ツール
- [Awesome-LLM-Constrained-Decoding (Saibo-creator)](https://github.com/Saibo-creator/Awesome-LLM-Constrained-Decoding)
- [lm-format-enforcer (noamgat)](https://github.com/noamgat/lm-format-enforcer)
- [llguidance (guidance-ai)](https://github.com/guidance-ai/llguidance)
- [Outlines (dottxt-ai)](https://dottxt-ai.github.io/outlines/)
- [instructor (jxnl)](https://github.com/jxnl/instructor)
- [The best library for structured LLM output (Paul Simmering)](https://simmering.dev/blog/structured_output/)

### 業界記事
- [Claude API Structured Output: Complete Guide to Schema-Guaranteed Responses](https://thomas-wiegold.com/blog/claude-api-structured-output/)
- [Hands-On with Anthropic's New Structured Output (Towards Data Science)](https://towardsdatascience.com/hands-on-with-anthropics-new-structured-output-capabilities/)
- [Anthropic boosts Claude API with Structured Outputs (tessl.io)](https://tessl.io/blog/anthropic-brings-structured-outputs-to-claude-developer-platform-making-api-responses-more-reliable/)
- [Constrained Decoding: Grammar-Guided Generation for Structured LLM Output (Brenndoerfer)](https://mbrenndoerfer.com/writing/constrained-decoding-structured-llm-output)
- [The LLM Retry Loop That Looks Like Progress and Does Nothing](https://pithycyborg.substack.com/p/the-llm-retry-loop-that-looks-like)
- [LLM Verification Loops: Best Practices and Patterns (Williams, Medium)](https://timjwilliams.medium.com/llm-verification-loops-best-practices-and-patterns-07541c854fd8)
- [What is LLM Input/Output Validation? (futureagi 2026)](https://futureagi.com/blog/what-is-llm-input-output-validation-2026/)
- [Taming LLM Outputs: Your Guide to Structured Text Generation (Dataiku)](https://www.dataiku.com/stories/blog/your-guide-to-structured-text-generation)
- [Verification and Validation Loops for Agent Reliability (Muthu)](https://notes.muthu.co/2025/11/verification-and-validation-loops-for-agent-reliability-through-runtime-checks/)
