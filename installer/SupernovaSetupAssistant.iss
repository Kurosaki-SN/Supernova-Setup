; Supernova Setup Assistant installer.
; This installer only installs the assistant and helper scripts into a
; user-writable folder. Game-folder writes happen later from the assistant, where
; the user can see the step, confirm it, and approve UAC only when needed.
#define MyAppName "Supernova Setup Assistant"
#define MyAppVersion "Beta1.0.5"
#define MyAppPublisher "Supernova Community"
#define MyAppScript "SupernovaSetupAssistant.ps1"

; Core installer settings. PrivilegesRequired=lowest keeps setup itself from
; requesting admin rights just to install the assistant.
[Setup]
AppId={{B7B946D4-71F7-4778-A092-EE768C4F1A2B}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Supernova Setup Assistant
DefaultGroupName={#MyAppName}
DisableDirPage=yes
UsePreviousAppDir=no
AllowNoIcons=yes
OutputDir=dist
OutputBaseFilename=SupernovaInstallHelper
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
UninstallDisplayName={#MyAppName}

; Installer language resources.
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

; Only the desktop shortcut is optional. xiloader, DATs, patches, Windower, and
; Ashita setup are handled by the assistant after install.
[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

; Bundled scripts and Supernova-provided payload archives. No Square Enix client
; files, xiloader binary, Windower, or Ashita files are redistributed here.
[Files]
Source: "..\SupernovaSetupAssistant.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\SupernovaSetupAssistant.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\ApplySupernovaPatch.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\InstallXiloader.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\InstallMsvc2015Runtime.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\InstallAshitaBootloader.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\RemoveVulgarDictionary.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\RepairSupernovaClient.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\ConfigureWindower.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\ConfigureAshita.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\ExportSupernovaDiagnostics.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\assets\update-ffxi\*.png"; DestDir: "{app}\assets\update-ffxi"; Flags: ignoreversion
Source: "..\payload\*.zip"; DestDir: "{app}\payload"; Flags: ignoreversion skipifsourcedoesntexist

; Shortcuts launch PowerShell directly. The command wrapper is still included as
; a manual troubleshooting fallback, but normal users do not go through cmd.exe.
[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\{#MyAppScript}"""; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\{#MyAppScript}"""; WorkingDir: "{app}"; Tasks: desktopicon

; Offer to open the setup assistant on the final page.
[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\{#MyAppScript}"""; WorkingDir: "{app}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
