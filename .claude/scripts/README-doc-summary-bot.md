# 公式ドキュメント更新サマリ 自動生成パイプライン（doc-summary-bot）

`update-official-doc-summary` Skill を**無人（ヘッドレス）で日次実行**するための運用一式。
Skill 単体の仕様は `.claude/skills/update-official-doc-summary/README.md` を参照。本書はその
一段上の「自動化レイヤ」（ラッパー・スケジューラ・push 認証・多層レビュー・異常系通知）を扱う。

## 全体フロー

```
タスクスケジューラ（毎日 N 時）
  └─ run-doc-summary.ps1 -Site all
       1. 前提チェック（tracked 未コミットなし）
       2. bot ブランチ work/LLMs/doc-summary-bot を feature/LLMs から作成 / 取り込み
       3. dl_llms.sh で公式 llms.txt 取り込み → commit
       4. サイト毎に原文差分を判定
       5. 差分ありサイトを claude -p（Opus）で生成
            └─ SKILL Phase 3: doc-summary-reviewer（Sonnet）で第三者レビュー（無人時必須・最大3回）
       6. 生成サマリを commit
       7. bot ブランチ限定 push（inline credential helper + DPAPI トークン）
          ※ DryRun / 生成失敗 / レビュー打ち切り 時は push 抑止
                  │
                  ▼
  人手レビュー → bot → feature/LLMs → develop へマージ（= 品質ゲート）
```

**設計の要点**: Claude の実行領域を最大化しつつ、品質は「セルフレビュー（Phase 1/2）→ 第三者
Agent（Sonnet, Phase 3）→ 人間（develop へのマージ）」の 3 層で担保する。生成は Opus、レビューは
Sonnet とモデルを分けて確証バイアスを抑える。`develop`/`main` へは構造的に push しない（push 先を
ブランチ名で固縛し、push 直前に現在ブランチを assert）。

## 構成ファイル

| ファイル | 役割 |
|---|---|
| `run-doc-summary.ps1` | 中核ラッパー。dl→生成→commit→bot 限定 push を無人実行 |
| `register-doc-summary-task.ps1` | タスクスケジューラへの日次登録ヘルパー |
| `notify-bot-branch.sh` | SessionStart で「bot に未確定生成あり」を通知（異常系の後追い検出） |
| `.claude/agents/doc-summary-reviewer.md` | Phase 3 の第三者レビューア（Sonnet, read-only） |
| `.claude/skills/update-official-doc-summary/` | 生成本体の Skill（Phase 3 ループ込み） |

## 初回セットアップ（作業指示者が一度だけ実施）

### 1. push 用 PAT の発行

GitHub の **fine-grained PAT** を推奨。最小権限・短期限で発行する:

- リポジトリ: `empty-can/cc-relative-info` のみ
- 権限: **Contents: Read and write** のみ（push に必要な最小）
- 有効期限: 短め（例 90 日）。失効時は再発行して下記 2 を再実行

### 2. トークンを DPAPI 暗号化して保管

PowerShell で以下を実行（**対話入力**でトークンを貼り付ける。履歴・平文ファイルに残さない）:

```powershell
Read-Host "PAT を貼り付け" -AsSecureString |
  Export-Clixml "$env:USERPROFILE\.claude\doc-summary-bot-token.xml"
```

`Export-Clixml` は SecureString を **DPAPI（CurrentUser スコープ）で暗号化**して保存する。
復号は**同一 Windows ユーザー・同一マシン**でのみ可能（別ユーザー/別マシンでは復号不可）。
ラッパーは push の瞬間だけこのファイルを復号し、inline credential helper 経由で git に渡す
（URL・コマンド引数・ログにトークンを出さない）。

### 3. 単体 dry-run で一周検証（push しない）

```powershell
pwsh -NoProfile -File .claude\scripts\run-doc-summary.ps1 -Site all -DryRun -RestoreBranch
```

`-DryRun` は push のみ抑止し、dl・生成・commit はローカルで実施する。`-RestoreBranch` は終了時に
開始ブランチへ戻す。ログは `LLMs/work/doc-summary-bot/run-<日時>.log`（gitignore）。
生成結果は bot ブランチにコミットされるので、内容を確認してから feature/LLMs へマージする。

### 4. タスクスケジューラへ登録

```powershell
# まず内容確認（実登録しない）
pwsh -NoProfile -File .claude\scripts\register-doc-summary-task.ps1 -At 07:00 -WhatIfOnly
# 問題なければ登録
pwsh -NoProfile -File .claude\scripts\register-doc-summary-task.ps1 -At 07:00
```

既定は **Interactive ログオン**（ユーザーがログオン中のみ実行）。これは DPAPI トークンが S4U
（パスワードなし）ログオンでは復号できない場合があるため。ログオフ中も走らせたい場合は
`-RunWhenLoggedOff` を付けるが、**その構成では DPAPI 復号可否を実走で必ず確認**すること。

## ラッパー run-doc-summary.ps1 のパラメータ

| パラメータ | 効果 |
|---|---|
| `-Site <all\|claude-code-docs\|mcp>` | 対象サイト。既定 `all` |
| `-DryRun` | push のみ抑止（dl・生成・commit は実施）。検証用 |
| `-SkipDownload` | dl_llms.sh をスキップ（取り込み済み状態で生成だけ試す） |
| `-RestoreBranch` | 終了時に開始ブランチへ戻す（手動テスト時の利便） |

終了コード: 正常 0 / 異常（生成失敗・push 抑止・例外）1。

## 異常系と通知

ラッパーは以下を**自律的に**処理する:

- **生成失敗**（claude 非ゼロ終了 or JSON `is_error`）: 当該サイトの生成途中物をロールバックし、
  以後 push を抑止（他サイト・dl コミットは保持）
- **レビュー打ち切り**（Phase 3 が 3 回 FAIL）: SKILL が非ゼロ終了 → ラッパーが push 抑止
- **push 失敗**: 例外を捕捉してログ記録・終了コード 1

これらの異常時、生成コミットは **bot ブランチにローカル残存**する。次回セッション開始時に
`notify-bot-branch.sh`（共有 `settings.json` の SessionStart hook）が
「feature/LLMs へ未マージの bot コミットあり」を検出して通知するので、人手で内容を確認し、
マージするか破棄するか判断する。

```
⚠ doc-summary-bot に未確定の自動生成サマリがあります（feature/LLMs へ未マージ: N 件）。
```

## トラブルシュート

| 症状 | 対処 |
|---|---|
| `トークンファイル ... が無い` | 初回セットアップ 2 を実施 |
| `トークン復号に失敗` | 別ユーザー/別マシンで実行している。発行マシン・同一ユーザーで再セットアップ |
| push が 401 | PAT の失効・権限不足。fine-grained PAT の Contents:write と期限を確認し再セットアップ |
| `作業ツリーに未コミットの変更があります` | tracked の変更を commit / stash してから再実行 |
| スケジュール実行だけ push が失敗 | S4U での DPAPI 復号失敗の可能性。Interactive ログオン構成へ変更（既定）|
| 初版が `スキップ` される | 当該サイトの `latest-detail.md` 未作成。手動で `/update-official-doc-summary --site <slug> --from <commit>` を一度実行して初版を作る |

## 関連

- Skill 仕様: `.claude/skills/update-official-doc-summary/README.md`
- 第三者レビューア: `.claude/agents/doc-summary-reviewer.md`
- ブランチ運用ルール: ルート `CLAUDE.md`（feature/* → develop、work/* → feature）
