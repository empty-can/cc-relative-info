# cc-relative-info

Claude Code の利用に役立つ情報を収集・整備するリポジトリ。現在は **LLM 関連情報収集**（公式 `llms.txt` の取り込み・生成）、**Claude Code 拡張の整備**、および **`.claude/` チーム共有・統制の調査/設計/運用手順**（`claude-dir-sharing-governance/`）を進めている。

## 📰 公式ドキュメント更新サマリ

各公式サイトのドキュメント（`llms.txt` / `llms-full.txt`）の更新差分を、人間向けの changelog / リリースノート風にまとめたサマリです。サイトごとに **ライト版**（要点を素早く把握）と **詳細版**（背景・解説つき）の 2 種を用意しています。

| サイト | ライト版（要点） | 詳細版（解説つき） |
|---|---|---|
| **Claude Code Docs** | [latest.md](./LLMs/official-doc-update-summary/claude-code-docs/latest.md) | [latest-detail.md](./LLMs/official-doc-update-summary/claude-code-docs/latest-detail.md) |
| **Model Context Protocol** | [latest.md](./LLMs/official-doc-update-summary/mcp/latest.md) | [latest-detail.md](./LLMs/official-doc-update-summary/mcp/latest-detail.md) |

- **ライト版** (`latest.md`): ハイライト・新規追加・更新ページを箇条書きで一覧化。各項目から詳細版の該当セクションへリンクします。
- **詳細版** (`latest-detail.md`): 各トピックを段落で解説し、対応する公式ページへのリンクを併記します。

最新の対象期間:

- Claude Code Docs: 2026年05月31日 〜 2026年06月02日（Week 21 / Week 22 反映）
- Model Context Protocol: 2026年05月29日 〜 2026年06月02日（SEP-2243 / SEP-2663 ほか）

> サマリは `/update-official-doc-summary` Skill で生成しています。過去分は各サイトフォルダの `archives/<日付>/` に退避されます。

## リポジトリ構成

```
LLMs/                          # LLM 関連情報収集（llms.txt の定期取り込み・生成、更新サマリ）
Extensions/                    # Claude Code 拡張（Skill / Rule / Plugin）のインデックス整備
claude-dir-sharing-governance/ # .claude チーム共有・統制の調査/設計/運用手順（完成版マスタ）
.claude/                       # 運用設定資産（Skill / Rule / Agent / テンプレート等）
```

各フォルダの詳細は配下の `CLAUDE.md` / `README.md` を参照してください。
