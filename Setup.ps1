<#
.SYNOPSIS
    CmdPal Start Search - One-click installer.

    Checks for (and installs) prerequisites, enables Command Palette in
    PowerToys, registers the background interceptor at login, and launches it.

.DESCRIPTION
    Prerequisites handled automatically via winget:
      * Microsoft PowerToys  (Microsoft.PowerToys)
      * AutoHotkey v2        (AutoHotkey.AutoHotkey)

    Safe to re-run - idempotent on every step.

.NOTES
    Run from an *elevated* (Admin) PowerShell if winget installs are needed.
    After the first run, no elevation is required.
#>

[CmdletBinding()]
param (
    [switch]$SkipLaunch   # Install everything but don't start the interceptor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# -- Helpers -----------------------------------------------------------------

function Write-Step  { param([string]$msg) Write-Host "`n> $msg" -ForegroundColor Cyan }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Skip  { param([string]$msg) Write-Host "  [--] $msg (already satisfied)" -ForegroundColor DarkGray }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg" -ForegroundColor Yellow }

function Test-CommandExists {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

# -- 1. Verify winget -------------------------------------------------------

Write-Step "Checking for winget (Windows Package Manager)"

if (-not (Test-CommandExists winget)) {
    Write-Error @"
winget is not available on this system.
Please install 'App Installer' from the Microsoft Store, or update Windows to
a recent build of Windows 10/11 that includes winget, then re-run this script.
"@
    exit 1
}
Write-OK "winget found"

# -- 2. PowerToys -----------------------------------------------------------

Write-Step "Checking for Microsoft PowerToys"

$ptProcess = Get-Process PowerToys -ErrorAction SilentlyContinue
$ptInstalled = $null -ne $ptProcess

if (-not $ptInstalled) {
    $wingetList = winget list Microsoft.PowerToys 2>&1 | Out-String
    if ($wingetList -match "Microsoft.PowerToys") {
        $ptInstalled = $true
    }
}

if (-not $ptInstalled) {
    Write-Host "  Installing PowerToys via winget..." -ForegroundColor Yellow
    winget install --id Microsoft.PowerToys --accept-source-agreements --accept-package-agreements --silent
    if ($LASTEXITCODE -ne 0) {
        Write-Error "PowerToys installation failed (exit code $LASTEXITCODE). Try running this script as Administrator."
        exit 1
    }
    Write-OK "PowerToys installed"
    Write-Warn "PowerToys needs to be launched once before Command Palette is available."

    $ptExe = Join-Path $env:LOCALAPPDATA "PowerToys\PowerToys.exe"
    if (Test-Path $ptExe) {
        Start-Process $ptExe
        Write-OK "PowerToys launched - please wait a moment and re-run Setup.ps1"
    }
    exit 0
} else {
    Write-OK "PowerToys is installed"
}

# -- 3. Enable Command Palette in PowerToys ---------------------------------

Write-Step "Ensuring Command Palette (CmdPal) is enabled in PowerToys"

$ptSettingsPath = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\settings.json"

if (Test-Path $ptSettingsPath) {
    $ptSettings = Get-Content $ptSettingsPath -Raw | ConvertFrom-Json

    $changed = $false

    if ($ptSettings.enabled.PSObject.Properties["CmdPal"]) {
        if (-not $ptSettings.enabled.CmdPal) {
            $ptSettings.enabled.CmdPal = $true
            $changed = $true
            Write-OK "Enabled Command Palette"
        } else {
            Write-Skip "Command Palette already enabled"
        }
    } else {
        $ptSettings.enabled | Add-Member -NotePropertyName "CmdPal" -NotePropertyValue $true
        $changed = $true
        Write-OK "Added and enabled Command Palette"
    }

    if ($ptSettings.enabled.PSObject.Properties["PowerToys Run"] -and $ptSettings.enabled."PowerToys Run") {
        $ptSettings.enabled."PowerToys Run" = $false
        $changed = $true
        Write-Warn "Disabled legacy PowerToys Run to avoid hotkey conflicts"
    }

    if ($changed) {
        $ptSettings | ConvertTo-Json -Depth 10 | Set-Content $ptSettingsPath -Encoding UTF8
        Write-OK "PowerToys settings updated"
    }
} else {
    Write-Warn "PowerToys settings file not found - launch PowerToys once, then re-run this script."
}

# -- 4. AutoHotkey v2 -------------------------------------------------------

Write-Step "Checking for AutoHotkey v2"

function Find-AHKv2 {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\AutoHotkey\v2\AutoHotkey64.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\AutoHotkey\v2\AutoHotkey32.exe"),
        (Join-Path $env:ProgramFiles "AutoHotkey\v2\AutoHotkey64.exe"),
        (Join-Path $env:ProgramFiles "AutoHotkey\v2\AutoHotkey32.exe")
    )
    if (${env:ProgramFiles(x86)}) {
        $candidates += (Join-Path ${env:ProgramFiles(x86)} "AutoHotkey\v2\AutoHotkey64.exe")
        $candidates += (Join-Path ${env:ProgramFiles(x86)} "AutoHotkey\v2\AutoHotkey32.exe")
    }
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    $inPath = Get-Command AutoHotkey64.exe -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    $inPath = Get-Command AutoHotkey32.exe -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }
    return $null
}

$ahkExe = Find-AHKv2

if (-not $ahkExe) {
    Write-Host "  Installing AutoHotkey v2 via winget..." -ForegroundColor Yellow
    winget install --id AutoHotkey.AutoHotkey --accept-source-agreements --accept-package-agreements --silent
    if ($LASTEXITCODE -ne 0) {
        Write-Error "AutoHotkey installation failed (exit code $LASTEXITCODE). Try running this script as Administrator."
        exit 1
    }
    $ahkExe = Find-AHKv2
    if (-not $ahkExe) {
        Write-Error "AutoHotkey v2 was installed but could not be found. Please check the installation and re-run."
        exit 1
    }
    Write-OK "AutoHotkey v2 installed at: $ahkExe"
} else {
    Write-OK "AutoHotkey v2 found at: $ahkExe"
}

# -- 5. Validate the AHK script ---------------------------------------------

Write-Step "Validating interceptor script"

$scriptDir  = $PSScriptRoot
$ahkScript  = Join-Path $scriptDir "PowerToys_StartSearch.ahk"

if (-not (Test-Path $ahkScript)) {
    Write-Error "PowerToys_StartSearch.ahk not found in $scriptDir. Re-clone the repository."
    exit 1
}

$validateProc = Start-Process -FilePath $ahkExe -ArgumentList "/validate `"$ahkScript`"" -PassThru -Wait -NoNewWindow
if ($validateProc.ExitCode -ne 0) {
    Write-Error "AHK script syntax validation failed."
    exit 1
}
Write-OK "PowerToys_StartSearch.ahk syntax OK"

# -- 6. Read the CmdPal hotkey and sync the AHK script ----------------------

Write-Step "Detecting Command Palette hotkey"

$cmdPalSettingsPath = $null
$packagesDir = Join-Path $env:LOCALAPPDATA "Packages"
if (Test-Path $packagesDir) {
    $cmdPalPkg = Get-ChildItem $packagesDir -Directory |
        Where-Object { $_.Name -like "Microsoft.CommandPalette*" } |
        Select-Object -First 1
    if ($cmdPalPkg) {
        $cmdPalSettingsPath = Join-Path $cmdPalPkg.FullName "LocalState\settings.json"
    }
}

$hotkeySendStr = "!#{Space}"   # default: Win + Alt + Space

if ($cmdPalSettingsPath -and (Test-Path $cmdPalSettingsPath)) {
    $cmdPalSettings = Get-Content $cmdPalSettingsPath -Raw | ConvertFrom-Json
    $hk = $cmdPalSettings.Hotkey

    $parts = ""
    if ($hk.win)   { $parts += "#" }
    if ($hk.alt)   { $parts += "!" }
    if ($hk.ctrl)  { $parts += "^" }
    if ($hk.shift) { $parts += "+" }

    $vkMap = @{}
    $vkMap[32] = "Space"; $vkMap[13] = "Enter"; $vkMap[9] = "Tab"; $vkMap[27] = "Escape"
    for ($i = 65; $i -le 90; $i++) { $vkMap[$i] = [string][char]$i }
    for ($i = 48; $i -le 57; $i++) { $vkMap[$i] = [string][char]$i }

    if ($vkMap.ContainsKey([int]$hk.code)) {
        $keyName = $vkMap[[int]$hk.code]
        $hotkeySendStr = "$parts{$keyName}"
    }

    Write-OK "CmdPal hotkey detected: $hotkeySendStr"
} else {
    Write-Warn "CmdPal settings not found - using default hotkey: $hotkeySendStr"
}

# Patch the AHK script to use the detected hotkey
$ahkContent = Get-Content $ahkScript -Raw
$newLine = "    SendInput `"$hotkeySendStr`""
$ahkContent = $ahkContent -replace '    SendInput ".*" ; CmdPal hotkey -- patched by Setup\.ps1', "$newLine ; CmdPal hotkey -- patched by Setup.ps1"
Set-Content $ahkScript -Value $ahkContent -NoNewline -Encoding UTF8
Write-OK "AHK script synced with CmdPal hotkey"

# -- 7. Register startup shortcut -------------------------------------------

Write-Step "Registering startup shortcut"

$startupFolder = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::Startup)
$shortcutPath  = Join-Path $startupFolder "CmdPalStartSearch.lnk"

$wshShell = New-Object -ComObject WScript.Shell
$shortcut = $wshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath       = $ahkExe
$shortcut.Arguments        = "`"$ahkScript`""
$shortcut.WorkingDirectory = $scriptDir
$shortcut.Description      = "CmdPal Start Search - redirects Start Menu typing to PowerToys Command Palette"
$shortcut.Save()

Write-OK "Startup shortcut created: $shortcutPath"

# Remove old shortcut name if present
$oldShortcut = Join-Path $startupFolder "PowerToys_StartSearch.lnk"
if (Test-Path $oldShortcut) {
    Remove-Item $oldShortcut -Force
    Write-OK "Removed legacy shortcut: $oldShortcut"
}

# -- 8. Launch ---------------------------------------------------------------

if (-not $SkipLaunch) {
    Write-Step "Launching CmdPal Start Search"

    # Stop any existing instances
    $existing = Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*PowerToys_StartSearch.ahk*" }
    foreach ($proc in $existing) {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }

    Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine = "`"$ahkExe`" `"$ahkScript`""
    } | Out-Null

    Start-Sleep -Milliseconds 500
    $running = Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*PowerToys_StartSearch.ahk*" }

    if ($running) {
        Write-OK "Running! (PID $($running.ProcessId))"
    } else {
        Write-Warn "Process started but may have exited. Check the system tray."
    }
}

# -- Done --------------------------------------------------------------------

Write-Host ""
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host "  Press Win -> start typing -> Command Palette takes over." -ForegroundColor White
Write-Host "  Look for the green H icon in your system tray." -ForegroundColor White
Write-Host ""
