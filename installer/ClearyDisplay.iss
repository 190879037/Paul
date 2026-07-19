; ClearyDisplay 鈥?Inno Setup installer
#define MyAppName "ClearyDisplay"
#define MyAppVersion "1.6.0"
#define MyAppPublisher "ClearyDisplay"
#define MyAppURL "https://github.com/stormertoolscn/ClearyDisplay"
#define MyAppExeName "ClearyDisplay.exe"

[Setup]
AppId={{A8C3E4F1-9B2D-4F70-8E1A-C1EA4D150001}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\ClearyDisplay
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=ClearyDisplay-Setup-{#MyAppVersion}
SetupIconFile=..\assets\ClearyDisplay.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible
VersionInfoVersion=1.6.0.0
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription=Display and font tuner (ZH/EN)
VersionInfoProductName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startup"; Description: "Start / apply profile at Windows logon (寮€鏈哄簲鐢ㄦ樉绀洪厤缃?"; GroupDescription: "Startup / 寮€鏈?; Flags: unchecked

[Files]
Source: "..\dist\ClearyDisplay.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\ClearyDisplay.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\GammaTuner.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\ApplyProfile.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\ApplyProfile.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\WatchPower.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\Build-Exe.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\README.md"; DestDir: "{app}"; Flags: ignoreversion isreadme

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\ClearyDisplay.ico"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\ClearyDisplay.ico"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "ClearyDisplayApply"; ValueData: """{app}\ApplyProfile.cmd"""; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
