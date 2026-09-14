# 実測スクリプト（`結論・構成案_ポータブルな.claude共有_v2.0.md` の 【実測】 の再現用）

v2.0 本文で 【実測】 と記した事実を再現するためのスクリプト。**2026-09-14 に CLI v2.1.266 / git 2.46.0 / Windows 11（Git Bash）で実行したもの**をそのまま置いてある。

本文の [実測記録の再現手順](../結論・構成案_ポータブルな.claude共有_v2.0.md#repro) から参照される。

## 実行方法

いずれも Git Bash（または任意の bash）から実行する。**各スクリプトは自分と同じディレクトリに作業用フォルダを掘り、毎回作り直す**（`rm -rf` してから `mkdir`）。リポジトリを汚さないよう、生成物は `.gitignore` 済み。

```bash
cd reports/01.配布・統制方針調査/verification
bash switch-fail.sh
```

## スクリプト一覧

| スクリプト | 測るもの | 本文の対応節 |
|---|---|---|
| `nestclone-setup.sh` | **足場作成**: 作業リポジトリ（git 管理・`.gitignore` に `.claude/`）の `.claude/` が別リポジトリのクローン、という案C-1 の実形状を組む | §3-1 |
| `nestclone-run.sh` | 上記の足場で、`CLAUDE.md` / `paths:` なし rule / `settings.json` の `env` / skill の 4 資産がロードされるかを合言葉で回収する。**skill は自己申告ではなく Skill ツールの起動成否で判定する** | §3-1 |
| `nestclone-branch.sh` | ブランチ運用の一巡（子ブランチ作成 → 親更新 → rebase 追従 → 消費側の切替 → `settings.local.json` の保護）。**このスクリプトの実行中に D/F コンフリクトを踏んだ**のが §5-3 の命名規約の発端 | §5-3 |
| `nestclone-branch2.sh` | 上記を**葉トークン命名**（`java/base` 形式）でやり直し、多段 rebase から消費側の切替まで通す | §5-3 / §5-4 |
| `nestclone-updaterefs.sh` | `rebase.updateRefs` が中間ブランチを一括更新すること、および**中間ブランチをローカルに持たないクローンでは黙って取り残される**こと | §5-4 |
| `trigger-setup.sh` | **足場作成**: 1 つのサブディレクトリ `sub/` に 3 資産（`paths:` 付き rule の対象ファイル・`sub/CLAUDE.md`・`sub/.claude/skills/`）を同居させ、1 回の先行操作で 3 つとも発火しうる状態にする | §3-2 |
| `trigger-run.sh` | 先行操作の種類（なし / Read / Bash `cat` / Grep）ごとに 1 セッションずつ起動し、発火を判定する。**合言葉を読みに行けないよう、先行操作用ツールと `Skill` だけを許可する** | §3-2 |
| `trigger-edit.sh` | Edit ツール単独での発火を測る | §3-2 |
| `ffonly-test.sh` | リモートが rebase + force-push した後、消費側の `git pull --ff-only` が exit 128 で失敗すること、`fetch` + `switch` + `reset --hard` で復旧できること、ignore 済み `settings.local.json` が残ること | §5-5 |
| `switch-fail.sh` | **`switch` の失敗を検査せずに `reset --hard` を続けると、ブランチ名は保たれたまま中身が別ブランチで上書きされる**こと | §5-6 |

## 読むときの注意

- **`trigger-edit.sh` の冒頭コメントは、実行前の仮説のまま残してある。** 「作業ディレクトリ配下のファイルなので Edit は事前 Read を要求しないはず」と書いてあるが、**実測はこれを否定した** —— Edit は作業ディレクトリ配下でも `File has not been read yet. Read it first before writing to it.` で失敗する。**結論は本文 §3-2 を見ること。** スクリプトのコメントは実行時点の記録として書き換えていない
- **判定にモデルの自己申告を使っていない。** skill のロード判定は `Skill` ツールを実際に起動して成否を見る形にしてある。検証中、モデルが「skill はロードされています」と答え、その理由まで作文した事例があったため（本文 §3-2 の「判定を誤りやすい点」）
- **`--debug` のログには nested ロードが記録されない。** ログの有無でロードの有無を判定しないこと
- **CLI の版が上がったら測り直すこと。** 本文の判断のうち条件付きロードに関するものは版依存である（§8-1）
