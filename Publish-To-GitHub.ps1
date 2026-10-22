<#
.SYNOPSIS
    Creates the GitHub repository "Better Start Menu Search" and pushes this project.
#>

$ErrorActionPreference = "Stop"

$gitPath = "C:\Program Files\Git\cmd"
$ghPath  = "C:\Program Files\GitHub CLI"
$env:Path = "$gitPath;$ghPath;$env:Path"

Set-Location $PSScriptRoot

Write-Host "`n> Checking local Git repository..." -ForegroundColor Cyan

# 1. Ensure git repo initialized and committed
if (-not (Test-Path ".git")) {
    git init
    git branch -M main
}

git add .
$status = git status --porcelain
if ($status) {
    git commit -m "Initial commit: Better Start Menu Search"
}
Write-Host "  [OK] Local repository ready." -ForegroundColor Green

# 2. Check GitHub CLI authentication
Write-Host "`n> Checking GitHub authentication..." -ForegroundColor Cyan
$authCheck = gh auth status 2>&1 | Out-String

if ($LASTEXITCODE -ne 0) {
    Write-Host "  [!] You need to authenticate with GitHub once." -ForegroundColor Yellow
    Write-Host "  A browser window will open to authorize GitHub CLI..." -ForegroundColor Yellow
    gh auth login --web -p https -h github.com
    if ($LASTEXITCODE -ne 0) {
        Write-Error "GitHub authentication failed or was cancelled."
        exit 1
    }
}
Write-Host "  [OK] Authenticated with GitHub." -ForegroundColor Green

# 3. Create remote repo and push
Write-Host "`n> Creating repository 'Better Start Menu Search' on GitHub and pushing..." -ForegroundColor Cyan

$remotes = git remote
if ($remotes -contains "origin") {
    Write-Host "  Remote 'origin' already exists. Pushing..." -ForegroundColor Yellow
    git push -u origin main
} else {
    gh repo create "Better Start Menu Search" --public --source=. --remote=origin --push
}

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host "  Successfully published to GitHub!" -ForegroundColor Green
    $repoUrl = gh repo view --json url -q .url
    Write-Host "  Repo URL: $repoUrl" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
} else {
    Write-Error "Failed to create or push repository."
}
