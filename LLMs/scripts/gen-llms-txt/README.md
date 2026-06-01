# gen-llms-txt

`llms.txt` と `llms-full.txt` をリポジトリから自動生成するスクリプト群。

## ファイル構成

| ファイル | 内容 |
|---|---|
| `gen_llms.sh` | バッチエントリ。`targets.txt` を読み、clone → 生成 → validate を一括実行 |
| `gen_llms_full.py` | `llms.txt` / `llms-full.txt` 本体生成スクリプト（Type A: .md/.mdx/.rst/.adoc/.ipynb、Type C: ソースシグネチャ） |
| `validate.sh` | 生成した `llms.txt` を `llms_txt2ctx` で検証するヘルパー |
| `targets.txt` | `gen_llms.sh` / `--target-list` 用のターゲット一覧 |
| `targets.example.txt` | `targets.txt` 記述パターンのテンプレート |
| `template.md` | `llms.txt` のテンプレート（プレースホルダ付き） |

## 事前準備

```bash
pip install codesigs llm-ctx
```

## 使い方

`dl_llms.sh` と同じく、リポジトリルートから shell で起動できる。
LLM 補完（blockquote / description プレースホルダ置換）が要らない／後回しで構わない
バッチ実行はこの経路を使う。LLM 補完まで含めたい場合は `/generate-llms-txt` Skill を使う。

### gen_llms.sh — バッチ実行（推奨エントリ）

```bash
# targets.txt を読んで全件処理
bash LLMs/scripts/gen-llms-txt/gen_llms.sh

# 別のターゲット一覧ファイルを指定
bash LLMs/scripts/gen-llms-txt/gen_llms.sh --target-list <path/to/list.txt>

# ヘッダコメントをそのまま表示
bash LLMs/scripts/gen-llms-txt/gen_llms.sh --help
```

各ターゲットについて以下を順に実施する:

1. GitHub URL → `LLMs/work/tmp-clone/<owner>/<repo>/` に `--depth=1` clone（既存なら pull）
2. `gen_llms_full.py` を `--skip-if-unchanged` 付きで起動して生成
3. `validate.sh` で生成物を検証

出力先 `LLMs/work/gen-out/` の `llms.txt` / `llms-full.txt` には `{BLOCKQUOTE}` /
`{DESCRIPTION}` プレースホルダが**残った状態**で出力される。`/generate-llms-txt`
Skill か手動で別途補完する想定。

### gen_llms_full.py — 単発（プログラマブル用途）

クローン済みのローカルリポジトリ 1 件を直接処理したい場合に使う:

```bash
# Type A（ドキュメント系）
python LLMs/scripts/gen-llms-txt/gen_llms_full.py <repo_path> --base-url <url>

# Type C（ドキュメント + ソースシグネチャ）
python LLMs/scripts/gen-llms-txt/gen_llms_full.py <repo_path> --base-url <url> --extract-sigs

# Claude Code 拡張リポジトリ向け（--extract-sigs 相当を自動有効化）
python LLMs/scripts/gen-llms-txt/gen_llms_full.py <repo_path> --base-url <url> --cc-extensions
```

### validate.sh — 検証

```bash
bash LLMs/scripts/gen-llms-txt/validate.sh <llms.txt のパス>
```

- 成功: `OK: <ファイル名>` を出力して exit 0
- 失敗: エラー内容を出力して exit 1

## Skill 経由での実行（LLM 補完込み）

```
/generate-llms-txt --target <ローカルパスまたは GitHub URL>
/generate-llms-txt --target-list LLMs/scripts/gen-llms-txt/targets.txt
```

詳細は `.claude/skills/generate-llms-txt/SKILL.md` 参照。

## セクション自動分類ルール

ファイルパスに含まれるキーワードでセクションを決定する:

| キーワード | 分類先 |
|---|---|
| `install`, `setup`, `quickstart`, `getting-started`, `start` | Getting Started |
| `api`, `reference`, `spec` | API Reference |
| `guide`, `tutorial`, `how-to`, `howto`, `example` | Guide |
| `changelog`, `release`, `faq`, `contributing`, `license`, `security` | Optional |
| それ以外 | Guide（フォールバック） |
| `README.md` | セクションに含めない |
