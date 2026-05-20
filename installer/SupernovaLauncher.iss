; Shared app metadata used throughout the installer script. Updating the version
; here changes what Windows and the installer wizard display.
#define MyAppName "Supernova FFXI Launcher"
#define MyAppVersion "0.3.2"
#define MyAppPublisher "Supernova Community"

; Core installer settings: install location, output filename, compression, UI
; style, and privilege mode. The launcher itself installs per-machine by default
; but does not require admin unless the optional patch step needs it.
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

; Installer language resources.
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

; Optional choices shown during setup. The DAT/patch task is unchecked by default
; so players must explicitly choose to download and write files into their FFXI folder.
[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "installxiloader"; Description: "Download and install Supernova-compatible xiloader v2.0.1"; GroupDescription: "Supernova setup:"; Flags: unchecked
Name: "applypatch"; Description: "Download and install Supernova custom DATs and patch"; GroupDescription: "Supernova setup:"; Flags: unchecked

; Files bundled into the installed launcher folder. These are launcher/helper
; scripts only; the installer does not bundle FFXI game files or DAT assets.
[Files]
Source: "..\SupernovaLauncher.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\SupernovaLauncher.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\ApplySupernovaPatch.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\InstallXiloader.ps1"; DestDir: "{app}"; Flags: ignoreversion

; Start Menu and optional desktop shortcuts that launch the .cmd wrapper.
[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\SupernovaLauncher.cmd"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\SupernovaLauncher.cmd"; WorkingDir: "{app}"; Tasks: desktopicon

; Optional post-install launcher start shown on the final installer page.
[Run]
Filename: "{app}\SupernovaLauncher.cmd"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

; Custom Pascal Script for the optional patch workflow. This adds a folder
; selection page only when the player selects the patch task, then runs the
; PowerShell patch helper after the launcher files are installed.
[Code]
var
  PlayOnlineDirPage: TInputDirWizardPage;
  PatchDirPage: TInputDirWizardPage;

// Guesses the PlayOnlineViewer folder from common install locations. This is
// where pol.exe lives and where Windower expects xiloader.exe for this setup.
function GuessPlayOnlineFolder(Value: String): String;
begin
  Result := ExpandConstant('{commonpf32}\PlayOnline\SquareEnix\PlayOnlineViewer');
  if DirExists(Result) then
    Exit;

  Result := ExpandConstant('{commonpf}\PlayOnline\SquareEnix\PlayOnlineViewer');
  if DirExists(Result) then
    Exit;

  Result := 'E:\PlayOnline\SquareEnix\PlayOnlineViewer';
  if DirExists(Result) then
    Exit;

  Result := ExpandConstant('{commonpf32}\PlayOnline\SquareEnix\PlayOnlineViewer');
end;

// Guesses the player's FFXI folder from common install locations. The value is
// only a default for the wizard page; players can browse somewhere else.
function GuessFfxiFolder(Value: String): String;
begin
  Result := ExpandConstant('{commonpf32}\PlayOnline\SquareEnix\FINAL FANTASY XI');
  if DirExists(Result) then
    Exit;

  Result := ExpandConstant('{commonpf}\PlayOnline\SquareEnix\FINAL FANTASY XI');
  if DirExists(Result) then
    Exit;

  Result := 'E:\PlayOnline\SquareEnix\FINAL FANTASY XI';
  if DirExists(Result) then
    Exit;

  Result := ExpandConstant('{commonpf32}\PlayOnline\SquareEnix\FINAL FANTASY XI');
end;

// Creates the custom folder picker page used by the optional patch step.
procedure InitializeWizard;
begin
  PlayOnlineDirPage := CreateInputDirPage(
    wpSelectTasks,
    'Supernova xiloader',
    'Choose your PlayOnlineViewer folder',
    'The installer will download the Supernova-compatible xiloader v2.0.1 and place it beside pol.exe. Existing xiloader.exe files are backed up first.',
    False,
    ''
  );
  PlayOnlineDirPage.Add('PlayOnlineViewer folder:');
  PlayOnlineDirPage.Values[0] := GuessPlayOnlineFolder('');

  PatchDirPage := CreateInputDirPage(
    PlayOnlineDirPage.ID,
    'Supernova DATs and Patch Files',
    'Choose your Final Fantasy XI folder',
    'The installer will download the Supernova custom DATs and update patch, then copy the files into this FFXI folder. Existing files that are overwritten will be backed up first.',
    False,
    ''
  );
  PatchDirPage.Add('Final Fantasy XI folder:');
  PatchDirPage.Values[0] := GuessFfxiFolder('');
end;

// Hides the FFXI folder page unless the optional patch task was selected.
function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if PageID = PlayOnlineDirPage.ID then
    Result := not WizardIsTaskSelected('installxiloader');
  if PageID = PatchDirPage.ID then
    Result := not WizardIsTaskSelected('applypatch');
end;

// Validates the selected FFXI folder before allowing the wizard to continue.
function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = PlayOnlineDirPage.ID then
  begin
    if not FileExists(AddBackslash(PlayOnlineDirPage.Values[0]) + 'pol.exe') then
    begin
      MsgBox('Choose your PlayOnlineViewer folder that contains pol.exe before installing xiloader.', mbError, MB_OK);
      Result := False;
    end;
  end;

  if CurPageID = PatchDirPage.ID then
  begin
    if not DirExists(PatchDirPage.Values[0]) then
    begin
      MsgBox('Choose your FINAL FANTASY XI folder before applying the patch.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

// Runs after files are installed. If the player selected the patch task, this
// starts the PowerShell helper and waits for it to finish so setup can report
// success or failure before closing.
procedure CurStepChanged(CurStep: TSetupStep);
var
  PatchResultCode: Integer;
  XiloaderResultCode: Integer;
  PowerShellPath: String;
  PatchParams: String;
  XiloaderParams: String;
  PatchStarted: Boolean;
  XiloaderStarted: Boolean;
begin
  if CurStep = ssPostInstall then
  begin
    PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');

    if WizardIsTaskSelected('installxiloader') then
    begin
      WizardForm.StatusLabel.Caption := 'Downloading and installing xiloader v2.0.1...';

      // Build the PowerShell command that installs the pinned xiloader beside pol.exe.
      XiloaderParams := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\InstallXiloader.ps1') + '" -PlayOnlineFolder "' + PlayOnlineDirPage.Values[0] + '"';

      // If setup is already elevated, run directly. Otherwise request elevation
      // only for the xiloader helper, since PlayOnline may live under Program Files.
      if IsAdminInstallMode then
        XiloaderStarted := Exec(PowerShellPath, XiloaderParams, '', SW_SHOW, ewWaitUntilTerminated, XiloaderResultCode)
      else
        XiloaderStarted := ShellExec('runas', PowerShellPath, XiloaderParams, '', SW_SHOW, ewWaitUntilTerminated, XiloaderResultCode);

      // Tell the player where to look if the xiloader helper could not complete.
      if not XiloaderStarted then
        MsgBox('The installer could not start the xiloader helper. You can still run InstallXiloader.ps1 from the install folder later.', mbError, MB_OK)
      else if XiloaderResultCode <> 0 then
        MsgBox('The xiloader helper reported an error. Check %LOCALAPPDATA%\SupernovaFFXILauncher\XiloaderInstall.log for details.', mbError, MB_OK)
      else
        MsgBox('Supernova-compatible xiloader v2.0.1 was installed successfully. Any backup is under %LOCALAPPDATA%\SupernovaFFXILauncher\Backups.', mbInformation, MB_OK);
    end;

    if WizardIsTaskSelected('applypatch') then
    begin
      WizardForm.StatusLabel.Caption := 'Downloading and applying Supernova DATs and patch...';

      // Build the PowerShell command that runs the installed patch helper against
      // the selected FFXI folder.
      PatchParams := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\ApplySupernovaPatch.ps1') + '" -FfxiFolder "' + PatchDirPage.Values[0] + '"';

      // If setup is already elevated, run directly. Otherwise request elevation
      // only for the patch helper, since FFXI may live under Program Files.
      if IsAdminInstallMode then
        PatchStarted := Exec(PowerShellPath, PatchParams, '', SW_SHOW, ewWaitUntilTerminated, PatchResultCode)
      else
        PatchStarted := ShellExec('runas', PowerShellPath, PatchParams, '', SW_SHOW, ewWaitUntilTerminated, PatchResultCode);

      // Tell the player where to look if the patch helper could not complete.
      if not PatchStarted then
        MsgBox('The installer could not start the patch helper. You can still run ApplySupernovaPatch.ps1 from the install folder later.', mbError, MB_OK)
      else if PatchResultCode <> 0 then
        MsgBox('The patch helper reported an error. Check %LOCALAPPDATA%\SupernovaFFXILauncher\PatchInstall.log for details.', mbError, MB_OK)
      else
        MsgBox('Supernova custom DATs and patch files were applied successfully. Backups are under %LOCALAPPDATA%\SupernovaFFXILauncher\Backups.', mbInformation, MB_OK);
    end;
  end;
end;
