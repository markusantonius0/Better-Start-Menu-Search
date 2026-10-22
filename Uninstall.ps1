<#
.SYNOPSIS
    CmdPal Start Search — Uninstaller.

    Stops the running interceptor, removes the startup shortcut, and restores
    Windows default search behavior.

.DESCRIPTION
    This does NOT uninstall PowerToys or AutoHotkey — only the CmdPal Start
    Search integration. Run Setup.ps1 again at any time to reinstall.
#>

[CmdletBinding()]
param (
    [switch]$KeepStartup   # Remove process but keep the startup shortcut
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step  { param([string]$msg) Write-Host "`n> $msg" -ForegroundColor Cyan }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Skip  { param([string]$msg) Write-Host "  [--] $msg" -ForegroundColor DarkGray }

# ── 1. Stop running instances ─────────────────────────────────────────────────

Write-Step "Stopping CmdPal Start Search"

$processes = Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*PowerToys_StartSearch.ahk*" }

if ($processes) {
    foreach ($proc in $processes) {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        Write-OK "Stopped process (PID $($proc.ProcessId))"
    }
} else {
    Write-Skip "No running instances found"
}

# ── 2. Remove startup shortcut ───────────────────────────────────────────────

if (-not $KeepStartup) {
    Write-Step "Removing startup shortcut"

    $startupFolder = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Startup)

    # Check both old and new shortcut names
    $shortcutNames = @("CmdPalStartSearch.lnk", "PowerToys_StartSearch.lnk")
    $removed = $false

    foreach ($name in $shortcutNames) {
        $shortcutPath = Join-Path $startupFolder $name
        if (Test-Path $shortcutPath) {
            Remove-Item $shortcutPath -Force
            Write-OK "Removed: $shortcutPath"
            $removed = $true
        }
    }

    if (-not $removed) {
        Write-Skip "No startup shortcuts found"
    }
} else {
    Write-Skip "Keeping startup shortcut (-KeepStartup was specified)"
}

# ── Done ──────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "  Uninstall complete." -ForegroundColor Green
Write-Host "  Windows default Start Menu search is now restored." -ForegroundColor White
Write-Host "  Run Setup.ps1 again at any time to re-enable." -ForegroundColor White
Write-Host ""
