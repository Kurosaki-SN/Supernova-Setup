#define MyAppName "Supernova FFXI Launcher"
#define MyAppVersion "0.2.0"
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
Name: "applypatch"; Description: "Download and apply the Supernova FFXI patch now"; GroupDescription: "Supernova setup:"; Flags: unchecked

[Files]
Source: "..\SupernovaLauncher.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\SupernovaLauncher.cmd"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\ApplySupernovaPatch.ps1"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\SupernovaLauncher.cmd"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\SupernovaLauncher.cmd"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\SupernovaLauncher.cmd"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
var
  PatchDirPage: TInputDirWizardPage;

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

procedure InitializeWizard;
begin
  PatchDirPage := CreateInputDirPage(
    wpSelectTasks,
    'Supernova Patch Files',
    'Choose your Final Fantasy XI folder',
    'The installer will download the Supernova patch and copy the files into this FFXI folder. Existing files that are overwritten will be backed up first.',
    False,
    ''
  );
  PatchDirPage.Add('Final Fantasy XI folder:');
  PatchDirPage.Values[0] := GuessFfxiFolder('');
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if PageID = PatchDirPage.ID then
    Result := not WizardIsTaskSelected('applypatch');
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if CurPageID = PatchDirPage.ID then
  begin
    if not DirExists(PatchDirPage.Values[0]) then
    begin
      MsgBox('Choose your FINAL FANTASY XI folder before applying the patch.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  PowerShellPath: String;
  Params: String;
  Started: Boolean;
begin
  if (CurStep = ssPostInstall) and WizardIsTaskSelected('applypatch') then
  begin
    WizardForm.StatusLabel.Caption := 'Downloading and applying Supernova patch...';
    PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
    Params := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\ApplySupernovaPatch.ps1') + '" -FfxiFolder "' + PatchDirPage.Values[0] + '"';

    if IsAdminInstallMode then
      Started := Exec(PowerShellPath, Params, '', SW_SHOW, ewWaitUntilTerminated, ResultCode)
    else
      Started := ShellExec('runas', PowerShellPath, Params, '', SW_SHOW, ewWaitUntilTerminated, ResultCode);

    if not Started then
      MsgBox('The installer could not start the patch helper. You can still run ApplySupernovaPatch.ps1 from the install folder later.', mbError, MB_OK)
    else if ResultCode <> 0 then
      MsgBox('The patch helper reported an error. Check %LOCALAPPDATA%\SupernovaFFXILauncher\PatchInstall.log for details.', mbError, MB_OK)
    else
      MsgBox('Supernova patch files were applied successfully. Backups are under %LOCALAPPDATA%\SupernovaFFXILauncher\Backups.', mbInformation, MB_OK);
  end;
end;
