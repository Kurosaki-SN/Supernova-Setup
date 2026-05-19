#define MyAppName "Supernova FFXI Launcher"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "Supernova Community"

[Setup]
AppId={{B7B946D4-71F7-4778-A092-EE768C4F1A2B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Supernova FFXI Launcher
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=dist
OutputBaseFilename=SupernovaFFXILauncherSetup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\SupernovaLauncher.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\SupernovaLauncher.cmd"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\SupernovaLauncher.cmd"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\SupernovaLauncher.cmd"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\SupernovaLauncher.cmd"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
