# LLMs/llms-txt-official-repos/CLAUDE.md

llms.txt エコシステムの AnswerDotAI 公式リポジトリを submodule で管理するフォルダ。
各リポジトリの概要・用途・相互関係は `README.md` 参照。

## 何をしたいかと使うツールの対応

| やりたいこと | 使うツール | コマンド例 |
|---|---|---|
| Python パッケージの API 一覧を markdown で出力 | `pysymbol-llm/` | `pysym2md <package_name> --output_file apilist.txt` |
| Python/多言語ソースからシグネチャを抽出 | `codesigs/` | `file_sigs('path/to/file.py')` (Python API) |
| Jupyter ノートブックを LLM 用 XML に変換 | `nbs2ctx/` | `nbs_to_ctx nbs/ ctx.xml` |
| `llms.txt` → XML コンテキストファイルに展開 | `llm-ctx/` または `llms-txt/` | `llms_txt2ctx llms.txt > llms-ctx.txt` |
| `llms.txt` の仕様・フォーマットを確認 | `llms-txt/nbs/index.qmd` | （ファイルを直接参照） |

## インストール方法

各ツールは submodule としてソースがあるが、実行には pip インストールが必要:

```bash
pip install pysymbol_llm   # pysymbol-llm/
pip install codesigs       # codesigs/
pip install nbs2ctx        # nbs2ctx/
pip install llm-ctx        # llm-ctx/（軽量版）
# または
pip install llms-txt       # llms-txt/（フル版）
```

## codesigs 対応言語

Python / JavaScript / TypeScript / Java / Rust / C# / CSS / Go / Ruby / PHP / Kotlin / Swift / Lua（12 言語以上）
