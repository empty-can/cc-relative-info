# start_claude_code.ps1（Windows 版・最小例）
# 使い方: .\start_claude_code.ps1 [-Branch <ブランチ>] [claude へ渡す引数...]

# -Branch だけを受け取り、残りの引数はそのまま claude へ渡す
# （param で受けると、-c・-p などが PowerShell の引数として解釈されるため）
$Branch = "main"
$ClaudeArgs = @()
for ($i = 0; $i -lt $args.Count; $i++) {
    if ($args[$i] -eq "-Branch" -and $i + 1 -lt $args.Count) {
        $Branch = $args[$i + 1]
        $i++
    } else {
        $ClaudeArgs += $args[$i]
    }
}

# 作業リポジトリのルートを基準にする（§5-7「起動はルートから」）
Set-Location $PSScriptRoot

$ClaudeDir = Join-Path $PSScriptRoot ".claude"
$SharedUrl = "<共有リポの URL>"   # 例: https://github.com/<org>/shared-claude.git

# 1. 入れ子クローンの存在確認（無ければ clone）
if (-not (Test-Path (Join-Path $ClaudeDir ".git"))) {
    if (Get-ChildItem -Force $ClaudeDir -ErrorAction SilentlyContinue) {
        [Console]::Error.WriteLine(".claude/ に中身がありますが、共有リポのクローンではありません。中断します。")
        [Console]::Error.WriteLine("個人のファイル（settings.local.json など）を退避し、.claude/ を別の名前（例: .claude.old）へ移してから、もう一度起動してください。")
        exit 1
    }
    git clone --branch $Branch $SharedUrl $ClaudeDir
    if ($LASTEXITCODE -ne 0) {
        [Console]::Error.WriteLine("clone に失敗しました。中断します。")
        exit 1
    }
}

# 2. ローカル変更の検査（switch より前に）
$dirty = git -C $ClaudeDir status --porcelain
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine(".claude/ を git リポジトリとして読めません。中断します。")
    exit 1
}
if ($dirty) {
    [Console]::Error.WriteLine(".claude/ にローカル変更があります。更新を中止しました:`n" + ($dirty -join "`n"))
    [Console]::Error.WriteLine("git -C .claude status で中身を確かめてください。覚えのないものは消さずに、メンテナーへ相談してください。")
    exit 1
}

# 3-a. fetch（失敗しても続行 ＝ オフラインでも起動できるようにする）
git -C $ClaudeDir fetch --all --prune
if ($LASTEXITCODE -ne 0) {
    Write-Warning "fetch に失敗しました。手元にある内容で起動します（最新でない可能性があります）。"
}

# 3-a'. 指定のブランチが origin にあるか（大文字小文字も区別して）と、手元の旧い名前と衝突しないかを確かめる
$remote = @(git -C $ClaudeDir for-each-ref --format='%(refname:strip=3)' refs/remotes/origin/ | Where-Object { $_ -ne "HEAD" })
if ($remote -cnotcontains $Branch) {
    [Console]::Error.WriteLine("ブランチ '$Branch' は共有リポにありません（大文字小文字も区別します）。中断します。")
    [Console]::Error.WriteLine("共有リポのブランチ: " + ($remote -join ", "))
    exit 1
}
$parts = $Branch -split "/"
for ($k = 1; $k -lt $parts.Count; $k++) {
    $prefix = $parts[0..($k - 1)] -join "/"
    git -C $ClaudeDir show-ref --verify --quiet "refs/heads/$prefix"
    if ($LASTEXITCODE -eq 0) {
        [Console]::Error.WriteLine("手元に旧いブランチ '$prefix' が残っているため、'$Branch' に切り替えられません。中断します。")
        [Console]::Error.WriteLine("個人のファイル（settings.local.json など）を退避し、.claude/ を消して（または .claude.old へ移して）から、もう一度起動してください。")
        exit 1
    }
}

# 3-b. switch（失敗したら中断。ここで進むとブランチが静かに壊れる）
$before = (git -C $ClaudeDir rev-parse --abbrev-ref HEAD)
git -C $ClaudeDir switch $Branch
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("ブランチ '$Branch' への切替に失敗しました。中断します。")
    exit 1
}
if ($before -ne $Branch) {
    Write-Host ".claude/ のブランチを切り替えました: $before → $Branch"
}

# 3-c. 現在ブランチが指定と一致することを確認してから reset --hard
$current = (git -C $ClaudeDir rev-parse --abbrev-ref HEAD)
if ($LASTEXITCODE -ne 0 -or $current.Trim() -ne $Branch) {
    [Console]::Error.WriteLine("現在のブランチ '$current' が指定 '$Branch' と一致しません。reset を中止します。")
    exit 1
}

git -C $ClaudeDir reset --hard "origin/$Branch"
if ($LASTEXITCODE -ne 0) {
    [Console]::Error.WriteLine("reset --hard に失敗しました。中断します（origin/$Branch が無いときは、リモートでブランチが消された可能性があります）。")
    exit 1
}

# 4. 起動（配布のための起動フラグは渡さない。メンバーが付けた引数だけを渡す）
claude @ClaudeArgs
