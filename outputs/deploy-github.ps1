$ErrorActionPreference = 'Continue'
$env:Path += ';C:\Users\imcha\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\git\cmd;C:\Program Files\GitHub CLI'
$taskRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $taskRoot
function Run-Git {
    & git -c "safe.directory=$taskRoot" @args
    if ($LASTEXITCODE -ne 0) { throw 'Git command failed.' }
}
$taskAccountRaw = & gh api user
if ($LASTEXITCODE -ne 0) { throw 'GitHub login is unavailable. Run gh auth status in this terminal.' }
$taskAccount = ($taskAccountRaw -join "`n") | ConvertFrom-Json
$taskOwner = $taskAccount.login
$taskName = Split-Path $taskRoot -Leaf
$taskRepo = "$taskOwner/$taskName"
if (!(Test-Path -LiteralPath '.git')) { Run-Git init -b main }
Run-Git branch -M main
$taskGitName = & git -c "safe.directory=$taskRoot" config user.name
if (!$taskGitName) { Run-Git config user.name $taskOwner }
$taskGitEmail = & git -c "safe.directory=$taskRoot" config user.email
if (!$taskGitEmail) {
    $taskEmail = $taskAccount.email
    if (!$taskEmail) { $taskEmail = "$($taskAccount.id)+$taskOwner@users.noreply.github.com" }
    Run-Git config user.email $taskEmail
}
Run-Git add .gitignore index.html outputs
& git -c "safe.directory=$taskRoot" show-ref --verify --quiet refs/heads/main
if ($LASTEXITCODE -ne 0) { Run-Git commit -m '첫 배포' }
else {
    & git -c "safe.directory=$taskRoot" diff --cached --quiet
    if ($LASTEXITCODE -eq 1) { Run-Git commit -m '전단지 업데이트' }
}
& gh repo view $taskRepo --json name 2>$null
if ($LASTEXITCODE -ne 0) {
    & gh repo create $taskRepo --public
    if ($LASTEXITCODE -ne 0) { throw 'Repository creation failed.' }
}
$taskVisibility = & gh repo view $taskRepo --json visibility --jq .visibility
if ($taskVisibility -ne 'PUBLIC') { throw 'Existing repository is not public. Stopped without changing its visibility.' }
$taskRemote = & git -c "safe.directory=$taskRoot" remote get-url origin 2>$null
$taskExpected = "https://github.com/$taskRepo.git"
if (!$taskRemote) { Run-Git remote add origin $taskExpected }
elseif ($taskRemote -ne $taskExpected) { throw "Existing origin differs: $taskRemote" }
& gh auth setup-git
if ($LASTEXITCODE -ne 0) { throw 'Git authentication setup failed.' }
Run-Git push -u origin main
& gh api "repos/$taskRepo/pages" -X POST -f 'source[branch]=main' -f 'source[path]=/'
if ($LASTEXITCODE -ne 0) {
    $taskJson = Join-Path $env:TEMP ('pages-source-' + [guid]::NewGuid().ToString() + '.json')
    [IO.File]::WriteAllText($taskJson, '{"source":{"branch":"main","path":"/"}}', [Text.UTF8Encoding]::new($false))
    & gh api "repos/$taskRepo/pages" -X POST --input $taskJson
    if ($LASTEXITCODE -ne 0) {
        & gh api "repos/$taskRepo/pages" -X PUT --input $taskJson
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Open https://github.com/$taskRepo/settings/pages and choose Deploy from a branch, main, / (root), then Save."
            throw 'Pages setup failed.'
        }
    }
}
$taskUrl = "https://$taskOwner.github.io/$taskName/"
$taskDeadline = (Get-Date).AddMinutes(5)
do {
    $taskStatus = & gh api "repos/$taskRepo/pages" --jq .status
    Write-Host "Pages status: $taskStatus"
    if ($taskStatus -eq 'built') {
        Write-Host "Site ready: $taskUrl" -ForegroundColor Green
        Start-Process $taskUrl
        exit 0
    }
    if ((Get-Date) -ge $taskDeadline) { break }
    Start-Sleep -Seconds 30
} while ($true)
Write-Host "Deployment exceeded 5 minutes. Check https://github.com/$taskRepo/actions"
Write-Host "Site URL (not yet confirmed ready): $taskUrl"
