<#
.SYNOPSIS
  公式ドキュメント更新サマリ自動生成パイプラインのラッパー（無人実行用）。

.DESCRIPTION
  Windows タスクスケジューラから起動される想定。専用 bot ブランチ上で
  dl→差分判定→ヘッドレス生成（claude -p）→commit→bot ブランチ限定 push を行う。
  品質ゲートは「人間が bot→feature/LLMs→develop へマージする」段階に置く。
  develop/main へは構造的に push しない（push 先をブランチ名で固縛 + 実行直前に assert）。

.PARAMETER Site
  対象サイト。"all"（既定）/ "claude-code-docs" / "mcp"。

.PARAMETER DryRun
  push のみ抑止する。dl・生成・commit はローカルで実施する（一周の検証用）。

.PARAMETER SkipDownload
  dl_llms.sh をスキップする（既存の取り込み済み状態で生成のみ試すテスト用）。

.PARAMETER RestoreBranch
  終了時に開始前のブランチへ戻す（手動テスト時の利便のため。既定は戻さない）。

.NOTES
  実行モードは子プロセスへ環境変数 DOC_SUMMARY_AUTOMATED=1 で伝え、SKILL の
  Phase 3（第三者レビュー）を必須化する。
#>
[CmdletBinding()]
param(
    [ValidateSet("all", "claude-code-docs", "mcp")]
    [string]$Site = "all",
    [switch]$DryRun,
    [switch]$SkipDownload,
    [switch]$RestoreBranch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- 定数 -------------------------------------------------------------------
$BOT_BRANCH  = "work/LLMs/doc-summary-bot"
$BASE_BRANCH = "feature/LLMs"
$REPO_ROOT   = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$LOG_DIR     = Join-Path $REPO_ROOT "LLMs\work\doc-summary-bot"
$GEN_MODEL   = "opus"               # ヘッドレス生成のモデル（レビューは agent 定義で sonnet 固定）
# bot push 用 PAT を DPAPI 暗号化して保管するファイル（同一ユーザー・同一マシンでのみ復号可）。
# 初回セットアップ: Read-Host -AsSecureString | Export-Clixml $TOKEN_FILE
$TOKEN_FILE  = Join-Path $env:USERPROFILE ".claude\doc-summary-bot-token.xml"
# claude が SKILL 実行で使うツール群（acceptEdits と二重で明示）
$ALLOWED_TOOLS = "Read Write Edit Grep Bash(git diff:*) Bash(git log:*) Bash(git rev-parse:*) Bash(mkdir -p:*) Bash(mv:*) Bash(python:*) Bash(echo:*) Task Agent(doc-summary-reviewer)"

# サイト設定（SKILL.md サイト設定テーブルと一致させる）
$SITES = @(
    [pscustomobject]@{ Slug = "claude-code-docs"; Input = "LLMs/official-llms-txts/code.claude.com/docs/"; Detail = "LLMs/official-doc-update-summary/claude-code-docs/latest-detail.md" }
    [pscustomobject]@{ Slug = "mcp";              Input = "LLMs/official-llms-txts/modelcontextprotocol.io/"; Detail = "LLMs/official-doc-update-summary/mcp/latest-detail.md" }
)

# --- ログ -------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $LOG_DIR | Out-Null
$LOG_FILE = Join-Path $LOG_DIR ("run-{0}.log" -f (Get-Date -Format "yyyyMMdd-HHmmss"))

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    $line | Tee-Object -FilePath $LOG_FILE -Append
}

# git をラップし、失敗時に例外化（$LASTEXITCODE を確実に判定）
function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
    $out = & git @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($GitArgs -join ' ') が失敗 (exit $LASTEXITCODE): $out"
    }
    return $out
}

# bot ブランチ限定 push。GCM を一時無効化し、User scope の PAT を inline
# credential helper 経由でその push 1 回だけ git に渡す（URL/引数/ログに露出させない）。
# 無人実行で GCM の GUI プロンプトが出ないため確実に非対話で push できる。
function Invoke-BotPush {
    param([string]$Branch)
    if (-not (Test-Path $TOKEN_FILE)) {
        throw "トークンファイル $TOKEN_FILE が無い。初回セットアップ (Export-Clixml) を実施してください"
    }
    # DPAPI 復号（同一 Windows ユーザー・同一マシンでのみ成功する）
    try {
        $sec = Import-Clixml $TOKEN_FILE
        $token = (New-Object System.Management.Automation.PSCredential("x-access-token", $sec)).GetNetworkCredential().Password
    } catch {
        throw "トークン復号に失敗（別ユーザー/別マシンでは復号不可）: $($_.Exception.Message)"
    }
    if ([string]::IsNullOrEmpty($token)) { throw "復号したトークンが空です" }
    # sh 関数が展開する変数。PowerShell ではなく git の子 sh が参照する
    $env:GH_PUSH_TOKEN = $token
    try {
        $helper = '!f() { echo username=x-access-token; echo "password=$GH_PUSH_TOKEN"; }; f'
        $out = & git -c credential.helper= -c "credential.helper=$helper" push origin $Branch 2>&1
        if ($LASTEXITCODE -ne 0) { throw "push 失敗 (exit $LASTEXITCODE): $out" }
        return $out
    } finally {
        Remove-Item Env:\GH_PUSH_TOKEN -ErrorAction SilentlyContinue
    }
}

# --- メイン -----------------------------------------------------------------
Set-Location $REPO_ROOT
Write-Log "=== run-doc-summary 開始 (Site=$Site DryRun=$DryRun SkipDownload=$SkipDownload) ==="

$startBranch = (& git rev-parse --abbrev-ref HEAD).Trim()
$hadFailure  = $false
$pushAborted = $false

try {
    # 1. 前提: tracked の未コミット変更が無いこと（untracked は無視）
    $dirty = & git status --porcelain --untracked-files=no
    if ($dirty) {
        throw "作業ツリーに未コミットの変更があります。bot ブランチ操作前にクリーンにしてください:`n$dirty"
    }

    # 2. bot ブランチ準備（無ければ BASE から作成、有れば BASE を取り込み最新化）
    & git rev-parse --verify --quiet $BOT_BRANCH 2>$null | Out-Null
    $botExists = ($LASTEXITCODE -eq 0)
    if ($botExists) {
        Write-Log "bot ブランチへ切替し $BASE_BRANCH を取り込み"
        Invoke-Git checkout $BOT_BRANCH | Out-Null
        try {
            Invoke-Git merge --no-edit $BASE_BRANCH | Out-Null
        } catch {
            # コンフリクト等の merge 失敗時はツリーを mid-merge で残さず中断する
            # （残すと次回以降の未コミット判定で全実行が恒久ブロックされるため）
            & git merge --abort 2>$null | Out-Null
            throw "bot ブランチへの $BASE_BRANCH 取り込みに失敗（merge --abort 実施済み）: $($_.Exception.Message)"
        }
    } else {
        Write-Log "bot ブランチを $BASE_BRANCH から新規作成"
        Invoke-Git checkout -b $BOT_BRANCH $BASE_BRANCH | Out-Null
    }

    # 3. dl_llms.sh（公式 llms.txt 取り込み）
    if (-not $SkipDownload) {
        Write-Log "dl_llms.sh 実行"
        & bash "LLMs/scripts/dl_llms.sh" 2>&1 | Tee-Object -FilePath $LOG_FILE -Append | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "dl_llms.sh が失敗 (exit $LASTEXITCODE)" }
    } else {
        Write-Log "dl_llms.sh はスキップ (-SkipDownload)"
    }

    # 4. dl 差分を commit（取り込みと生成のコミットを分離）
    Invoke-Git add "LLMs/official-llms-txts" | Out-Null
    $dlStaged = & git diff --cached --quiet "LLMs/official-llms-txts"; $dlChanged = ($LASTEXITCODE -ne 0)
    if ($dlChanged) {
        Invoke-Git commit -m "chore(LLMs): 公式 llms.txt 定期取り込み (bot)" | Out-Null
        Write-Log "dl 差分を commit"
    } else {
        Write-Log "dl 差分なし"
    }

    $headCommit = (& git rev-parse HEAD).Trim()

    # 5. 対象サイトを生成
    $targets = if ($Site -eq "all") { $SITES } else { $SITES | Where-Object { $_.Slug -eq $Site } }
    foreach ($s in $targets) {
        # BASE_COMMIT は前回サマリのフッタ head_commit
        if (-not (Test-Path $s.Detail)) {
            Write-Log "[$($s.Slug)] latest-detail.md 不在。初版は手動 --from 指定が必要のためスキップ" "WARN"
            continue
        }
        $m = Select-String -Path $s.Detail -Pattern 'head_commit:\s*([0-9a-f]+)' | Select-Object -First 1
        if (-not $m) { Write-Log "[$($s.Slug)] head_commit 抽出失敗、スキップ" "WARN"; continue }
        $baseCommit = $m.Matches[0].Groups[1].Value

        $diff = & git diff $baseCommit $headCommit -- $s.Input
        if (-not $diff) {
            Write-Log "[$($s.Slug)] 原文差分なし、生成スキップ"
            continue
        }

        Write-Log "[$($s.Slug)] 差分あり。ヘッドレス生成を開始 ($baseCommit..$($headCommit.Substring(0,7)))"
        $env:DOC_SUMMARY_AUTOMATED = "1"
        $raw = & claude -p "/update-official-doc-summary --site $($s.Slug)" `
            --model $GEN_MODEL `
            --permission-mode acceptEdits `
            --allowedTools $ALLOWED_TOOLS `
            --output-format json 2>&1
        $cliExit = $LASTEXITCODE
        Remove-Item Env:\DOC_SUMMARY_AUTOMATED -ErrorAction SilentlyContinue

        # claude の終了コード + JSON の is_error を二重判定
        $isError = $true
        # $raw は 2>&1 で複数行（object[]）になり得るため join して 1 つの JSON として解釈する
        try { $isError = (($raw -join "`n") | ConvertFrom-Json).is_error } catch { $isError = $true }
        if ($cliExit -ne 0 -or $isError) {
            Write-Log "[$($s.Slug)] 生成失敗 (exit=$cliExit is_error=$isError)。当該サイトの生成物を破棄し push 抑止" "ERROR"
            Write-Log $raw "ERROR"
            # 失敗サイトの生成途中物をロールバック（他サイト・dl commit は保持）
            Invoke-Git checkout -- (Split-Path $s.Detail -Parent) | Out-Null
            $hadFailure = $true
        } else {
            Write-Log "[$($s.Slug)] 生成成功 (Phase 3 含む)"
        }
    }

    # 6. 生成物を commit
    $summaryDir = "LLMs/official-doc-update-summary"
    Invoke-Git add $summaryDir | Out-Null
    $genStaged = & git diff --cached --quiet $summaryDir; $genChanged = ($LASTEXITCODE -ne 0)
    if ($genChanged) {
        Invoke-Git commit -m "feat(LLMs): 公式ドキュ更新サマリ自動生成 (bot)" | Out-Null
        Write-Log "生成サマリを commit"
    } else {
        Write-Log "生成サマリの差分なし"
    }

    # 7. push（bot ブランチ限定・二重防御）
    if ($DryRun) {
        Write-Log "DryRun: push を抑止"
        $pushAborted = $true
    } elseif ($hadFailure) {
        Write-Log "生成失敗ありのため push を抑止（未確定生成が bot ローカルに残存）" "WARN"
        $pushAborted = $true
    } else {
        $cur = (& git rev-parse --abbrev-ref HEAD).Trim()
        if ($cur -ne $BOT_BRANCH) {
            throw "想定外ブランチ '$cur' での push を中止（期待: $BOT_BRANCH）"
        }
        Write-Log "bot ブランチへ push: origin $BOT_BRANCH (inline credential helper)"
        Invoke-BotPush $BOT_BRANCH | Out-Null
        Write-Log "push 完了"
    }
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    $hadFailure = $true
}
finally {
    if ($RestoreBranch -and $startBranch) {
        try { Invoke-Git checkout $startBranch | Out-Null; Write-Log "開始ブランチ $startBranch へ復帰" } catch { Write-Log "ブランチ復帰失敗: $($_.Exception.Message)" "WARN" }
    }
    $status = if ($hadFailure) { "FAILURE" } else { "SUCCESS" }
    Write-Log "=== run-doc-summary 終了: $status (pushAborted=$pushAborted) ==="
}

if ($hadFailure) { exit 1 } else { exit 0 }
