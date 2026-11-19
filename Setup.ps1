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
    Keep this file ASCII-only (Windows PowerShell 5.1 reads BOM-less files as ANSI).
#>

[CmdletBinding()]
param (
    [switch]$SkipLaunch   # Install everything but don't start the interceptor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# Keep a log: when run by the installer (or WinGet) this script is hidden.
$logPath = Join-Path $env:TEMP "CmdPalStartSearch-Setup.log"
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }

# -- Helpers -----------------------------------------------------------------

function Write-Step  { param([string]$msg) Write-Host "`n> $msg" -ForegroundColor Cyan }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Skip  { param([string]$msg) Write-Host "  [--] $msg (already satisfied)" -ForegroundColor DarkGray }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg" -ForegroundColor Yellow }

function Test-CommandExists {
    param([string]$Name)
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

# Run a native command without letting stderr output become a terminating
# NativeCommandError (Windows PowerShell 5.1 + $ErrorActionPreference=Stop).
function Invoke-Native {
    param([scriptblock]$Command)
    $oldPref = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try { & $Command } finally { $ErrorActionPreference = $oldPref }
}

# Safely read a property under StrictMode (returns $null if missing)
function Get-Prop {
    param($Object, [string]$Name)
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}

function Write-Utf8NoBom {
    param([string]$Path, [string]$Text)
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding $false))
}

function Find-PowerToysExe {
    $running = Get-Process PowerToys -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($running) {
        try { if ($running.Path) { return $running.Path } } catch { }
    }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "PowerToys\PowerToys.exe"),
        (Join-Path $env:ProgramFiles "PowerToys\PowerToys.exe"),
        $(if ($env:ProgramW6432) { Join-Path $env:ProgramW6432 "PowerToys\PowerToys.exe" })
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    return $null
}

# -- 1. Verify winget -------------------------------------------------------

Write-Step "Checking for winget (Windows Package Manager)"

$hasWinget = Test-CommandExists winget
if ($hasWinget) {
    Write-OK "winget found"
} else {
    Write-Warn "winget not found - prerequisites cannot be installed automatically."
}

# -- 2. PowerToys -----------------------------------------------------------

Write-Step "Checking for Microsoft PowerToys"

$ptExe = Find-PowerToysExe
$ptInstalled = $null -ne $ptExe

if (-not $ptInstalled -and $hasWinget) {
    $wingetList = Invoke-Native { winget list --id Microsoft.PowerToys --exact --accept-source-agreements 2>&1 } | Out-String
    if ($wingetList -match "Microsoft\.PowerToys") {
        $ptInstalled = $true
    }
}

if (-not $ptInstalled) {
    if (-not $hasWinget) {
        Write-Error @"
PowerToys is not installed and winget is not available.
Install PowerToys from https://aka.ms/installpowertoys (or install 'App Installer'
from the Microsoft Store to get winget), then re-run this script.
"@
    }
    Write-Host "  Installing PowerToys via winget..." -ForegroundColor Yellow
    Invoke-Native { winget install --id Microsoft.PowerToys --exact --accept-source-agreements --accept-package-agreements --silent }
    if ($LASTEXITCODE -ne 0) {
        Write-Error "PowerToys installation failed (exit code $LASTEXITCODE). Try running this script as Administrator."
    }
    Write-OK "PowerToys installed"
    $ptExe = Find-PowerToysExe
} else {
    Write-OK "PowerToys is installed"
}

# PowerToys must be running for Command Palette to be available, and it
# creates its settings file on first launch.
if (-not (Get-Process PowerToys -ErrorAction SilentlyContinue)) {
    if ($ptExe) {
        Write-Host "  Starting PowerToys..." -ForegroundColor Yellow
        Start-Process $ptExe
        Write-OK "PowerToys started"
    } else {
        Write-Warn "PowerToys is installed but PowerToys.exe was not found. Please start PowerToys manually."
    }
}

# -- 3. Enable Command Palette in PowerToys ---------------------------------

Write-Step "Ensuring Command Palette (CmdPal) is enabled in PowerToys"

$ptSettingsPath = Join-Path $env:LOCALAPPDATA "Microsoft\PowerToys\settings.json"

# On a fresh install PowerToys writes its settings shortly after first launch
for ($i = 0; $i -lt 30 -and -not (Test-Path $ptSettingsPath); $i++) {
    Start-Sleep -Seconds 1
}

if (Test-Path $ptSettingsPath) {
    $ptSettings = Get-Content $ptSettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json

    if (-not (Get-Prop $ptSettings "enabled")) {
        $ptSettings | Add-Member -NotePropertyName "enabled" -NotePropertyValue ([pscustomobject]@{})
    }
    $enabled = $ptSettings.enabled
    $changed = $false

    if ($enabled.PSObject.Properties["CmdPal"]) {
        if (-not $enabled.CmdPal) {
            $enabled.CmdPal = $true
            $changed = $true
            Write-OK "Enabled Command Palette"
        } else {
            Write-Skip "Command Palette already enabled"
        }
    } else {
        $enabled | Add-Member -NotePropertyName "CmdPal" -NotePropertyValue $true
        $changed = $true
        Write-OK "Added and enabled Command Palette"
    }

    if ($enabled.PSObject.Properties["PowerToys Run"] -and $enabled."PowerToys Run") {
        $enabled."PowerToys Run" = $false
        $changed = $true
        Write-Warn "Disabled legacy PowerToys Run to avoid hotkey conflicts"
    }

    if ($changed) {
        # PowerToys only reads settings.json at startup (and may overwrite it
        # while running), so stop it, write the change, then start it again.
        $ptProc = Get-Process PowerToys -ErrorAction SilentlyContinue
        if ($ptProc) {
            $ptProc | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }

        Write-Utf8NoBom -Path $ptSettingsPath -Text ($ptSettings | ConvertTo-Json -Depth 20)
        Write-OK "PowerToys settings updated"

        if ($ptExe) {
            Start-Process $ptExe
            Write-OK "PowerToys restarted to apply settings"
            Start-Sleep -Seconds 3
        } else {
            Write-Warn "Please restart PowerToys to apply the new settings."
        }
    }
} else {
    Write-Warn "PowerToys settings file not found - make sure Command Palette is enabled in PowerToys Settings."
}

# -- 4. AutoHotkey v2 -------------------------------------------------------

Write-Step "Checking for AutoHotkey v2"

function Find-AHKv2 {
    $roots = New-Object System.Collections.Generic.List[string]

    # Install folder recorded by the AutoHotkey installer. Read the 64-bit
    # registry view explicitly: this script may run in 32-bit PowerShell
    # (e.g. launched by a 32-bit installer), where the default view differs.
    foreach ($hive in @([Microsoft.Win32.RegistryHive]::CurrentUser, [Microsoft.Win32.RegistryHive]::LocalMachine)) {
        foreach ($view in @([Microsoft.Win32.RegistryView]::Registry64, [Microsoft.Win32.RegistryView]::Registry32)) {
            try {
                $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, $view)
                $key  = $base.OpenSubKey("SOFTWARE\AutoHotkey")
                if ($key) {
                    $dir = $key.GetValue("InstallDir")
                    if ($dir) { $roots.Add((Join-Path $dir "v2")); $roots.Add([string]$dir) }
                    $key.Close()
                }
                $base.Close()
            } catch { }
        }
    }

    # Default install locations. In 32-bit PowerShell $env:ProgramFiles is
    # "Program Files (x86)", so also check ProgramW6432 (the real 64-bit one).
    $roots.Add((Join-Path $env:LOCALAPPDATA "Programs\AutoHotkey\v2"))
    foreach ($pf in @($env:ProgramW6432, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($pf) { $roots.Add((Join-Path $pf "AutoHotkey\v2")) }
    }

    $exeNames = if ([Environment]::Is64BitOperatingSystem) {
        @("AutoHotkey64.exe", "AutoHotkey32.exe")
    } else {
        @("AutoHotkey32.exe")
    }
    foreach ($r in $roots) {
        foreach ($n in $exeNames) {
            $c = Join-Path $r $n
            if (Test-Path $c) { return $c }
        }
    }
    foreach ($n in $exeNames) {
        $inPath = Get-Command $n -ErrorAction SilentlyContinue
        if ($inPath) { return $inPath.Source }
    }
    return $null
}

$ahkExe = Find-AHKv2

if (-not $ahkExe) {
    if (-not $hasWinget) {
        Write-Error "AutoHotkey v2 is not installed and winget is not available. Install it from https://www.autohotkey.com/ and re-run."
    }
    Write-Host "  Installing AutoHotkey v2 via winget..." -ForegroundColor Yellow
    Invoke-Native { winget install --id AutoHotkey.AutoHotkey --exact --accept-source-agreements --accept-package-agreements --silent }
    if ($LASTEXITCODE -ne 0) {
        Write-Error "AutoHotkey installation failed (exit code $LASTEXITCODE). Try running this script as Administrator."
    }
    $ahkExe = Find-AHKv2
    if (-not $ahkExe) {
        Write-Error "AutoHotkey v2 was installed but could not be found. Please check the installation and re-run."
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
}

# /ErrorStdOut prints errors to the console instead of a message box, which
# would otherwise block a silent (WinGet / installer) run forever.
$validateProc = Start-Process -FilePath $ahkExe -ArgumentList "/ErrorStdOut /Validate `"$ahkScript`"" -PassThru -Wait -NoNewWindow
if ($validateProc.ExitCode -ne 0) {
    Write-Error "AHK script validation failed (exit code $($validateProc.ExitCode))."
}
Write-OK "PowerToys_StartSearch.ahk syntax OK"

# -- 6. Read the CmdPal hotkey and save it for the AHK script ---------------

Write-Step "Detecting Command Palette hotkey"

$hotkeySendStr = "!#{Space}"   # default: Win + Alt + Space

$hk = $null
$packagesDir = Join-Path $env:LOCALAPPDATA "Packages"
if (Test-Path $packagesDir) {
    $cmdPalSettingsFiles = Get-ChildItem $packagesDir -Directory -Filter "Microsoft.CommandPalette*" -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName "LocalState\settings.json" } |
        Where-Object { Test-Path $_ }

    foreach ($f in @($cmdPalSettingsFiles)) {
        try {
            $hk = Get-Prop (Get-Content $f -Raw -Encoding UTF8 | ConvertFrom-Json) "Hotkey"
            if ($hk) { break }
        } catch {
            Write-Warn "Could not read $f : $($_.Exception.Message)"
        }
    }
}

$code = Get-Prop $hk "code"
if ($code) {
    $code = [int]$code
    $parts = ""
    if (Get-Prop $hk "win")   { $parts += "#" }
    if (Get-Prop $hk "alt")   { $parts += "!" }
    if (Get-Prop $hk "ctrl")  { $parts += "^" }
    if (Get-Prop $hk "shift") { $parts += "+" }

    if     ($code -eq 32)                     { $keyName = "Space" }
    elseif ($code -ge 65 -and $code -le 90)   { $keyName = [string][char]$code }
    elseif ($code -ge 48 -and $code -le 57)   { $keyName = [string][char]$code }
    elseif ($code -ge 112 -and $code -le 135) { $keyName = "F$($code - 111)" }
    else                                      { $keyName = "vk{0:X2}" -f $code }

    $hotkeySendStr = "$parts{$keyName}"
    Write-OK "CmdPal hotkey detected: $hotkeySendStr"
} else {
    Write-Warn "CmdPal hotkey not found in its settings - using default Win+Alt+Space ($hotkeySendStr)"
}

$iniPath = Join-Path $scriptDir "settings.ini"
Write-Utf8NoBom -Path $iniPath -Text "[CmdPal]`r`nHotkey=$hotkeySendStr`r`n"
Write-OK "Saved hotkey to $iniPath"

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

    # #SingleInstance Force in the script replaces any running copy, so a
    # plain launch also picks up the new settings.
    Start-Process -FilePath $ahkExe -ArgumentList "`"$ahkScript`"" -WorkingDirectory $scriptDir

    Start-Sleep -Seconds 1
    $running = @(Get-CimInstance Win32_Process -Filter "Name LIKE 'AutoHotkey%.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like "*PowerToys_StartSearch.ahk*" })

    if ($running.Count -gt 0) {
        Write-OK "Running! (PID $($running[0].ProcessId))"
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

try { Stop-Transcript | Out-Null } catch { }
