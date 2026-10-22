#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#define MyAppName "CmdPal Start Search"
#define MyAppPublisher "MarkusAntonius0"
#define MyAppId "{{6C37A8B2-AFB7-4A04-9B70-0AA245447B15}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\CmdPalStartSearch
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=BetterStartMenuSearch-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
LicenseFile=..\LICENSE
UninstallDisplayName={#MyAppName}

[Files]
Source: "..\PowerToys_StartSearch.ahk"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Setup.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Setup.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Uninstall.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\Uninstall.bat"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\Configure CmdPal Start Search"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Setup.ps1"""; WorkingDir: "{app}"
Name: "{group}\Uninstall CmdPal Start Search"; Filename: "{uninstallexe}"

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Setup.ps1"""; WorkingDir: "{app}"; StatusMsg: "Configuring CmdPal Start Search..."; Flags: runhidden waituntilterminated

[UninstallRun]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\Uninstall.ps1"""; WorkingDir: "{app}"; Flags: runhidden waituntilterminated; RunOnceId: "CmdPalStartSearchUninstall"
