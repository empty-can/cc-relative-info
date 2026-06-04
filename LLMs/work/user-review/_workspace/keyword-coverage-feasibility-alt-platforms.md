# narrative キーワード網羅性: 非 Anthropic 代替の調査（B-10pre 拡張）

調査実施日: 2026-05-28
前段調査: `keyword-coverage-feasibility.md` 参照
スコープ: 非 Anthropic 選択肢の横断的調査（レイテンシ 9〜24h 許容前提）

---

## エグゼクティブサマリ

- **「自由文に対する token-level hard guarantee（レベル A）」の道具立ては、Anthropic API 単独では原理的に不可能だが、非 Anthropic を含めれば現実的に到達可能**。具体的には **オープンウェイトモデル + Outlines / lm-format-enforcer / llguidance（vLLM・llama.cpp バックエンド）** という構成が唯一の hard guarantee 経路。
- ただし「レベル A を実現するために narrative 品質を Claude Opus/Sonnet レベルから Llama 4 / Qwen 3 級に落とすか」というトレードオフが発生する。47 ターゲット × 日次〜週次という運用規模では **モデル品質劣化のリスクが採用の最大ブロッカー**となる。
- **Anthropic API 単独より優位な選択肢は存在する**が、それは「単一のプラットフォームに乗り換える」のではなく **ハイブリッド構成**（Anthropic で narrative 品質を担保 + 別プラットフォーム / 自前 validator でキーワード網羅性を保証）が現実解。
- **OpenAI Batch API** は Anthropic Batch と同等の 50% off / 24h SLA を提供するが、`logit_bias` も自由文 hard guarantee は提供しないため「Anthropic を OpenAI に置換すれば解決」とはならない。
- **24h レイテンシ許容**という新前提は、(a) Anthropic / OpenAI Batch API の活用（コスト半減）、(b) 自己ホスト推論の cron 運用（極端な低頻度なら現実的）、(c) 多段パイプライン（gen → critique → revise の 3〜5 回ループ）すべてを射程に入れる効果がある。リアルタイム性の制約から解放される意義は大きい。
- 推奨する 3 構成: **(1) Anthropic Batch + B レベル retry+validation（最小改造・最有力）**、**(2) Anthropic で narrative draft → 自前 grep validator → 不足キーワード補完で F レベル（軽量・最速実装）**、**(3) 検証専用に OpenAI gpt-5.4-mini Batch を併用する 2 段構成（コスト最適化）**。
- **レベル A を本気で追求する場合のみ、自己ホスト Outlines + Qwen 3 / Llama 4** が候補に上がるが、運用負荷（GPU・engineering 工数）を考慮すると 47 ターゲット規模では割高になる可能性が高い。

---

## 段階 1: 横断的プラットフォーム調査

### 1.1 商用 LLM API

| プラットフォーム | constrained generation | logit_bias | Batch API | キーワード保証適性 | コスト（標準/Batch、Flagship） | 備考 |
|---|---|---|---|---|---|---|
| **Anthropic** | JSON Schema 構造のみ（Structured Outputs / Strict tool use） | **なし** | あり（50% off / 24h SLA）。Opus 4.7 $2.50/$12.50 per MTok | 自由文 hard guarantee は不可 | Opus 4.7 $5/$25 → Batch $2.50/$12.50 / Sonnet 4.6 $3/$15 → Batch $1.50/$7.50 | 前段調査の通り。retry + validation で B レベルは可能 |
| **OpenAI** | JSON Schema strict mode（LLGuidance バックエンド・2025-05 以降）。`pattern` は ECMA-262 のサブセット | **あり**（-100〜+100、単一トークン単位） | あり（50% off / 24h SLA）。GPT-5.5 $2.50/$15 → $1.25/$7.50 | 自由文 hard guarantee は不可（logit_bias は確率操作、必出保証ではない） | GPT-5.5 $5/$30 → Batch $2.50/$15 / GPT-5.4-mini $0.75/$4.50 → Batch $0.375/$2.25 | logit_bias の運用上の限界（単一トークン制約、+80 以下は弱い、tokenization 問題）あり |
| **Google Gemini (Vertex AI)** | JSON Schema / function calling | 一部サポート（モデル依存） | あり（50% off / 24h SLA、BigQuery 連携可） | Anthropic 同等 | Gemini 2.5 Pro 系（同等価格帯）。詳細は Vertex AI pricing 参照 | Vertex AI Batch は **Claude モデルも対象**（マルチプロバイダ集約点として有用） |
| **Cohere** | structured output サポート、citations 付き | 限定的 | 限定情報 | RAG / citation 用途寄り | Command R+ $2.50/$10 / Command R7B $0.0375/$0.15 | R7B は極端に安価。検証用 LLM-as-judge に向く |
| **Mistral AI** | JSON mode / OpenAI 互換 API | あり | あり | OpenAI 同等 | Large 3 $2/$6 / Small 3.1 $0.20/$0.60 / Ministral 3B $0.04/$0.04 | EU データレジデンシー要件があるなら候補。Small 系は検証専用に好適 |
| **xAI** | Structured Outputs サポート | あり | 限定情報 | 範囲外 | - | 直接の優位性は限定的 |

> **結論**: 商用 API レイヤで「自由文に対する hard guarantee」を提供しているプラットフォームは現時点で存在しない。OpenAI の `logit_bias` は最も自由文制御に近づくが、(a) 単一トークン単位なので複数トークンからなるキーワード（特に日本語・複合語）には不向き、(b) +100 でも 100% 必出を保証しない、(c) tokenization のばらつきで取りこぼしが起きる、という根本的な制約がある。

### 1.2 OSS / 自己ホスト推論スタック

| ツール | サポート機能 | 必要インフラ | 統合難度 | キーワード必出（自由文）適性 | 備考 |
|---|---|---|---|---|---|
| **Outlines (dottxt-ai)** | regex / CFG / JSON Schema / Pydantic、token mask 適用 | OpenAI / Ollama / vLLM / llama.cpp 等の **logits アクセス可能な backend** が必要。API 経由でも Outlines サーバ提供あり | 中（既存パイプラインに inference 層追加） | **可**（regex `(?=.*kw1)(?=.*kw2)` で必出を強制可能。ただし複雑な lookahead は performance に影響） | 2026 年も最も汎用的な選択肢。AWS blog (2026-02) で本番採用事例あり |
| **lm-format-enforcer** | JSON / regex に decode-time 適合保証 | 同上 | 中 | 可 | Outlines と並ぶ標準。character-level parser でレイテンシ特性が異なる |
| **llguidance / guidance** | CFG-based、50μs/token クラスの高速 mask 計算 | vLLM / llama.cpp / SGLang / TensorRT-LLM の native backend | 低〜中（既に vLLM / llama.cpp が組み込み済み） | **可**（"select" / "gen with pattern" / lazy grammar で必出を表現） | 2025-05 から **OpenAI Structured Outputs の内部実装**として採用済み。事実上の業界標準 |
| **XGrammar** | JIT compile による grammar-constrained decoding | vLLM / SGLang / TensorRT-LLM | 低 | 可 | **2026 年最速**（< 40μs/token、near-zero overhead）。vLLM / SGLang / TensorRT-LLM の default backend |
| **vLLM** | guided_choice / guided_regex / guided_json / guided_grammar | GPU（H100 / A100 / RTX 系） | 中〜高（GPU 運用要） | 可（バックエンドに Outlines / XGrammar / LLGuidance） | OpenAI 互換 API で提供可能。本番運用向け |
| **llama.cpp** | GBNF grammar、lazy grammar、CPU 推論可能 | CPU で動作（GPU optional） | 低（個人 PC でも可） | 可（GBNF で必出表現） | 個人 PC でも 7B〜32B クラスは現実的。47 ターゲット × 週次なら CPU 推論でも回せる |
| **Ollama** | llama.cpp ベース、運用簡素化 | CPU / GPU 両対応 | **最低**（Docker レベル） | 可（llama.cpp 経由で grammar 使用） | プロトタイプには最適。本番には vLLM 推奨 |

> **重要**: 2025-05 以降、**OpenAI の Structured Outputs は内部で LLGuidance（guidance-ai）を採用**。つまり OSS 系の constrained decoding 技術は商用 API の内部実装としても標準化されている。OSS スタックを「使わない」場合でも、これらの技術知識は今後の API 機能拡張の予測に必須。

#### モデル品質との関係

- **Llama 4 / Qwen 3 / Mistral Large 3 / DeepSeek-V3** が 2026 年 5 月時点で主要なオープンウェイトフラッグシップ
- **Qwen 3.5 (3B active MoE)** は narrative 生成品質で 22-24B dense モデルを上回り、推論速度 2.6x 速いという報告
- **narrative 品質**（"プロジェクト名 X は Y のために A・B・C をサポートする" 級の短文）に限れば、Qwen 3 系・Llama 4 系で Claude Sonnet と概ね同等。Opus とは差があるという想定
- ただし **「複数キーワード必出」という制約下で自然な短文を書く能力**は、Claude / GPT-5 が依然として優位という経験則あり（IFEval 等のベンチマーク傾向から）

### 1.3 マルチパス / 構造化アプローチ

#### gen → critique → revise ループ

| アプローチ | 仕組み | キーワード網羅性への効果 | 実装難度 |
|---|---|---|---|
| **instructor (567-labs)** | Pydantic 検証 + retry。15+ provider 対応（Anthropic 含む） | 各 retry で「不足キーワード」を system に追加する custom validator を仕込めば B レベル達成 | **低**。Anthropic SDK / OpenAI SDK 両対応 |
| **DSPy Assertions** | `Assert`（hard）/ `Suggest`（soft, backtracking）。プロンプト最適化を compile time に行う | キーワード制約を Assert で表現可能。論文では制約遵守 +164%、品質 +37% | 中（パイプライン記述に DSPy 学習要） |
| **LangChain / LlamaIndex** | OutputParser + retry / RAG pipeline 部品 | 標準的な retry 機構あり。constrained generation 直接サポートはなし | 中（既存パイプラインを LangChain 化する必要） |
| **マルチエージェント検証** | generator agent → critic agent（別 LLM）→ reviser agent の反復 | gen を Anthropic Opus、critic を OpenAI / Cohere R7B 等の安価モデルで賄うとコスト効率良 | 中（プロンプト 3 つ＋オーケストレーション） |

> **本リポジトリへの示唆**: 既存パイプラインが Python スクリプト + Claude Code Skill 構成のため、**instructor + 自前 validator** が最小改造で B レベル達成可能。DSPy は学習コストが高いため、検証実験段階で導入するメリットは限定的。

### 1.4 バッチ処理の実用性（24h SLA 前提）

#### コスト比較（narrative 1 本あたり、input 2K + output 200 tokens 想定）

| 構成 | 単価 | 47 ターゲット日次 | 47 ターゲット週次 | 備考 |
|---|---|---|---|---|
| Anthropic Opus 4.7（standard） | ~$0.0150 | $0.70 / 日 ≒ $21 / 月 | $3.30 / 月 | 現状 |
| Anthropic Opus 4.7（Batch） | ~$0.0075 | $0.35 / 日 ≒ $10.5 / 月 | $1.65 / 月 | **50% off**。24h SLA |
| Anthropic Sonnet 4.6（Batch） | ~$0.0045 | $0.21 / 日 ≒ $6.3 / 月 | $0.99 / 月 | narrative には Sonnet で十分な可能性 |
| OpenAI GPT-5.5（Batch） | ~$0.0080 | $0.38 / 日 ≒ $11.4 / 月 | $1.79 / 月 | 同等価格帯 |
| OpenAI GPT-5.4-mini（Batch） | ~$0.0012 | $0.06 / 日 ≒ $1.7 / 月 | $0.27 / 月 | **検証専用 LLM-as-judge に好適** |
| Cohere Command R7B | ~$0.00007 | $0.003 / 日 ≒ $0.10 / 月 | $0.014 / 月 | **検証 LLM の最安手段**。narrative 本生成には品質不足の可能性 |
| 自己ホスト vLLM + Llama 4（H100 SXM5 $2.40/h） | GPU が空転すれば $1,728 / 月 | - | - | 47 × 日次の token 量では break-even（30M tok/日）に遠く及ばず、**API より高コスト** |
| 自己ホスト llama.cpp（個人 PC、CPU） | 電気代のみ（〜$5/月） | - | - | 個人 PC 運用なら可能。ただし可用性・冗長性は保証されない |

> **重要な含意**:
> 1. **47 ターゲット × 日次という運用規模では Batch API が常に最安**（自己ホストは break-even に届かない）
> 2. retry を 3 回平均で含めても月額 < $50 で収まる
> 3. 自己ホスト vLLM は「**constrained decoding が必須**」という要件があって初めて検討対象になる。コストでは絶対的に負ける
> 4. 個人 PC + llama.cpp は技術検証として有意義だが、本番運用としては可用性が低い

#### Batch API の運用上の注意

- Anthropic / OpenAI / Vertex AI とも **24h は最悪値**であり、実際は 1〜6h で完了するケースが多い（OpenAI 公称）
- バッチ提出 → 結果取得は非同期。**監視・失敗ハンドリング・部分再実行**の機構を組む必要あり
- prompt caching との併用で更に 25〜50% コスト削減可能（Anthropic / OpenAI とも）

---

## 段階 2: cc-relative-info への適合性

### 2.1 選択肢比較表

| 選択肢 | 保証レベル | 月額コスト概算（47 × 日次） | 実装複雑度 | 品質劣化リスク | 推奨度 |
|---|---|---|---|---|---|
| **(α) Anthropic Batch + retry（現行 + Batch 移行）** | B | $10〜15 | **低**（Batch API の非同期化のみ） | 低（同じモデル） | ★★★★★ |
| **(β) Anthropic Standard + retry + grep validator（現行ベース、リアルタイム）** | B | $25〜35 | 低 | 低 | ★★★★ |
| **(γ) Anthropic Batch + F レベル（narrative + キーワード補完行）** | F（grep ヒット 100%） | $10〜15 | 低 | 中（本文末尾の不自然さ） | ★★★★ |
| **(δ) Anthropic narrative + OpenAI Batch validator（2 段構成）** | B | $12〜18 | 中 | 低 | ★★★ |
| **(ε) OpenAI 単独に置換 + logit_bias** | C 相当（hard ではない） | $10〜15 | 中（プロンプト全面書き換え） | 中（narrative 品質低下リスク） | ★★ |
| **(ζ) 自己ホスト Outlines + Llama 4 / Qwen 3** | **A**（true hard guarantee） | GPU 常時稼働 $1,500〜 / spot 短時間運用 $50〜 | **高**（GPU 運用 + Outlines 統合 + 監視） | 中〜高（Claude 比） | ★★（A が本気で要るときのみ） |
| **(η) 個人 PC llama.cpp + GBNF** | **A**（true hard guarantee） | 電気代のみ | 中〜高（GBNF 設計 + 個人 PC 運用） | 高（モデルサイズ制約） | ★（プロトタイプ・実証用） |
| **(θ) Anthropic narrative + DSPy Assertions パイプライン** | B〜C | $15〜25 | 高（DSPy 学習要） | 低 | ★（学習コスト過大） |

### 2.2 7 シナリオへの適合性

前段調査 §2.3 で示した必要保証レベル仮説に対し、各選択肢の適合度を整理:

| シナリオ | 必要保証 Lv | 推奨選択肢 | 理由 |
|---|---|---|---|
| **Scenario 1**（Claude Code SDK 索引） | C〜D | α / γ | semantic 把握主体。Batch でコスト最適化 |
| **Scenario 2**（H/P 境界） | C〜D | α / γ | 同上 |
| **Scenario 3**（人が貼る llms-full.txt） | C | α | 可読性優先。Batch + Sonnet で十分 |
| **Scenario 4**（自動投入 / RAG） | **B 必須** | **α + 自前 grep validator** | 漏れ厳禁。retry で 100% 保証 |
| **Scenario 5**（版固定 / FT データセット） | **B 必須** | **α + 厳密 validator** | 固有名詞必出。retry + Assert ロジック |
| **Scenario 6**（コレクション横断） | **B 必須** | **α + カテゴリ語必出 validator** | 分類語が grep で見つからないと致命 |
| **Scenario 7**（同居非メンテナー） | C〜B | α / γ | What-is 理解語のみ B 必須、残りは C |

> **統一案**: Scenario 4 / 5 / 6 が要求する B レベルが全体の最大要件。**Scenario 別に分離せず、全体を α 構成（Anthropic Batch + retry + grep validator）で B 基準実装**するのが運用上合理的。Scenario 1 / 2 / 3 / 7 にとってもオーバースペックではなく、コスト負担も小さい。

---

## 段階 3: ハイブリッド構成の検討

### 3.1 構成パターン A: Anthropic Batch + 自前 grep validator + retry（最有力・最小改造）

```
[targets.txt] → [gen_llms_full.py 拡張]
                    ↓
              Anthropic Batch submit
                    ↓ (24h SLA、実態 1〜6h)
              結果取得 → grep validator (Python regex)
                    ↓
       全キーワード命中? ── Yes → llms.txt 確定
                    ↓ No
              不足キーワードを system に追加して再 Batch submit
                    ↓
              最大 3 retry → 全失敗時は warning 付きで暫定確定
```

- **保証レベル**: B（100% via retry）
- **月額コスト**: $10〜15（Opus Batch） or $5〜8（Sonnet Batch）
- **実装変更**: `gen_llms_full.py` に (1) Batch submit/poll ロジック、(2) keyword extraction（シナリオ別キーワード集合の管理）、(3) grep validator、(4) retry with feedback の 4 機能を追加
- **メリット**:
  - 既存モデル（Claude）の品質を維持
  - validator が grep ベースのため決定的・高速、retry loop poisoning リスク低い
  - Batch API でコスト半減
- **デメリット**:
  - 24h SLA を待つ運用フロー設計が必要（朝 9:00 提出 → 翌朝 9:00 取得など）
  - 失敗時のフォールバック（暫定確定 or 手動レビュー）方針が要決定

### 3.2 構成パターン B: Anthropic narrative + Outlines/Llama 4 自己ホスト（A レベル実現）

```
[Anthropic Opus Batch] → draft narrative
        ↓
[grep validator] → 不足キーワード集合 K
        ↓ (K が空でない場合のみ)
[Outlines + Llama 4 / Qwen 3 (vLLM)]
   ↓ regex (?=.*k1)(?=.*k2)... で必出強制再生成
        ↓
   token-level hard guarantee 出力 → llms.txt 確定
```

- **保証レベル**: A（token-level hard guarantee）
- **月額コスト**: Anthropic $5〜10 + GPU spot 短時間運用 $30〜60 = $35〜70
- **実装変更**: 上記 + Outlines / vLLM 環境構築、GPU プロビジョニング自動化、Llama 4 / Qwen 3 プロンプト調整
- **メリット**:
  - 第一段で Claude 品質、第二段で hard guarantee
  - 不足キーワードがあるターゲットのみ第二段を走らせるため平均コスト圧縮可能
- **デメリット**:
  - GPU 運用工数 10〜20h / 月（$750〜$3,000 の労務費換算）
  - 第二段の出力は Claude より自然さが劣る可能性。**第二段に流入したターゲットだけ品質劣化**するため、品質ばらつき問題が発生
  - Outlines + 複雑な regex のレイテンシが想定外に大きい場合がある（実測必要）

### 3.3 構成パターン C: Anthropic Batch + OpenAI Batch validator（2 段クラウド構成）

```
[Anthropic Opus Batch] → draft narrative
        ↓
[OpenAI GPT-5.4-mini Batch] → LLM-as-judge で「キーワード命中チェック + 不足リスト抽出」
        ↓ (grep だけでなく semantic な命中判定も併用)
不足あり? ── Yes → Anthropic で system に不足明示して再 Batch
        ↓ No → 確定
```

- **保証レベル**: B（retry）+ semantic 命中判定強化
- **月額コスト**: Anthropic $10〜15 + OpenAI mini $2〜3 = **$12〜18**
- **実装変更**: パターン A + OpenAI SDK 追加、judge プロンプト設計
- **メリット**:
  - semantic な「キーワードの言い換え検出」も拾える（例: "Kubernetes" の代わりに "k8s クラスタ" と書かれた場合の判定）
  - 2 つの provider 障害が同時発生する確率は低く、可用性向上
- **デメリット**:
  - LLM-as-judge は決定的でないため、validator 自体のばらつきが retry 回数を増やす可能性
  - API key 管理が 2 倍に

### 3.4 構成パターン比較

| 観点 | A (Anthropic Batch + grep) | B (Anthropic + 自己ホスト Outlines) | C (Anthropic + OpenAI judge) |
|---|---|---|---|
| 保証レベル | B（retry 100%） | **A（hard guarantee）** | B + semantic |
| 月額コスト | **$10〜15（最安）** | $35〜70 + 工数 | $12〜18 |
| 実装複雑度 | **低** | 高 | 中 |
| narrative 品質 | **高（Claude）** | 混在（Claude or Llama） | 高（Claude） |
| 障害耐性 | Anthropic 単一依存 | Anthropic + GPU | **マルチ provider** |
| 拡張性 | 高 | 中 | 高 |
| 推奨度 | **★★★★★ 第一推奨** | ★★（A が真に要るとき） | ★★★ 第三推奨 |

---

## 推奨される構成案（採用候補トップ 3）

### 第 1 推奨: 構成パターン A（Anthropic Batch + grep validator + retry）

- **理由**: 最小改造・最小コスト・最高 ROI。保証レベル B は本リポジトリの Scenario 4/5/6 要件を満たす
- **実装規模**: `gen_llms_full.py` に 300〜500 行の機能追加。1〜2 週間で実装可能と見込まれる
- **月額コスト**: $10〜15（Opus Batch）または $5〜8（Sonnet Batch でも narrative 品質が許容できれば）
- **段階 3 実証で確認すべき**: (a) 平均リトライ回数、(b) Batch SLA の実態（朝 9:00 → 夕方完了パターンが実際に成立するか）、(c) シナリオ別キーワード集合の確定

### 第 2 推奨: 構成パターン A + F レベル併用（補強オプション）

- 構成 A で 3 retry しても不足するキーワードが残ったターゲットに対し、**末尾に "関連キーワード: X, Y, Z" の補完行を機械的に追加**
- 全 47 ターゲットで grep ヒット 100% を保証しつつ、自然な narrative も維持
- 追加コスト: 0（Python 後処理のみ）
- **品質劣化リスクの最終セーフティネット**として機能

### 第 3 推奨: 構成パターン C（Anthropic + OpenAI judge、可用性重視）

- マルチプロバイダ構成による障害耐性が必要 / semantic 命中判定（言い換え検出）が必要な場合
- コスト追加分は月額 $2〜3 程度で済む
- ただし P0.2 以降で「言い換えが実際に問題になっているか」を実証してから採用判断

> **不採用**: 自己ホスト Outlines + Llama 4 構成。**A レベルが運用上必須でない**限り、GPU 運用工数と品質ばらつきリスクが利益を上回る。「A レベルが必須」と判明した場合のみ P0.3 以降で再検討。

---

## 制約と未解明事項

### 実証実験を要する点

1. **Batch SLA の実態運用**: 「朝 9:00 提出 → 夕方完了」が常に成立するかは Anthropic / OpenAI 公称の "実態 1〜6h" を 47 ターゲット同時提出で再現確認が必要
2. **平均リトライ回数**: 構成 A で Scenario 4/5/6 の必出キーワード（5〜10 個）を満たすのに平均何回のリトライが必要か。1.2x 程度と推定したが実測必要
3. **OpenAI logit_bias の自由文での実効性**: 本リポジトリでは構成 ε（OpenAI 単独）を推奨しなかったが、「+100 で日本語複合語キーワードがどこまで自然に必出されるか」は学術的興味のある測定
4. **Outlines + 複数 lookahead regex のレイテンシ**: `(?=.*kw1)(?=.*kw2)...` を 10 個並べた時の token mask 計算オーバーヘッド
5. **オープンウェイトモデルでの narrative 品質**: Qwen 3 / Llama 4 で Claude Sonnet と同等の「短文 narrative」が書けるかの実測（IFEval 系では同等とされるが、本リポジトリ用途固有の品質判断は別途必要）

### ライセンス・配布制約

- **Llama 4**: Meta Community License。商用利用可だが MAU 7 億超の条項あり（cc-relative-info は該当しない）
- **Qwen 3**: Apache 2.0。完全に自由
- **Outlines / lm-format-enforcer / llguidance / vLLM / llama.cpp**: Apache 2.0 / MIT 等で問題なし

### 本調査だけでは判断できない点

- narrative の最終品質要件（人手レビュー前提か完全自動か）。完全自動なら B 必須、人手レビュー前提なら C で許容可
- 「同じ narrative が日々再生成されるが微妙に変動する」ことの許容範囲。Batch + retry で安定性向上は期待できるが、temperature=0 + 同 prompt でも完全な再現性は保証されない
- 47 ターゲットのうち「日次更新が真に必要」なもの vs「週次・月次で十分」なものの内訳。コスト試算は日次前提だが、実需が週次なら更に 1/7 のコスト

---

## 参照リンク・出典

### 商用 API 公式ドキュメント
- [OpenAI Structured Outputs Guide](https://developers.openai.com/api/docs/guides/structured-outputs)
- [OpenAI Batch API Guide](https://developers.openai.com/api/docs/guides/batch)
- [OpenAI logit_bias Help](https://help.openai.com/en/articles/5247780-using-logit-bias-to-alter-token-probability-with-the-openai-api)
- [Anthropic Pricing (Batch)](https://platform.claude.com/docs/en/about-claude/pricing)
- [Vertex AI Batch Predictions (Gemini)](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/multimodal/batch-prediction-gemini)
- [Vertex AI Batch Predictions (Claude on Vertex)](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/partner-models/claude/batch)
- [Mistral API Pricing](https://pricepertoken.com/pricing-page/provider/mistral-ai)
- [Cohere Pricing](https://www.aipricing.guru/cohere-pricing/)

### OSS Constrained Decoding
- [Outlines (dottxt-ai)](https://dottxt-ai.github.io/outlines/latest/)
- [Outlines Regex Reference](https://dottxt-ai.github.io/outlines/latest/reference/generation/regex/)
- [lm-format-enforcer (noamgat)](https://github.com/noamgat/lm-format-enforcer)
- [llguidance (guidance-ai)](https://github.com/guidance-ai/llguidance)
- [LLGuidance Tech Blog](https://guidance-ai.github.io/llguidance/llg-go-brrr)
- [XGrammar (vLLM 統合)](https://blog.vllm.ai/2025/01/14/struct-decode-intro.html)
- [vLLM Structured Outputs](https://docs.vllm.ai/en/latest/features/structured_outputs/)
- [llama.cpp Grammars README](https://github.com/ggml-org/llama.cpp/blob/master/grammars/README.md)

### マルチパス / パイプラインフレームワーク
- [Instructor (567-labs/jxnl)](https://python.useinstructor.com/)
- [DSPy (stanfordnlp)](https://github.com/stanfordnlp/dspy)
- [DSPy Assertions Paper (arXiv 2312.13382)](https://arxiv.org/abs/2312.13382)

### コスト・運用記事（2026）
- [Anthropic API Pricing 2026 (finout.io)](https://www.finout.io/blog/anthropic-api-pricing)
- [OpenAI Batch API 2026 Guide (tokenmix.ai)](https://tokenmix.ai/blog/openai-batch-api-pricing)
- [Self-Hosting AI 2026 TCO (pooya.blog)](https://pooya.blog/blog/self-hosting-ai-infrastructure-open-source-2026/)
- [Self-Host LLM vs API Cost 2026 (devtk.ai)](https://devtk.ai/en/blog/self-hosting-llm-vs-api-cost-2026/)

### モデル比較（2026）
- [Best Open-Source LLMs May 2026 (web3aiblog)](https://www.web3aiblog.com/blog/best-open-source-llms-llama-4-qwen-3-deepseek-v3-mistral-large-3-may-2026)
- [Local LLM Inference 2026 Guide (dev.to/starmorph)](https://dev.to/starmorph/local-llm-inference-in-2026-the-complete-guide-to-tools-hardware-open-weight-models-2iho)

### llms.txt 自体の運用記事
- [LLMs.txt Complete Guide 2026 (derivatex)](https://derivatex.agency/blog/llms-txt-guide/)
- [llms.txt in 2026 (limy.ai)](https://limy.ai/blog/llms.txt-in-2026-the-full-guide)
