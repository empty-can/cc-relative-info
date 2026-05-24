# gen-llms-txt

`llms.txt` と `llms-full.txt` をリポジトリから自動生成するスクリプト群。

## ファイル構成

| ファイル | 内容 |
|---|---|
| `template.md` | `llms.txt` のテンプレート（プレースホルダ付き） |
| `validate.sh` | 生成した `llms.txt` を `llms_txt2ctx` で検証するヘルパー |
| `gen_llms_full.py` | Type A / C 向け `llms-full.txt` 生成スクリプト（Phase 1〜2 で作成） |
| `gen_nb_llms_full.py` | Type D（nbdev/Jupyter）向け（Phase 4 で作成） |

## 事前準備

```bash
pip install codesigs llm-ctx
```

## 使い方

### validate.sh — 生成した llms.txt の検証

```bash
bash LLMs/scripts/gen-llms-txt/validate.sh <llms.txt のパス>
```

- 成功: `OK: <ファイル名>` を出力して exit 0
- 失敗: エラー内容を出力して exit 1

### gen_llms_full.py — llms-full.txt の生成（Phase 1〜2 実装後）

```bash
# Type A（ドキュメント系）
python LLMs/scripts/gen-llms-txt/gen_llms_full.py <repo_path> --base-url <url>

# Type C（ソースコード系）— --extract-sigs を追加
python LLMs/scripts/gen-llms-txt/gen_llms_full.py <repo_path> --base-url <url> --extract-sigs
```

## Skill 経由での実行（Phase 3 実装後）

```
/generate-llms-txt --target <ローカルパスまたは GitHub URL>
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
