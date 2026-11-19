<#
.SYNOPSIS
    Generates WinGet manifests for a published GitHub release.

.DESCRIPTION
    Downloads the release installer, computes its SHA-256, and writes the three
    manifest files (version, defaultLocale, installer) with the schema headers
    that winget-pkgs validation requires, to:

      winget\manifests\m\MarkusAntonius0\BetterStartMenuSearch\<version>\

    Validate locally with:   winget validate --manifest <that folder>
    Test-install locally:    winget install --manifest <that folder>
    Then copy the folder to the same path in your fork of microsoft/winget-pkgs
    and open a pull request.

.EXAMPLE
    .\winget\New-WingetManifests.ps1 -Version 1.0.1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version,

    # Hash this local installer instead of downloading the release asset
    # (used by CI to validate manifests before a release exists)
    [string]$InstallerPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

$id           = "MarkusAntonius0.BetterStartMenuSearch"
$manifestVer  = "1.12.0"
$repoUrl      = "https://github.com/markusantonius0/Better-Start-Menu-Search"
$installerUrl = "$repoUrl/releases/download/v$Version/BetterStartMenuSearch-Setup-$Version.exe"
# Inno Setup registers its uninstall entry as "<AppId>_is1" (AppId from installer\CmdPalStartSearch.iss)
$productCode  = "{6C37A8B2-AFB7-4A04-9B70-0AA245447B15}_is1"

if ($InstallerPath) {
    $sha = (Get-FileHash $InstallerPath -Algorithm SHA256).Hash
} else {
    Write-Host "Downloading $installerUrl"
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "BetterStartMenuSearch-Setup-$Version.exe"
    Invoke-WebRequest $installerUrl -OutFile $tmp -UseBasicParsing
    $sha = (Get-FileHash $tmp -Algorithm SHA256).Hash
    Remove-Item $tmp
}
Write-Host "SHA-256: $sha"

$outDir = Join-Path $PSScriptRoot "manifests\m\MarkusAntonius0\BetterStartMenuSearch\$Version"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$versionYaml = @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.version.$manifestVer.schema.json

PackageIdentifier: $id
PackageVersion: $Version
DefaultLocale: en-US
ManifestType: version
ManifestVersion: $manifestVer
"@

$localeYaml = @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.defaultLocale.$manifestVer.schema.json

PackageIdentifier: $id
PackageVersion: $Version
PackageLocale: en-US
Publisher: MarkusAntonius0
PublisherUrl: https://github.com/markusantonius0
PublisherSupportUrl: $repoUrl/issues
PackageName: Better Start Menu Search
PackageUrl: $repoUrl
License: MIT
LicenseUrl: $repoUrl/blob/main/LICENSE
ShortDescription: Redirect Windows Start Menu searches to PowerToys Command Palette.
Description: A lightweight AutoHotkey script that hands Start Menu typing to PowerToys Command Palette. Press Win, start typing, and Command Palette opens with your query.
Tags:
- autohotkey
- command-palette
- powertoys
- search
- start-menu
ReleaseNotesUrl: $repoUrl/releases/tag/v$Version
ManifestType: defaultLocale
ManifestVersion: $manifestVer
"@

$installerYaml = @"
# yaml-language-server: `$schema=https://aka.ms/winget-manifest.installer.$manifestVer.schema.json

PackageIdentifier: $id
PackageVersion: $Version
Platform:
- Windows.Desktop
MinimumOSVersion: 10.0.22000.0
InstallerType: inno
Scope: user
InstallModes:
- interactive
- silent
- silentWithProgress
UpgradeBehavior: install
Dependencies:
  PackageDependencies:
  - PackageIdentifier: Microsoft.PowerToys
  - PackageIdentifier: AutoHotkey.AutoHotkey
ProductCode: '$productCode'
Installers:
- Architecture: x64
  InstallerUrl: $installerUrl
  InstallerSha256: $sha
ManifestType: installer
ManifestVersion: $manifestVer
"@

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[IO.File]::WriteAllText((Join-Path $outDir "$id.yaml"),                  $versionYaml   + "`n", $utf8NoBom)
[IO.File]::WriteAllText((Join-Path $outDir "$id.locale.en-US.yaml"),     $localeYaml    + "`n", $utf8NoBom)
[IO.File]::WriteAllText((Join-Path $outDir "$id.installer.yaml"),        $installerYaml + "`n", $utf8NoBom)

Write-Host "Manifests written to $outDir"
Write-Host "Next: winget validate --manifest `"$outDir`""
