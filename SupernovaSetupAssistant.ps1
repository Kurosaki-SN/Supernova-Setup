# Guided setup UI for the Supernova FFXI private server. This is not intended to
# replace Windower or Ashita; it guides installation and runs safe helper scripts.
# Catch startup errors too. Without this, a shortcut-launched PowerShell window
# can close before the player sees the problem.
trap {
    $crashRoot = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($crashRoot)) {
        $crashRoot = $env:TEMP
    }
    $crashDir = Join-Path $crashRoot 'SupernovaSetupAssistant'
    $crashLog = Join-Path $crashDir 'StartupCrash.log'
    $desktopCrashLog = ''
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not [string]::IsNullOrWhiteSpace($desktop)) {
        $desktopCrashLog = Join-Path $desktop 'SupernovaSetupAssistant-StartupCrash.log'
    }
    $crashText = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $($_ | Out-String)"
    try {
        if (-not (Test-Path -LiteralPath $crashDir)) {
            New-Item -ItemType Directory -Path $crashDir -Force | Out-Null
        }
        Add-Content -LiteralPath $crashLog -Value $crashText
        if (-not [string]::IsNullOrWhiteSpace($desktopCrashLog)) {
            Add-Content -LiteralPath $desktopCrashLog -Value $crashText
        }
    }
    catch {
        Write-Host "Could not write startup crash log: $($_.Exception.Message)"
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show("Supernova Setup Assistant could not start.`r`n`r`nCrash log:`r`n$crashLog`r`n`r`nDesktop copy:`r`n$desktopCrashLog", 'Supernova Setup Assistant', 'OK', 'Error') | Out-Null
    }
    catch {
        Write-Host "Supernova Setup Assistant could not start. Crash log: $crashLog"
    }
    exit 1
}

# Strict mode turns common scripting mistakes into clear errors instead of
# letting the wizard continue with bad state.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Application-wide constants: server host, official download pages, local
# settings/log paths, and bundled image locations used throughout the wizard.
$script:AppName = 'Supernova Setup Assistant'
$script:ServerHost = 'login.supernovaffxi.com'
$script:OfficialFfxiInstallUrl = 'https://www.playonline.com/ff11us/download/media/install_win.html'
$script:Msvc2015RuntimeUrl = 'https://www.microsoft.com/en-ca/download/details.aspx?id=48145'
$script:WindowerUrl = 'https://www.windower.net/'
$script:AshitaUrl = 'https://www.ashitaxi.com/'
$script:SettingsDir = Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant'
$script:SettingsPath = Join-Path $script:SettingsDir 'settings.json'
$script:LogPath = Join-Path $script:SettingsDir 'SetupAssistant.log'
$script:ScriptDir = Split-Path -Parent $PSCommandPath
$script:StepImageDir = Join-Path $script:ScriptDir 'assets\update-ffxi'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Basic utility helpers for folder creation, logging, and common message boxes.
function New-DirectoryIfMissing {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-AssistantLog {
    param([Parameter(Mandatory)][string]$Message)
    New-DirectoryIfMissing -Path $script:SettingsDir
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $script:LogPath -Value "[$stamp] $Message"
}

function Show-Info {
    param([Parameter(Mandatory)][string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, $script:AppName, 'OK', 'Information') | Out-Null
}

function Show-Error {
    param([Parameter(Mandatory)][string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, $script:AppName, 'OK', 'Error') | Out-Null
}

function Confirm-Action {
    param([Parameter(Mandatory)][string]$Message)
    $result = [System.Windows.Forms.MessageBox]::Show($Message, $script:AppName, 'YesNo', 'Warning')
    return $result -eq [System.Windows.Forms.DialogResult]::Yes
}

# Default path discovery helpers. These fill in likely install paths but still
# let the user browse when their install is somewhere else.
function Add-CandidatePath {
    param(
        [System.Collections.Generic.List[string]]$Candidates,
        [string]$Base,
        [string]$Child
    )
    if (-not [string]::IsNullOrWhiteSpace($Base)) {
        $Candidates.Add((Join-Path $Base $Child)) | Out-Null
    }
}

function Get-KnownPath {
    param([string[]]$Candidates, [string]$Fallback)
    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }
    return $Fallback
}

function Get-DefaultPlayOnlineFolder {
    $pf86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $pf = [Environment]::GetFolderPath('ProgramFiles')
    $candidates = [System.Collections.Generic.List[string]]::new()
    Add-CandidatePath -Candidates $candidates -Base $pf86 -Child 'PlayOnline\SquareEnix\PlayOnlineViewer'
    Add-CandidatePath -Candidates $candidates -Base $pf -Child 'PlayOnline\SquareEnix\PlayOnlineViewer'
    $candidates.Add('E:\PlayOnline\SquareEnix\PlayOnlineViewer') | Out-Null
    $fallback = if (-not [string]::IsNullOrWhiteSpace($pf86)) { Join-Path $pf86 'PlayOnline\SquareEnix\PlayOnlineViewer' } else { 'C:\Program Files (x86)\PlayOnline\SquareEnix\PlayOnlineViewer' }
    return Get-KnownPath -Candidates $candidates.ToArray() -Fallback $fallback
}

function Get-DefaultFfxiFolder {
    $pf86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $pf = [Environment]::GetFolderPath('ProgramFiles')
    $candidates = [System.Collections.Generic.List[string]]::new()
    Add-CandidatePath -Candidates $candidates -Base $pf86 -Child 'PlayOnline\SquareEnix\FINAL FANTASY XI'
    Add-CandidatePath -Candidates $candidates -Base $pf -Child 'PlayOnline\SquareEnix\FINAL FANTASY XI'
    $candidates.Add('E:\PlayOnline\SquareEnix\FINAL FANTASY XI') | Out-Null
    $fallback = if (-not [string]::IsNullOrWhiteSpace($pf86)) { Join-Path $pf86 'PlayOnline\SquareEnix\FINAL FANTASY XI' } else { 'C:\Program Files (x86)\PlayOnline\SquareEnix\FINAL FANTASY XI' }
    return Get-KnownPath -Candidates $candidates.ToArray() -Fallback $fallback
}

function Get-DefaultWindowerExe {
    $pf86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $candidates = [System.Collections.Generic.List[string]]::new()
    Add-CandidatePath -Candidates $candidates -Base $pf86 -Child 'Windower4\Windower.exe'
    Add-CandidatePath -Candidates $candidates -Base $HOME -Child 'Desktop\Windower4\Windower.exe'
    $candidates.Add('C:\Windower4\Windower.exe') | Out-Null
    $fallback = if (-not [string]::IsNullOrWhiteSpace($pf86)) { Join-Path $pf86 'Windower4\Windower.exe' } else { 'C:\Windower4\Windower.exe' }
    return Get-KnownPath -Candidates $candidates.ToArray() -Fallback $fallback
}

function Get-DefaultAshitaFolder {
    return Get-KnownPath -Candidates @(
        'C:\Ashita',
        (Join-Path $HOME 'Desktop\Ashita'),
        (Join-Path $HOME 'Downloads\Ashita')
    ) -Fallback 'C:\Ashita'
}

function Get-DefaultGameInstallFolder {
    $ffxi = Get-DefaultFfxiFolder
    $parent = Split-Path -Parent $ffxi -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        return $parent
    }

    $pol = Get-DefaultPlayOnlineFolder
    return Split-Path -Parent $pol -ErrorAction SilentlyContinue
}

function Get-DefaultSettings {
    $pol = Get-DefaultPlayOnlineFolder
    $ffxi = Get-DefaultFfxiFolder
    $windowerExe = Get-DefaultWindowerExe
    $windowerFolder = Split-Path -Parent $windowerExe -ErrorAction SilentlyContinue
    $windowerSettings = if (-not [string]::IsNullOrWhiteSpace($windowerFolder)) { Join-Path $windowerFolder 'settings.xml' } else { 'settings.xml' }
    [pscustomobject]@{
        Mode = 'Existing Installation'
        GameInstallFolder = Get-DefaultGameInstallFolder
        PlayOnlineFolder = $pol
        FfxiFolder = $ffxi
        WindowerExe = $windowerExe
        WindowerSettings = $windowerSettings
        WindowerProfile = 'Supernova'
        WindowerUsername = ''
        AshitaFolder = Get-DefaultAshitaFolder
        AshitaUsername = ''
        SelectedLauncher = 'Windower'
    }
}

# Settings are stored under LocalAppData. Passwords are intentionally not saved
# here; only usernames and paths are persisted.
function Load-Settings {
    $defaults = Get-DefaultSettings
    if (-not (Test-Path -LiteralPath $script:SettingsPath)) {
        return $defaults
    }
    try {
        $loaded = Get-Content -LiteralPath $script:SettingsPath -Raw | ConvertFrom-Json
        foreach ($name in $defaults.PSObject.Properties.Name) {
            if ($loaded.PSObject.Properties.Name -notcontains $name) {
                $loaded | Add-Member -NotePropertyName $name -NotePropertyValue $defaults.$name
            }
        }
        return $loaded
    }
    catch {
        Write-AssistantLog "Failed to load settings: $($_.Exception.Message)"
        return $defaults
    }
}

function Save-Settings {
    New-DirectoryIfMissing -Path $script:SettingsDir
    [pscustomobject]@{
        Mode = $script:CurrentMode
        GameInstallFolder = $gameRootBox.Text
        PlayOnlineFolder = $polBox.Text
        FfxiFolder = $ffxiBox.Text
        WindowerExe = $windowerExeBox.Text
        WindowerSettings = $windowerSettingsBox.Text
        WindowerProfile = $windowerProfileBox.Text
        WindowerUsername = $windowerUsernameBox.Text
        AshitaFolder = $ashitaFolderBox.Text
        AshitaUsername = $ashitaUsernameBox.Text
        SelectedLauncher = if ($windowerRadio.Checked) { 'Windower' } else { 'Ashita' }
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
}

# Process/elevation helpers. Game-folder writes stay in helper scripts, and this
# logic requests UAC only when a target path appears to be protected by Windows.
function Quote-Argument {
    param([string]$Value)
    if ($null -eq $Value) {
        return '""'
    }
    return '"' + $Value.Replace('"', '\"') + '"'
}

function Test-PathNeedsElevation {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    try {
        $full = [System.IO.Path]::GetFullPath($Path)
        $protectedRoots = @(
            [Environment]::GetFolderPath('ProgramFiles'),
            [Environment]::GetFolderPath('ProgramFilesX86'),
            [Environment]::GetFolderPath('Windows')
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        foreach ($root in $protectedRoots) {
            $rootFull = [System.IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
            if ($full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    }
    catch {
        Write-AssistantLog "Could not evaluate elevation need for '$Path': $($_.Exception.Message)"
    }
    return $false
}

$script:HelperLogHints = @{
    'InstallXiloader.ps1' = '%LOCALAPPDATA%\SupernovaSetupAssistant\XiloaderInstall.log'
    'ApplySupernovaPatch.ps1' = '%LOCALAPPDATA%\SupernovaSetupAssistant\PatchInstall.log'
    'RepairSupernovaClient.ps1' = '%LOCALAPPDATA%\SupernovaSetupAssistant\RepairSupernovaClient.log'
    'ConfigureWindower.ps1' = '%LOCALAPPDATA%\SupernovaSetupAssistant\ConfigureWindower.log'
    'ConfigureAshita.ps1' = '%LOCALAPPDATA%\SupernovaSetupAssistant\ConfigureAshita.log'
    'InstallAshitaBootloader.ps1' = '%LOCALAPPDATA%\SupernovaSetupAssistant\AshitaBootloaderInstall.log'
    'InstallMsvc2015Runtime.ps1' = '%LOCALAPPDATA%\SupernovaSetupAssistant\MsvcRuntimeInstall.log'
    'RemoveVulgarDictionary.ps1' = '%LOCALAPPDATA%\SupernovaSetupAssistant\VulgarDictionaryCleanup.log'
    'ExportSupernovaDiagnostics.ps1' = '%LOCALAPPDATA%\SupernovaSetupAssistant'
}

# Support-friendly log locations shown when a helper fails.
function Get-HelperLogHint {
    param([string]$ScriptName)
    if ($script:HelperLogHints.ContainsKey($ScriptName)) {
        return $script:HelperLogHints[$ScriptName]
    }
    return '%LOCALAPPDATA%\SupernovaSetupAssistant'
}

# Path resolution helpers. These accept a parent folder when possible and adjust
# it to the exact PlayOnlineViewer or FINAL FANTASY XI folder before writing.
function Join-CandidatePath {
    param([string]$Base, [string]$Child)
    if ([string]::IsNullOrWhiteSpace($Base)) {
        return ''
    }
    return Join-Path $Base $Child
}

function Get-ResolvedPlayOnlineFolder {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    $candidates = @(
        $Path,
        (Join-CandidatePath $Path 'PlayOnlineViewer'),
        (Join-CandidatePath $Path 'SquareEnix\PlayOnlineViewer'),
        (Join-CandidatePath $Path 'PlayOnline\SquareEnix\PlayOnlineViewer')
    )

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath (Join-Path $candidate 'pol.exe') -PathType Leaf)) {
            return $candidate
        }
    }
    return $Path
}

function Test-PlayOnlineFolderLooksValid {
    param([string]$Path)
    return (
        -not [string]::IsNullOrWhiteSpace($Path) -and
        (Test-Path -LiteralPath $Path -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Path 'pol.exe') -PathType Leaf)
    )
}

function Get-ResolvedFfxiFolder {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    $candidates = @(
        $Path,
        (Join-CandidatePath $Path 'FINAL FANTASY XI'),
        (Join-CandidatePath $Path 'SquareEnix\FINAL FANTASY XI'),
        (Join-CandidatePath $Path 'PlayOnline\SquareEnix\FINAL FANTASY XI')
    )

    foreach ($candidate in $candidates) {
        if (Test-FfxiFolderLooksValid -Path $candidate) {
            return $candidate
        }
    }
    return $Path
}

function Test-GameInstallFolderLooksValid {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $false
    }

    $pol = Join-Path $Path 'PlayOnlineViewer'
    $ffxi = Join-Path $Path 'FINAL FANTASY XI'
    return (
        (Test-PlayOnlineFolderLooksValid -Path $pol) -and
        (Test-FfxiFolderLooksValid -Path $ffxi)
    )
}

function Test-ExistingPath {
    param(
        [string]$Path,
        [ValidateSet('Leaf', 'Container')]
        [string]$PathType
    )
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }
    return Test-Path -LiteralPath $Path -PathType $PathType
}

function Get-ResolvedGameInstallFolder {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    $candidates = @(
        $Path,
        (Join-CandidatePath $Path 'SquareEnix'),
        (Join-CandidatePath $Path 'PlayOnline\SquareEnix')
    )

    if ((Split-Path -Leaf $Path) -in @('PlayOnlineViewer', 'FINAL FANTASY XI')) {
        $parent = Split-Path -Parent $Path -ErrorAction SilentlyContinue
        if (-not [string]::IsNullOrWhiteSpace($parent)) {
            $candidates += $parent
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-GameInstallFolderLooksValid -Path $candidate) {
            return $candidate
        }
    }
    return $Path
}

function Apply-GameInstallFolder {
    param([string]$Path)
    $resolved = Get-ResolvedGameInstallFolder -Path $Path
    if (-not [string]::IsNullOrWhiteSpace($resolved)) {
        $gameRootBox.Text = $resolved
        $polBox.Text = Join-Path $resolved 'PlayOnlineViewer'
        $ffxiBox.Text = Join-Path $resolved 'FINAL FANTASY XI'
        $resultBox.Text = "Game install folder selected:`r`n$resolved`r`n`r`nPlayOnlineViewer and FINAL FANTASY XI paths were filled in from that folder."
    }
}

function Test-FfxiFolderLooksValid {
    param([string]$Path)
    return (
        -not [string]::IsNullOrWhiteSpace($Path) -and
        (Test-Path -LiteralPath $Path -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Path 'ROM') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Path 'ROM3') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Path 'ROM4') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Path 'sound4') -PathType Container)
    )
}

function Set-ResolvedPathIfChanged {
    param(
        [System.Windows.Forms.TextBox]$Box,
        [string]$ResolvedPath,
        [string]$Label
    )

    if (-not [string]::IsNullOrWhiteSpace($ResolvedPath) -and $Box.Text -ne $ResolvedPath) {
        $Box.Text = $ResolvedPath
        $resultBox.Text = "$Label path adjusted to:`r`n$ResolvedPath"
    }
}

function Ensure-PlayOnlineFolder {
    if (Test-GameInstallFolderLooksValid -Path $gameRootBox.Text) {
        Apply-GameInstallFolder -Path $gameRootBox.Text
    }

    $resolved = Get-ResolvedPlayOnlineFolder -Path $polBox.Text
    Set-ResolvedPathIfChanged -Box $polBox -ResolvedPath $resolved -Label 'PlayOnlineViewer'
    if (-not (Test-PlayOnlineFolderLooksValid -Path $polBox.Text)) {
        throw "Select the PlayOnlineViewer folder that contains pol.exe. Do not choose the FINAL FANTASY XI folder, SquareEnix parent folder, or PlayOnline parent folder. Current value: $($polBox.Text)"
    }
    Save-Settings
    return $polBox.Text
}

function Ensure-FfxiFolder {
    if (Test-GameInstallFolderLooksValid -Path $gameRootBox.Text) {
        Apply-GameInstallFolder -Path $gameRootBox.Text
    }

    $resolved = Get-ResolvedFfxiFolder -Path $ffxiBox.Text
    Set-ResolvedPathIfChanged -Box $ffxiBox -ResolvedPath $resolved -Label 'FINAL FANTASY XI'
    if (-not (Test-FfxiFolderLooksValid -Path $ffxiBox.Text)) {
        throw "Select the FINAL FANTASY XI folder itself. It should contain ROM, ROM3, ROM4, and sound4 folders. Do not choose PlayOnlineViewer, SquareEnix, or PlayOnline. Current value: $($ffxiBox.Text)"
    }
    Save-Settings
    return $ffxiBox.Text
}

function Ensure-XiloaderInstalled {
    $pol = Ensure-PlayOnlineFolder
    $xiloader = Join-Path $pol 'xiloader.exe'
    if (-not (Test-Path -LiteralPath $xiloader -PathType Leaf)) {
        throw "xiloader.exe is not installed beside pol.exe yet. Click Install xiloader first."
    }
    return $xiloader
}

function Test-RunAsAdminCompatibilityFlag {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
        Write-AssistantLog "Could not resolve Run as administrator path '$Path': $($_.Exception.Message)"
        return $false
    }

    $registryPaths = @(
        'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers',
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    )

    foreach ($registryPath in $registryPaths) {
        try {
            if (-not (Test-Path -LiteralPath $registryPath)) {
                continue
            }

            $props = Get-ItemProperty -LiteralPath $registryPath
            foreach ($property in $props.PSObject.Properties) {
                if ($property.Name.Equals($fullPath, [StringComparison]::OrdinalIgnoreCase) -and ([string]$property.Value) -match 'RUNASADMIN') {
                    return $true
                }
            }
        }
        catch {
            Write-AssistantLog "Could not read compatibility flags from ${registryPath}: $($_.Exception.Message)"
        }
    }

    return $false
}

# Runtime detection helpers. The assistant validates the x86 VC++ runtime before
# saying setup is complete.
function Get-Msvc2015RuntimeX86Status {
    $runtimeRegistryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x86',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86'
    )

    foreach ($path in $runtimeRegistryPaths) {
        try {
            if (-not (Test-Path -LiteralPath $path)) {
                continue
            }

            $props = Get-ItemProperty -LiteralPath $path
            $installedValue = 0
            if ($props.PSObject.Properties.Name -contains 'Installed') {
                $installedValue = [int]$props.Installed
            }

            if ($installedValue -eq 1) {
                $version = 'unknown'
                if (($props.PSObject.Properties.Name -contains 'Version') -and -not [string]::IsNullOrWhiteSpace([string]$props.Version)) {
                    $version = [string]$props.Version
                }
                return [pscustomobject]@{ Installed = $true; Version = $version; Source = $path }
            }
        }
        catch {
            Write-AssistantLog "MSVC runtime registry check failed for ${path}: $($_.Exception.Message)"
        }
    }

    $bundleRegistryPaths = @(
        'HKLM:\SOFTWARE\Classes\Installer\Dependencies\,,x86,14.0,bundle',
        'HKLM:\SOFTWARE\WOW6432Node\Classes\Installer\Dependencies\,,x86,14.0,bundle'
    )

    foreach ($path in $bundleRegistryPaths) {
        try {
            if (-not (Test-Path -LiteralPath $path)) {
                continue
            }

            $props = Get-ItemProperty -LiteralPath $path
            $version = 'unknown'
            if (($props.PSObject.Properties.Name -contains 'Version') -and -not [string]::IsNullOrWhiteSpace([string]$props.Version)) {
                $version = [string]$props.Version
            }
            return [pscustomobject]@{ Installed = $true; Version = $version; Source = $path }
        }
        catch {
            Write-AssistantLog "MSVC runtime bundle registry check failed for ${path}: $($_.Exception.Message)"
        }
    }

    return [pscustomobject]@{ Installed = $false; Version = 'missing'; Source = '' }
}

function Test-Msvc2015RuntimeX86Installed {
    return (Get-Msvc2015RuntimeX86Status).Installed
}

# Launcher input validation. These checks catch common support mistakes before a
# helper edits Windower or Ashita config files.
function Ensure-WindowerInputs {
    if (-not (Test-Path -LiteralPath $windowerExeBox.Text -PathType Leaf)) {
        throw "Select Windower.exe. It is usually inside your Windower folder."
    }
    if ([System.IO.Path]::GetFileName($windowerExeBox.Text) -ne 'Windower.exe') {
        throw "The Windower path must point to Windower.exe. Current value: $($windowerExeBox.Text)"
    }
    if (-not (Test-Path -LiteralPath $windowerSettingsBox.Text -PathType Leaf)) {
        throw "Select Windower settings.xml. It is usually in the same folder as Windower.exe."
    }
    if ([System.IO.Path]::GetFileName($windowerSettingsBox.Text) -ne 'settings.xml') {
        throw "The Windower settings path must point to settings.xml. Current value: $($windowerSettingsBox.Text)"
    }
}

function Ensure-WindowerAccountInputs {
    Ensure-WindowerInputs
    if ([string]::IsNullOrWhiteSpace($windowerUsernameBox.Text)) {
        throw "Enter the Windower account username before updating the args."
    }
    if ([string]::IsNullOrWhiteSpace($windowerPasswordBox.Text)) {
        throw "Enter the Windower account password before updating the args."
    }
    if ($windowerUsernameBox.Text -match '\s|"') {
        throw "The Windower username cannot contain spaces or quotation marks."
    }
    if ($windowerPasswordBox.Text -match '\s|"') {
        throw "The Windower password cannot contain spaces or quotation marks."
    }
}

function Ensure-AshitaInputs {
    if (-not (Test-Path -LiteralPath $ashitaFolderBox.Text -PathType Container)) {
        throw "Select your Ashita folder."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $ashitaFolderBox.Text 'ashita-cli.exe') -PathType Leaf)) {
        throw "ashita-cli.exe was not found in the selected Ashita folder. Select the folder that contains ashita-cli.exe."
    }
}

function Ensure-AshitaAccountInputs {
    Ensure-AshitaInputs
    if ([string]::IsNullOrWhiteSpace($ashitaUsernameBox.Text)) {
        throw "Enter the Ashita account username before updating the command."
    }
    if ([string]::IsNullOrWhiteSpace($ashitaPasswordBox.Text)) {
        throw "Enter the Ashita account password before updating the command."
    }
    if ($ashitaUsernameBox.Text -match '\s|"') {
        throw "The Ashita username cannot contain spaces or quotation marks."
    }
    if ($ashitaPasswordBox.Text -match '\s|"') {
        throw "The Ashita password cannot contain spaces or quotation marks."
    }
}

# Helper runner. It centralizes argument quoting, optional output capture, UAC
# prompts, and error messages for all modular helper scripts.
function Invoke-Helper {
    param(
        [Parameter(Mandatory)][string]$ScriptName,
        [hashtable]$Arguments,
        [string]$ElevationPath = '',
        [switch]$ForceElevation,
        [string]$ElevationReason = '',
        [switch]$CaptureOutput,
        [string]$FriendlyName = ''
    )

    if ([string]::IsNullOrWhiteSpace($FriendlyName)) {
        $FriendlyName = $ScriptName
    }

    $scriptPath = Join-Path $script:ScriptDir $ScriptName
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Helper script missing: $scriptPath"
    }

    $argParts = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Quote-Argument $scriptPath))
    foreach ($key in $Arguments.Keys) {
        $value = $Arguments[$key]
        if ($value -is [System.Management.Automation.SwitchParameter] -or $value -is [bool]) {
            if ([bool]$value) {
                $argParts += "-$key"
            }
            continue
        }
        $argParts += "-$key"
        $argParts += (Quote-Argument ([string]$value))
    }
    $argString = $argParts -join ' '

    $requiresElevation = $ForceElevation -or (Test-PathNeedsElevation -Path $ElevationPath)
    Write-AssistantLog "Running helper $ScriptName; elevated=$requiresElevation"

    if ($CaptureOutput -and -not $requiresElevation) {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = 'powershell.exe'
        $psi.Arguments = $argString
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $process = [System.Diagnostics.Process]::Start($psi)
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            $details = if ([string]::IsNullOrWhiteSpace($stderr)) { $stdout } else { $stderr }
            throw "$FriendlyName did not finish successfully. The assistant has not marked setup complete. Details: $details"
        }
        return $stdout.Trim()
    }

    if ($requiresElevation) {
        if ([string]::IsNullOrWhiteSpace($ElevationReason)) {
            if ([string]::IsNullOrWhiteSpace($ElevationPath)) {
                $ElevationReason = 'make a protected Windows system change'
            }
            else {
                $ElevationReason = "write to:`r`n$ElevationPath"
            }
        }
        Show-Info "$FriendlyName needs Windows administrator approval because it will $ElevationReason.`r`n`r`nIf you choose No or close the prompt, this step stops and setup will not be marked complete."
    }

    $startParams = @{
        FilePath = 'powershell.exe'
        ArgumentList = $argString
        Wait = $true
        PassThru = $true
    }
    if ($requiresElevation) {
        $startParams.Verb = 'runas'
    }
    try {
        $p = Start-Process @startParams
    }
    catch {
        if ($requiresElevation) {
            throw "Windows administrator approval was not completed for $FriendlyName. No setup completion was recorded. Click the step again and choose Yes on the Windows prompt, or move FFXI/PlayOnline outside Program Files. Log: $(Get-HelperLogHint -ScriptName $ScriptName)"
        }
        throw
    }

    if ($p.ExitCode -ne 0) {
        throw "$FriendlyName did not finish successfully. The assistant has not marked setup complete. Exit code: $($p.ExitCode). Log: $(Get-HelperLogHint -ScriptName $ScriptName)"
    }
    return ''
}

# Browse/detect helpers used by the path selection controls.
function Browse-Folder {
    param([string]$Description, [string]$CurrentPath)
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $false
    if (-not [string]::IsNullOrWhiteSpace($CurrentPath) -and (Test-Path -LiteralPath $CurrentPath)) {
        $dialog.SelectedPath = $CurrentPath
    }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }
    return $null
}

function Browse-File {
    param([string]$Title, [string]$CurrentPath, [string]$Filter = 'Executable files (*.exe)|*.exe|All files (*.*)|*.*')
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = $Title
    $dialog.Filter = $Filter
    $parent = Split-Path -Parent $CurrentPath -ErrorAction SilentlyContinue
    if (-not [string]::IsNullOrWhiteSpace($parent) -and (Test-Path -LiteralPath $parent)) {
        $dialog.InitialDirectory = $parent
    }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }
    return $null
}

function Detect-Paths {
    $pol = Get-DefaultPlayOnlineFolder
    if (Test-Path -LiteralPath $pol) { $polBox.Text = $pol }
    $ffxi = Get-DefaultFfxiFolder
    if (Test-Path -LiteralPath $ffxi) { $ffxiBox.Text = $ffxi }
    $root = Get-DefaultGameInstallFolder
    if (Test-GameInstallFolderLooksValid -Path $root) {
        Apply-GameInstallFolder -Path $root
    }
    $windower = Get-DefaultWindowerExe
    if (Test-Path -LiteralPath $windower) {
        $windowerExeBox.Text = $windower
        $windowerSettingsBox.Text = Join-Path (Split-Path -Parent $windower) 'settings.xml'
    }
    $ashita = Get-DefaultAshitaFolder
    if (Test-Path -LiteralPath $ashita) { $ashitaFolderBox.Text = $ashita }
    Save-Settings
    [void](Show-Validation)
}

# Windower and Ashita validation helpers. These read configs only; they do not
# change player files.
function Test-WindowerConfigured {
    if (-not (Test-Path -LiteralPath $windowerSettingsBox.Text -PathType Leaf)) {
        return $false
    }
    try {
        [xml]$doc = Get-Content -LiteralPath $windowerSettingsBox.Text -Raw
        $profiles = $doc.SelectNodes("//*[local-name()='profile']")
        foreach ($profile in $profiles) {
            $match = $false
            if ($profile.Attributes -and $profile.Attributes['name'] -and $profile.Attributes['name'].Value -eq $windowerProfileBox.Text) {
                $match = $true
            }
            $nameNode = $profile.SelectSingleNode("*[local-name()='name']")
            if ($nameNode -and $nameNode.InnerText -eq $windowerProfileBox.Text) {
                $match = $true
            }
            if ($match) {
                $args = $profile.SelectSingleNode("*[local-name()='args']")
                $exe = $profile.SelectSingleNode("*[local-name()='executable']")
                return ($args -and $args.InnerText -match 'login\.supernovaffxi\.com' -and $exe -and $exe.InnerText -eq 'xiloader.exe')
            }
        }
    }
    catch {
        Write-AssistantLog "Windower validation failed: $($_.Exception.Message)"
    }
    return $false
}

function Test-WindowerAccountArgsConfigured {
    if (-not (Test-Path -LiteralPath $windowerSettingsBox.Text -PathType Leaf)) {
        return $false
    }
    try {
        [xml]$doc = Get-Content -LiteralPath $windowerSettingsBox.Text -Raw
        $profiles = $doc.SelectNodes("//*[local-name()='profile']")
        foreach ($profile in $profiles) {
            $match = $false
            if ($profile.Attributes -and $profile.Attributes['name'] -and $profile.Attributes['name'].Value -eq $windowerProfileBox.Text) {
                $match = $true
            }
            $nameNode = $profile.SelectSingleNode("*[local-name()='name']")
            if ($nameNode -and $nameNode.InnerText -eq $windowerProfileBox.Text) {
                $match = $true
            }
            if ($match) {
                $args = $profile.SelectSingleNode("*[local-name()='args']")
                return (
                    $args -and
                    $args.InnerText -match '--server\s+login\.supernovaffxi\.com' -and
                    $args.InnerText -match '--user\s+\S+' -and
                    $args.InnerText -match '--password\s+\S+'
                )
            }
        }
    }
    catch {
        Write-AssistantLog "Windower account args validation failed: $($_.Exception.Message)"
    }
    return $false
}

function Test-WindowerProfileExists {
    if (-not (Test-Path -LiteralPath $windowerSettingsBox.Text -PathType Leaf)) {
        return $false
    }
    try {
        [xml]$doc = Get-Content -LiteralPath $windowerSettingsBox.Text -Raw
        $profiles = $doc.SelectNodes("//*[local-name()='profile']")
        foreach ($profile in $profiles) {
            if ($profile.Attributes -and $profile.Attributes['name'] -and $profile.Attributes['name'].Value -eq $windowerProfileBox.Text) {
                return $true
            }
            $nameNode = $profile.SelectSingleNode("*[local-name()='name']")
            if ($nameNode -and $nameNode.InnerText -eq $windowerProfileBox.Text) {
                return $true
            }
        }
    }
    catch {
        Write-AssistantLog "Windower profile lookup failed: $($_.Exception.Message)"
    }
    return $false
}

function Test-AshitaConfigured {
    if ([string]::IsNullOrWhiteSpace($ashitaFolderBox.Text)) {
        return $false
    }
    $config = Join-Path $ashitaFolderBox.Text 'config\boot\supernova.ini'
    try {
        $bootloader = [regex]::Escape((Join-Path $ashitaFolderBox.Text 'ffxi-bootmod\xiloader.exe'))
        $content = Get-Content -LiteralPath $config -Raw
        return (
            (Test-Path -LiteralPath (Join-Path $ashitaFolderBox.Text 'ashita-cli.exe') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $ashitaFolderBox.Text 'ffxi-bootmod\xiloader.exe') -PathType Leaf) -and
            (Test-Path -LiteralPath $config -PathType Leaf) -and
            ($content -match 'login\.supernovaffxi\.com') -and
            ($content -match $bootloader)
        )
    }
    catch {
        Write-AssistantLog "Ashita validation failed: $($_.Exception.Message)"
        return $false
    }
}

function Test-AshitaAccountCommandConfigured {
    if ([string]::IsNullOrWhiteSpace($ashitaFolderBox.Text)) {
        return $false
    }
    $config = Join-Path $ashitaFolderBox.Text 'config\boot\supernova.ini'
    try {
        if (-not (Test-Path -LiteralPath $config -PathType Leaf)) {
            return $false
        }
        $content = Get-Content -LiteralPath $config -Raw
        return (
            ($content -match '--server\s+login\.supernovaffxi\.com') -and
            ($content -match '--user\s+\S+') -and
            ($content -match '--password\s+\S+')
        )
    }
    catch {
        Write-AssistantLog "Ashita account command validation failed: $($_.Exception.Message)"
        return $false
    }
}

function Test-AshitaBootloaderInstalled {
    if ([string]::IsNullOrWhiteSpace($ashitaFolderBox.Text)) {
        return $false
    }
    $bootloader = Join-Path $ashitaFolderBox.Text 'ffxi-bootmod\xiloader.exe'
    return Test-Path -LiteralPath $bootloader -PathType Leaf
}

function New-ValidationResult {
    param([string]$Name, [bool]$Passed)
    return [pscustomobject]@{
        Name = $Name
        Passed = $Passed
    }
}

# Final readiness checks. The wizard only calls setup ready when the required
# files and selected launcher configuration pass these tests.
function Get-ValidationResults {
    $results = @()
    $results += New-ValidationResult -Name 'Game install folder contains PlayOnlineViewer and FINAL FANTASY XI' -Passed (Test-GameInstallFolderLooksValid -Path $gameRootBox.Text)
    $results += New-ValidationResult -Name 'Microsoft Visual C++ 2015 x86 runtime is installed' -Passed (Test-Msvc2015RuntimeX86Installed)
    $results += New-ValidationResult -Name 'PlayOnlineViewer folder is selected and contains pol.exe' -Passed (Test-PlayOnlineFolderLooksValid -Path $polBox.Text)
    $results += New-ValidationResult -Name 'xiloader.exe exists beside pol.exe' -Passed (Test-ExistingPath -Path (Join-CandidatePath $polBox.Text 'xiloader.exe') -PathType Leaf)
    $results += New-ValidationResult -Name 'pol.exe is set to Run as administrator' -Passed (Test-RunAsAdminCompatibilityFlag -Path (Join-CandidatePath $polBox.Text 'pol.exe'))
    $results += New-ValidationResult -Name 'xiloader.exe is set to Run as administrator' -Passed (Test-RunAsAdminCompatibilityFlag -Path (Join-CandidatePath $polBox.Text 'xiloader.exe'))
    $results += New-ValidationResult -Name 'FINAL FANTASY XI folder is selected and contains ROM, ROM3, ROM4, and sound4' -Passed (Test-FfxiFolderLooksValid -Path $ffxiBox.Text)
    $results += New-ValidationResult -Name 'Supernova DAT representative appears installed: ROM4\1\69.dat' -Passed (Test-ExistingPath -Path (Join-CandidatePath $ffxiBox.Text 'ROM4\1\69.dat') -PathType Leaf)
    $results += New-ValidationResult -Name 'Supernova patch representative appears installed: FFXi.dll' -Passed (Test-ExistingPath -Path (Join-CandidatePath $ffxiBox.Text 'FFXi.dll') -PathType Leaf)

    if ($windowerRadio.Checked) {
        $results += New-ValidationResult -Name 'Windower.exe is selected' -Passed (Test-ExistingPath -Path $windowerExeBox.Text -PathType Leaf)
        $results += New-ValidationResult -Name 'Windower settings.xml is selected' -Passed (Test-ExistingPath -Path $windowerSettingsBox.Text -PathType Leaf)
        $results += New-ValidationResult -Name 'Windower profile uses xiloader.exe and the Supernova server' -Passed (Test-WindowerConfigured)
        $windowerAccountArgsConfigured = Test-WindowerAccountArgsConfigured
        if ($windowerAccountArgsConfigured -or -not [string]::IsNullOrWhiteSpace($windowerUsernameBox.Text)) {
            $results += New-ValidationResult -Name 'Windower profile includes username and password args' -Passed $windowerAccountArgsConfigured
        }
    }
    elseif ($ashitaRadio.Checked) {
        $ashitaCliPresent = $false
        if (-not [string]::IsNullOrWhiteSpace($ashitaFolderBox.Text)) {
            $ashitaCliPresent = Test-ExistingPath -Path (Join-CandidatePath $ashitaFolderBox.Text 'ashita-cli.exe') -PathType Leaf
        }
        $results += New-ValidationResult -Name 'Ashita folder contains ashita-cli.exe' -Passed $ashitaCliPresent
        $results += New-ValidationResult -Name 'Ashita ffxi-bootmod contains xiloader.exe' -Passed (Test-AshitaBootloaderInstalled)
        $results += New-ValidationResult -Name 'Ashita supernova.ini uses the Supernova server' -Passed (Test-AshitaConfigured)
        $results += New-ValidationResult -Name 'Ashita supernova.ini includes username and password command' -Passed (Test-AshitaAccountCommandConfigured)
    }
    else {
        $results += New-ValidationResult -Name 'Windower or Ashita is selected' -Passed $false
    }

    return ,$results
}

function Show-Validation {
    $results = Get-ValidationResults
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($result in $results) {
        $mark = if ($result.Passed) { 'PASS' } else { 'MISSING' }
        $lines.Add(("{0}: {1}" -f $mark, $result.Name)) | Out-Null
    }

    $complete = -not @($results | Where-Object { -not $_.Passed }).Count
    $lines.Add('') | Out-Null
    if ($complete) {
        $lines.Add('READY: Setup validation passed. Start the game through the configured Windower or Ashita profile.') | Out-Null
    }
    else {
        $lines.Add('NOT READY: Setup is not complete yet. Fix each MISSING item before playing.') | Out-Null
    }
    $resultBox.Text = $lines -join "`r`n"
    return $complete
}

# Wizard mode and step navigation helpers. New Installation dynamically appends
# either the Windower branch or the Ashita branch based on the selected method.
function Set-Mode {
    param([string]$Mode)
    if (-not $script:StepSets.ContainsKey($Mode)) {
        $Mode = 'Existing Installation'
    }
    $script:CurrentMode = $Mode
    Update-StepList
    Save-Settings
}

function Get-SelectedPlayMethod {
    $windowerVar = Get-Variable -Name windowerRadio -ErrorAction SilentlyContinue
    $ashitaVar = Get-Variable -Name ashitaRadio -ErrorAction SilentlyContinue
    if ($windowerVar -and $windowerRadio.Checked) {
        return 'Windower'
    }
    if ($ashitaVar -and $ashitaRadio.Checked) {
        return 'Ashita'
    }
    if ($settings.SelectedLauncher -eq 'Ashita') {
        return 'Ashita'
    }
    return 'Windower'
}

function Get-StepsForMode {
    param([string]$Mode)
    $steps = @($script:StepSets[$Mode])
    if ($Mode -eq 'New Installation') {
        $branchKey = "New Installation - $(Get-SelectedPlayMethod)"
        if ($script:StepSets.ContainsKey($branchKey)) {
            $steps += @($script:StepSets[$branchKey])
        }
    }
    return ,$steps
}

function Update-StepList {
    $oldIndex = $stepsList.SelectedIndex
    $oldTitle = ''
    if ($oldIndex -ge 0 -and $oldIndex -lt $script:CurrentSteps.Count) {
        $oldTitle = $script:CurrentSteps[$oldIndex].Title
    }

    $script:CurrentSteps = @(Get-StepsForMode -Mode $script:CurrentMode)
    $stepsList.Items.Clear()
    foreach ($step in $script:CurrentSteps) {
        $stepsList.Items.Add($step.Title) | Out-Null
    }

    if ($stepsList.Items.Count -eq 0) {
        return
    }

    $newIndex = -1
    if (-not [string]::IsNullOrWhiteSpace($oldTitle)) {
        for ($i = 0; $i -lt $script:CurrentSteps.Count; $i++) {
            if ($script:CurrentSteps[$i].Title -eq $oldTitle) {
                $newIndex = $i
                break
            }
        }
    }

    if ($newIndex -lt 0) {
        if ($oldIndex -ge 0) {
            $newIndex = [Math]::Min($oldIndex, $stepsList.Items.Count - 1)
        }
        else {
            $newIndex = 0
        }
    }

    $stepsList.SelectedIndex = $newIndex
}

# Guide-image and conditional-control helpers. Some steps show screenshots, and
# account boxes only appear on their relevant Windower/Ashita steps.
function Update-StepImage {
    param([string]$ImageFile)

    $imageBoxVar = Get-Variable -Name stepImageBox -ErrorAction SilentlyContinue
    $imageLabelVar = Get-Variable -Name stepImageLabel -ErrorAction SilentlyContinue
    if (-not $imageBoxVar -or -not $imageLabelVar) {
        return
    }

    if ($stepImageBox.Image) {
        $stepImageBox.Image.Dispose()
        $stepImageBox.Image = $null
    }

    if ([string]::IsNullOrWhiteSpace($ImageFile)) {
        $stepImageBox.Visible = $false
        $stepImageLabel.Visible = $false
        return
    }

    $imagePath = Join-Path $script:StepImageDir $ImageFile
    if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
        $stepImageBox.Visible = $false
        $stepImageLabel.Visible = $false
        Write-AssistantLog "Step image missing: $imagePath"
        return
    }

    $loaded = [System.Drawing.Image]::FromFile($imagePath)
    try {
        $stepImageBox.Image = New-Object System.Drawing.Bitmap($loaded)
    }
    finally {
        $loaded.Dispose()
    }
    $stepImageLabel.Text = 'Guide image for this step'
    $stepImageLabel.Visible = $true
    $stepImageBox.Visible = $true
}

function Update-StepControls {
    param($Step)

    $accountGroupVar = Get-Variable -Name ashitaAccountGroup -ErrorAction SilentlyContinue
    if ($accountGroupVar) {
        $ashitaAccountGroup.Visible = ($Step.Title -like '20. Add Ashita account command*')
    }

    $windowerAccountGroupVar = Get-Variable -Name windowerAccountGroup -ErrorAction SilentlyContinue
    if ($windowerAccountGroupVar) {
        $windowerAccountGroup.Visible = ($Step.Title -like '20. Add Windower login args*')
    }
}

function Update-StepView {
    if ($stepsList.SelectedIndex -lt 0) { return }
    if ($stepsList.SelectedIndex -ge $script:CurrentSteps.Count) { return }
    $step = $script:CurrentSteps[$stepsList.SelectedIndex]
    $stepTitle.Text = $step.Title
    $stepText.Text = $step.Body
    $imageFile = ''
    if ($step.PSObject.Properties.Name -contains 'Image') {
        $imageFile = $step.Image
    }
    Update-StepImage -ImageFile $imageFile
    Update-StepControls -Step $step
    if ($stepsList.SelectedIndex -lt ($stepsList.Items.Count - 1)) {
        $nextButton.Text = 'Next Step ->'
        $nextButton.Enabled = $true
    }
    else {
        $nextButton.Text = 'Final Step'
        $nextButton.Enabled = $false
    }
}

# Step definitions shown in the wizard. These are user-facing instructions and
# keep manual PlayOnline/Windower/Ashita work explicit instead of automating UI.
$script:StepSets = @{
    'New Installation' = @(
        [pscustomobject]@{ Title = '1. Download FFXI and PlayOnline'; Body = "Manual step: click Open FFXI Download. It opens the official Square Enix page: $script:OfficialFfxiInstallUrl. Download and install the PlayOnline Viewer and FINAL FANTASY XI files yourself, then return to this assistant." },
        [pscustomobject]@{ Title = '2. Install FFXI and PlayOnline'; Body = 'Manual step: from the files you downloaded, install these components: PlayOnline Viewer and Final Fantasy XI Online. Then use the Game install folder Browse button to select the parent folder that contains both PlayOnlineViewer and FINAL FANTASY XI. Finish both installers and select that folder before clicking Next Step.' },
        [pscustomobject]@{ Title = '3. Run PlayOnline update'; Body = 'Manual step: run PlayOnline Viewer and let it update completely. If PlayOnline restarts during the update, let it finish before clicking Next Step.' },
        [pscustomobject]@{ Title = '4. Save Existing User settings'; Body = 'Manual step: after PlayOnline updates and restarts, choose Existing User. Enter any Member Name you want. For the PlayOnline ID and password, enter 1234567, or use any values you prefer. Save the settings, then return here.' },
        [pscustomobject]@{ Title = '5. Install patch files'; Body = 'Automated step: use Detect Paths or Browse on Game install folder if the paths are not already filled in, then click Install Patch Files. The assistant downloads the Supernova patch zip and places those files in the correct FFXI folder with backups. When it finishes, click Next Step.' },
        [pscustomobject]@{ Title = '6. Click Check Files'; Body = 'Manual step: run PlayOnline Viewer. On the left side of the PlayOnline screen, click Check Files.'; Image = 'checkfiles_ffxi_1.png' },
        [pscustomobject]@{ Title = '7. Select FINAL FANTASY XI'; Body = 'Manual step: in the Check Files screen, select FINAL FANTASY XI from the drop-down box.'; Image = 'checkfiles_ffxi_2.png' },
        [pscustomobject]@{ Title = '8. Run Check Files'; Body = 'Manual step: click Check Files and wait for the file check to complete.'; Image = 'checkfiles_ffxi_3.png' },
        [pscustomobject]@{ Title = '9. Run File Repair'; Body = 'Manual step: click the File Repair button. If you get a separate popup window that says it is launching the FFXI installer or asks for install discs, you can close that popup.'; Image = 'filecheck_ffxi_repair.png' },
        [pscustomobject]@{ Title = '10. Install MSVC 2015 x86 runtime'; Body = "Automated step: click Install MSVC x86. The assistant downloads vc_redist.x86.exe from Microsoft's official Visual C++ Redistributable 2015 page and installs it. Windows will ask for administrator approval because this installs a system runtime, not because it changes your FFXI files. When it finishes, click Next Step." },
        [pscustomobject]@{ Title = '11. Install Supernova DATs'; Body = 'Automated step: click Install Supernova DATs. The assistant downloads the Supernova DAT zip and extracts those files into the correct FINAL FANTASY XI folders with backups. Folder paths such as ROM, ROM3, ROM4, and sound4 are preserved. Optional: click Optional: Delete vulgar2.dic if your setup instructions require that file removed; the assistant backs it up first.' },
        [pscustomobject]@{ Title = '12. Download and install xiloader'; Body = 'Automated step: use Detect Paths or Browse on Game install folder if the PlayOnlineViewer path is not filled in, then click Install xiloader. The assistant downloads pinned Supernova-compatible xiloader v2.0.1, verifies it, backs up any existing xiloader.exe, and places xiloader.exe in the same PlayOnlineViewer folder where pol.exe lives. If that folder is protected by Windows, approve the administrator prompt.' },
        [pscustomobject]@{ Title = '13. Set pol.exe and xiloader.exe to run as administrator'; Body = 'Manual step: click Open POL Folder, or open the selected PlayOnlineViewer folder yourself. Right-click pol.exe, choose Properties, open the Compatibility tab, check Run this program as an administrator at the bottom of the window, then click Apply and OK. Repeat the same steps for xiloader.exe. You must do this for both pol.exe and xiloader.exe before clicking Next Step.' },
        [pscustomobject]@{ Title = '14. Download Windower or Ashita'; Body = "Manual step: choose the play method you are going to use in Required Play Method. Windower is recommended. If you choose Windower, click Open Windower Website. If you choose Ashita, click Open Ashita Website. Download and run the selected tool's executable yourself.`r`n`r`nNOTE: WINDOWER WILL INSTALL INTO WHATEVER DIRECTORY YOU PLACE THE DOWNLOADED EXECUTABLE FROM.`r`n`r`nNOTE: ASHITA WILL INSTALL INTO WHATEVER DIRECTORY YOU PLACE THE DOWNLOADED EXECUTABLE FROM." }
    )
    'New Installation - Windower' = @(
        [pscustomobject]@{ Title = '15. Start Windower'; Body = 'Manual step: after Windower is installed, start Windower. If the Windower.exe path is not filled in yet, use the Windower.exe Browse button under Selected Paths, then click Open Windower or start Windower from its folder.' },
        [pscustomobject]@{ Title = '16. Create a Windower profile'; Body = 'Manual step: in Windower, click the + symbol at the bottom left to create a new profile. Highlight your new profile, then click the pencil icon to adjust your desired settings. Before the automated configuration step, make sure the Windower profile box in this assistant matches the profile name you created.' },
        [pscustomobject]@{ Title = '17. Create a Windower desktop shortcut'; Body = 'Manual step: in Windower, highlight the profile you created, then click the pin icon to create a desktop shortcut for that profile. When the shortcut is created, return to this assistant and click Next Step.' },
        [pscustomobject]@{ Title = '18. Configure Windower profile XML'; Body = "Automated step: click Configure Windower. The assistant backs up settings.xml, finds the profile named in the Windower profile box, and adds or updates these two entries in that profile section:`r`n`r`n<args>--server login.supernovaffxi.com</args>`r`n<executable>xiloader.exe</executable>" },
        [pscustomobject]@{ Title = '19. Launch Windower profile and create account'; Body = 'Manual step: launch Windower with your chosen profile. When xiloader opens, create your Supernova account, then return here and click Next Step.' },
        [pscustomobject]@{ Title = '20. Add Windower login args'; Body = "Optional automated step: if you want Windower to remember your username and password, enter them in the Windower Login box and click Update Windower Args. The assistant backs up settings.xml, finds the profile named in the Windower profile box, and updates it to:`r`n`r`n<args>--server login.supernovaffxi.com --user your_username --password your_password</args>`r`n<executable>xiloader.exe</executable>`r`n`r`nWindower stores these args in settings.xml, so the password is written there in plain text." },
        [pscustomobject]@{ Title = '21. Validate'; Body = 'Click Validate Setup. Setup is ready only when every item says PASS, including Run as administrator for both pol.exe and xiloader.exe and the Windower profile XML. If you used Update Windower Args, validation also checks for username and password args.' }
    )
    'New Installation - Ashita' = @(
        [pscustomobject]@{ Title = '15. Install and start Ashita'; Body = 'Manual step: run the Ashita executable you downloaded and let it install. Ashita will automatically open after installation. When it finishes, use the Ashita folder Browse button under Selected Paths to select the main Ashita folder that contains ashita-cli.exe.' },
        [pscustomobject]@{ Title = '16. Install Ashita xiloader bootloader'; Body = 'Automated step: click Install Ashita Bootloader. The assistant downloads xiloader v2.0.1 from the LandSandBoat/xiloader release, verifies it, backs up any existing Ashita bootloader, and pastes xiloader.exe into the ffxi-bootmod folder inside the main Ashita folder.' },
        [pscustomobject]@{ Title = '17. Configure Ashita Supernova entry'; Body = "Automated step: click Configure Ashita. The assistant backs up or writes config\\boot\\supernova.ini so the file points at the new ffxi-bootmod\\xiloader.exe and Command is:`r`n`r`n--server login.supernovaffxi.com`r`n`r`nManual fallback: in Ashita, right-click the topmost profile and select Edit Configuration. Click the three dotted button next to the File text box. In the file popup, change the file type to Executable Files (*.exe), select xiloader.exe from the ffxi-bootmod folder, and make sure Command is --server login.supernovaffxi.com." },
        [pscustomobject]@{ Title = '18. Create Ashita desktop shortcut'; Body = 'Manual step: in Ashita, right-click the profile and select Create Desktop Shortcut to make a direct launch shortcut to that profile on your desktop. When the shortcut is created, return here and click Next Step.' },
        [pscustomobject]@{ Title = '19. Launch Ashita profile and create account'; Body = 'Manual step: launch the selected profile by clicking the arrow to the right of the profile name. Create your new Supernova account in game, then return here and click Next Step.' },
        [pscustomobject]@{ Title = '20. Add Ashita account command'; Body = "Automated step: enter the username and password you created in the Ashita Login box, then click Update Ashita Command. The assistant backs up supernova.ini and replaces the Command section with:`r`n`r`n--server login.supernovaffxi.com --user your_username --password your_password`r`n`r`nAshita stores this command in its profile config, so the password is written there in plain text." },
        [pscustomobject]@{ Title = '21. Validate'; Body = 'Click Validate Setup. Setup is ready only when every item says PASS, including Run as administrator for both pol.exe and xiloader.exe, the Ashita ffxi-bootmod bootloader, and the Ashita Supernova config with username and password command.' }
    )
    'Existing Installation' = @(
        [pscustomobject]@{ Title = '1. Select folders'; Body = 'Detect or browse to your PlayOnlineViewer folder with pol.exe and your FINAL FANTASY XI folder with ROM, ROM3, ROM4, and sound4.' },
        [pscustomobject]@{ Title = '2. Install required runtime and xiloader'; Body = 'Click Install MSVC x86 if validation says the runtime is missing, then click Install xiloader. The assistant downloads pinned xiloader v2.0.1 and places xiloader.exe in the same PlayOnlineViewer folder where pol.exe lives.' },
        [pscustomobject]@{ Title = '3. Set pol.exe and xiloader.exe to run as administrator'; Body = 'Manual step: click Open POL Folder, then right-click pol.exe and xiloader.exe one at a time. For each file, use Properties > Compatibility > Run this program as an administrator. The assistant validates both flags before setup is complete.' },
        [pscustomobject]@{ Title = '4. Install Supernova files'; Body = 'Click Install Patch Files, then Install Supernova DATs. Both steps back up files before replacing them.' },
        [pscustomobject]@{ Title = '5. Configure Windower or Ashita'; Body = 'Choose the required play method and configure it for Supernova.' },
        [pscustomobject]@{ Title = '6. Validate'; Body = 'Click Validate Setup. Setup is ready only when every item says PASS.' }
    )
    'Repair / Update Existing Installation' = @(
        [pscustomobject]@{ Title = '1. Confirm repair'; Body = 'This flow moves VTABLE.DAT out of the FFXI folder with a backup, then opens PlayOnline for manual file repair.' },
        [pscustomobject]@{ Title = '2. Run PlayOnline repair'; Body = 'In PlayOnline Viewer, choose Check Files > FINAL FANTASY XI > File Repair. Close PlayOnline when finished.' },
        [pscustomobject]@{ Title = '3. Reapply Supernova files'; Body = 'After PlayOnline repair, click Install Patch Files, then Install Supernova DATs.' },
        [pscustomobject]@{ Title = '4. Revalidate'; Body = 'Click Validate Setup. Setup is ready only when xiloader, Supernova files, and Windower/Ashita configuration all say PASS.' }
    )
}

$settings = Load-Settings
$script:CurrentMode = $settings.Mode
$script:CurrentSteps = @()

# Main form and top-level layout.
$form = New-Object System.Windows.Forms.Form
$form.Text = $script:AppName
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(1040, 860)
$form.MinimumSize = New-Object System.Drawing.Size(1000, 840)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$modeGroup = New-Object System.Windows.Forms.GroupBox
$modeGroup.Text = 'Setup Mode'
$modeGroup.Location = New-Object System.Drawing.Point(12, 12)
$modeGroup.Size = New-Object System.Drawing.Size(260, 130)
$form.Controls.Add($modeGroup)

$newButton = New-Object System.Windows.Forms.Button
$newButton.Text = 'New Installation'
$newButton.Location = New-Object System.Drawing.Point(14, 24)
$newButton.Size = New-Object System.Drawing.Size(220, 28)
$modeGroup.Controls.Add($newButton)

$existingButton = New-Object System.Windows.Forms.Button
$existingButton.Text = 'Existing Installation'
$existingButton.Location = New-Object System.Drawing.Point(14, 58)
$existingButton.Size = New-Object System.Drawing.Size(220, 28)
$modeGroup.Controls.Add($existingButton)

$repairButton = New-Object System.Windows.Forms.Button
$repairButton.Text = 'Repair / Update'
$repairButton.Location = New-Object System.Drawing.Point(14, 92)
$repairButton.Size = New-Object System.Drawing.Size(220, 28)
$modeGroup.Controls.Add($repairButton)

$stepsList = New-Object System.Windows.Forms.ListBox
$stepsList.Location = New-Object System.Drawing.Point(12, 152)
$stepsList.Size = New-Object System.Drawing.Size(260, 205)
$form.Controls.Add($stepsList)

$stepTitle = New-Object System.Windows.Forms.Label
$stepTitle.Location = New-Object System.Drawing.Point(290, 14)
$stepTitle.Size = New-Object System.Drawing.Size(700, 26)
$stepTitle.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($stepTitle)

$stepText = New-Object System.Windows.Forms.TextBox
$stepText.Multiline = $true
$stepText.ReadOnly = $true
$stepText.ScrollBars = 'Vertical'
$stepText.Location = New-Object System.Drawing.Point(290, 44)
$stepText.Size = New-Object System.Drawing.Size(710, 96)
$form.Controls.Add($stepText)

$pathsGroup = New-Object System.Windows.Forms.GroupBox
$pathsGroup.Text = 'Selected Paths'
$pathsGroup.Location = New-Object System.Drawing.Point(290, 152)
$pathsGroup.Size = New-Object System.Drawing.Size(710, 220)
$form.Controls.Add($pathsGroup)

# Reusable path row builder. It creates a label, textbox, and browse button, then
# resolves the selected path according to the expected folder/file type.
function Add-PathRow {
    param([System.Windows.Forms.Control]$Parent, [string]$Label, [string]$Value, [int]$Y, [string]$Kind)
    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $Label
    $lbl.Location = New-Object System.Drawing.Point(12, $Y)
    $lbl.Size = New-Object System.Drawing.Size(150, 22)
    $Parent.Controls.Add($lbl)

    $box = New-Object System.Windows.Forms.TextBox
    $box.Text = $Value
    $box.Location = New-Object System.Drawing.Point(166, $Y)
    $box.Size = New-Object System.Drawing.Size(430, 22)
    $Parent.Controls.Add($box)

    $browse = New-Object System.Windows.Forms.Button
    $browse.Text = 'Browse'
    $browse.Location = New-Object System.Drawing.Point(606, $Y - 2)
    $browse.Size = New-Object System.Drawing.Size(78, 26)
    $Parent.Controls.Add($browse)

    $browse.Add_Click({
        if ($Kind -eq 'windower-exe') {
            $chosen = Browse-File -Title 'Select Windower.exe' -CurrentPath $box.Text -Filter 'Windower.exe|Windower.exe|Executable files (*.exe)|*.exe|All files (*.*)|*.*'
        }
        elseif ($Kind -eq 'windower-settings') {
            $chosen = Browse-File -Title 'Select Windower settings.xml' -CurrentPath $box.Text -Filter 'settings.xml|settings.xml|XML files (*.xml)|*.xml|All files (*.*)|*.*'
        }
        else {
            $chosen = Browse-Folder -Description $Label -CurrentPath $box.Text
        }
        if ($chosen) {
            if ($Kind -eq 'game-root') {
                Apply-GameInstallFolder -Path $chosen
            }
            elseif ($Kind -eq 'pol-folder') {
                $chosen = Get-ResolvedPlayOnlineFolder -Path $chosen
                $box.Text = $chosen
            }
            elseif ($Kind -eq 'ffxi-folder') {
                $chosen = Get-ResolvedFfxiFolder -Path $chosen
                $box.Text = $chosen
            }
            else {
                $box.Text = $chosen
            }
            Save-Settings
            [void](Show-Validation)
        }
    })
    return $box
}

$gameRootBox = Add-PathRow -Parent $pathsGroup -Label 'Game install folder' -Value $settings.GameInstallFolder -Y 24 -Kind 'game-root'
$polBox = Add-PathRow -Parent $pathsGroup -Label 'PlayOnlineViewer' -Value $settings.PlayOnlineFolder -Y 54 -Kind 'pol-folder'
$ffxiBox = Add-PathRow -Parent $pathsGroup -Label 'FINAL FANTASY XI' -Value $settings.FfxiFolder -Y 84 -Kind 'ffxi-folder'
$windowerExeBox = Add-PathRow -Parent $pathsGroup -Label 'Windower.exe' -Value $settings.WindowerExe -Y 114 -Kind 'windower-exe'
$windowerSettingsBox = Add-PathRow -Parent $pathsGroup -Label 'Windower settings.xml' -Value $settings.WindowerSettings -Y 144 -Kind 'windower-settings'
$ashitaFolderBox = Add-PathRow -Parent $pathsGroup -Label 'Ashita folder' -Value $settings.AshitaFolder -Y 174 -Kind 'ashita-folder'

# Required launcher choice and profile/login fields.
$launcherGroup = New-Object System.Windows.Forms.GroupBox
$launcherGroup.Text = 'Required Play Method'
$launcherGroup.Location = New-Object System.Drawing.Point(12, 370)
$launcherGroup.Size = New-Object System.Drawing.Size(260, 82)
$form.Controls.Add($launcherGroup)

$windowerRadio = New-Object System.Windows.Forms.RadioButton
$windowerRadio.Text = 'Windower (Recommended)'
$windowerRadio.Location = New-Object System.Drawing.Point(16, 24)
$windowerRadio.Size = New-Object System.Drawing.Size(158, 22)
$windowerRadio.Checked = ($settings.SelectedLauncher -ne 'Ashita')
$launcherGroup.Controls.Add($windowerRadio)

$ashitaRadio = New-Object System.Windows.Forms.RadioButton
$ashitaRadio.Text = 'Ashita'
$ashitaRadio.Location = New-Object System.Drawing.Point(182, 24)
$ashitaRadio.Size = New-Object System.Drawing.Size(68, 22)
$ashitaRadio.Checked = ($settings.SelectedLauncher -eq 'Ashita')
$launcherGroup.Controls.Add($ashitaRadio)

$profileLabel = New-Object System.Windows.Forms.Label
$profileLabel.Text = 'Windower profile'
$profileLabel.Location = New-Object System.Drawing.Point(16, 52)
$profileLabel.Size = New-Object System.Drawing.Size(105, 20)
$launcherGroup.Controls.Add($profileLabel)

$windowerProfileBox = New-Object System.Windows.Forms.TextBox
$windowerProfileBox.Text = $settings.WindowerProfile
$windowerProfileBox.Location = New-Object System.Drawing.Point(126, 50)
$windowerProfileBox.Size = New-Object System.Drawing.Size(112, 22)
$launcherGroup.Controls.Add($windowerProfileBox)

$windowerAccountGroup = New-Object System.Windows.Forms.GroupBox
$windowerAccountGroup.Text = 'Windower Login'
$windowerAccountGroup.Location = New-Object System.Drawing.Point(12, 464)
$windowerAccountGroup.Size = New-Object System.Drawing.Size(260, 134)
$windowerAccountGroup.Visible = $false
$form.Controls.Add($windowerAccountGroup)

$windowerUsernameLabel = New-Object System.Windows.Forms.Label
$windowerUsernameLabel.Text = 'Username'
$windowerUsernameLabel.Location = New-Object System.Drawing.Point(16, 28)
$windowerUsernameLabel.Size = New-Object System.Drawing.Size(74, 20)
$windowerAccountGroup.Controls.Add($windowerUsernameLabel)

$windowerUsernameBox = New-Object System.Windows.Forms.TextBox
$windowerUsernameBox.Text = $settings.WindowerUsername
$windowerUsernameBox.Location = New-Object System.Drawing.Point(96, 26)
$windowerUsernameBox.Size = New-Object System.Drawing.Size(144, 22)
$windowerAccountGroup.Controls.Add($windowerUsernameBox)

$windowerPasswordLabel = New-Object System.Windows.Forms.Label
$windowerPasswordLabel.Text = 'Password'
$windowerPasswordLabel.Location = New-Object System.Drawing.Point(16, 58)
$windowerPasswordLabel.Size = New-Object System.Drawing.Size(74, 20)
$windowerAccountGroup.Controls.Add($windowerPasswordLabel)

$windowerPasswordBox = New-Object System.Windows.Forms.TextBox
$windowerPasswordBox.Location = New-Object System.Drawing.Point(96, 56)
$windowerPasswordBox.Size = New-Object System.Drawing.Size(144, 22)
$windowerPasswordBox.UseSystemPasswordChar = $true
$windowerAccountGroup.Controls.Add($windowerPasswordBox)

$windowerPasswordNote = New-Object System.Windows.Forms.Label
$windowerPasswordNote.Text = 'Password is written to settings.xml when you update the args.'
$windowerPasswordNote.Location = New-Object System.Drawing.Point(16, 86)
$windowerPasswordNote.Size = New-Object System.Drawing.Size(226, 38)
$windowerAccountGroup.Controls.Add($windowerPasswordNote)

$ashitaAccountGroup = New-Object System.Windows.Forms.GroupBox
$ashitaAccountGroup.Text = 'Ashita Login'
$ashitaAccountGroup.Location = New-Object System.Drawing.Point(12, 464)
$ashitaAccountGroup.Size = New-Object System.Drawing.Size(260, 134)
$ashitaAccountGroup.Visible = $false
$form.Controls.Add($ashitaAccountGroup)

$ashitaUsernameLabel = New-Object System.Windows.Forms.Label
$ashitaUsernameLabel.Text = 'Username'
$ashitaUsernameLabel.Location = New-Object System.Drawing.Point(16, 28)
$ashitaUsernameLabel.Size = New-Object System.Drawing.Size(74, 20)
$ashitaAccountGroup.Controls.Add($ashitaUsernameLabel)

$ashitaUsernameBox = New-Object System.Windows.Forms.TextBox
$ashitaUsernameBox.Text = $settings.AshitaUsername
$ashitaUsernameBox.Location = New-Object System.Drawing.Point(96, 26)
$ashitaUsernameBox.Size = New-Object System.Drawing.Size(144, 22)
$ashitaAccountGroup.Controls.Add($ashitaUsernameBox)

$ashitaPasswordLabel = New-Object System.Windows.Forms.Label
$ashitaPasswordLabel.Text = 'Password'
$ashitaPasswordLabel.Location = New-Object System.Drawing.Point(16, 58)
$ashitaPasswordLabel.Size = New-Object System.Drawing.Size(74, 20)
$ashitaAccountGroup.Controls.Add($ashitaPasswordLabel)

$ashitaPasswordBox = New-Object System.Windows.Forms.TextBox
$ashitaPasswordBox.Location = New-Object System.Drawing.Point(96, 56)
$ashitaPasswordBox.Size = New-Object System.Drawing.Size(144, 22)
$ashitaPasswordBox.UseSystemPasswordChar = $true
$ashitaAccountGroup.Controls.Add($ashitaPasswordBox)

$ashitaPasswordNote = New-Object System.Windows.Forms.Label
$ashitaPasswordNote.Text = 'Password is written to Ashita config when you update the command.'
$ashitaPasswordNote.Location = New-Object System.Drawing.Point(16, 86)
$ashitaPasswordNote.Size = New-Object System.Drawing.Size(226, 38)
$ashitaAccountGroup.Controls.Add($ashitaPasswordNote)

# Action buttons. These either open official/manual resources or call the modular
# helper scripts for file/config changes.
$actionsGroup = New-Object System.Windows.Forms.GroupBox
$actionsGroup.Text = 'Actions'
$actionsGroup.Location = New-Object System.Drawing.Point(290, 384)
$actionsGroup.Size = New-Object System.Drawing.Size(710, 226)
$form.Controls.Add($actionsGroup)

function Add-ActionButton {
    param([string]$Text, [int]$X, [int]$Y)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size(160, 30)
    $actionsGroup.Controls.Add($button)
    return $button
}

$officialButton = Add-ActionButton -Text 'Open FFXI Download' -X 14 -Y 24
$detectButton = Add-ActionButton -Text 'Detect Paths' -X 184 -Y 24
$polButton = Add-ActionButton -Text 'Open PlayOnline' -X 354 -Y 24
$repairPrepButton = Add-ActionButton -Text 'Prepare File Repair' -X 524 -Y 24
$installPatchButton = Add-ActionButton -Text 'Install Patch Files' -X 14 -Y 64
$installMsvcButton = Add-ActionButton -Text 'Install MSVC x86' -X 184 -Y 64
$installDatsButton = Add-ActionButton -Text 'Install Supernova DATs' -X 354 -Y 64
$deleteVulgarButton = Add-ActionButton -Text 'Optional: Delete vulgar2.dic' -X 524 -Y 64
$installXiloaderButton = Add-ActionButton -Text 'Install xiloader' -X 14 -Y 104
$configureWindowerButton = Add-ActionButton -Text 'Configure Windower' -X 184 -Y 104
$configureAshitaButton = Add-ActionButton -Text 'Configure Ashita' -X 354 -Y 104
$validateButton = Add-ActionButton -Text 'Validate Setup' -X 524 -Y 104
$diagnosticButton = Add-ActionButton -Text 'Export Diagnostic' -X 14 -Y 144
$openPolFolderButton = Add-ActionButton -Text 'Open POL Folder' -X 184 -Y 144
$windowerWebsiteButton = Add-ActionButton -Text 'Open Windower Website' -X 354 -Y 144
$ashitaWebsiteButton = Add-ActionButton -Text 'Open Ashita Website' -X 524 -Y 144
$openWindowerButton = Add-ActionButton -Text 'Open Windower' -X 14 -Y 184
$installAshitaBootloaderButton = Add-ActionButton -Text 'Install Ashita Bootloader' -X 184 -Y 184
$updateAshitaCommandButton = Add-ActionButton -Text 'Update Ashita Command' -X 354 -Y 184
$updateWindowerArgsButton = Add-ActionButton -Text 'Update Windower Args' -X 524 -Y 184
$advancedXiloaderButton = Add-ActionButton -Text 'Support: xiloader' -X 354 -Y 104
$advancedXiloaderButton.Visible = $false

$resultBox = New-Object System.Windows.Forms.TextBox
$resultBox.Multiline = $true
$resultBox.ReadOnly = $true
$resultBox.ScrollBars = 'Vertical'
$resultBox.Location = New-Object System.Drawing.Point(12, 626)
$resultBox.Size = New-Object System.Drawing.Size(570, 150)
$form.Controls.Add($resultBox)

$stepImageLabel = New-Object System.Windows.Forms.Label
$stepImageLabel.Text = 'Guide image for this step'
$stepImageLabel.Location = New-Object System.Drawing.Point(610, 606)
$stepImageLabel.Size = New-Object System.Drawing.Size(390, 18)
$stepImageLabel.Visible = $false
$form.Controls.Add($stepImageLabel)

$stepImageBox = New-Object System.Windows.Forms.PictureBox
$stepImageBox.Location = New-Object System.Drawing.Point(610, 626)
$stepImageBox.Size = New-Object System.Drawing.Size(390, 150)
$stepImageBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$stepImageBox.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$stepImageBox.Visible = $false
$form.Controls.Add($stepImageBox)

# Wizard navigation buttons.
$backButton = New-Object System.Windows.Forms.Button
$backButton.Text = 'Back'
$backButton.Location = New-Object System.Drawing.Point(820, 790)
$backButton.Size = New-Object System.Drawing.Size(80, 28)
$form.Controls.Add($backButton)

$nextButton = New-Object System.Windows.Forms.Button
$nextButton.Text = 'Next Step ->'
$nextButton.Location = New-Object System.Drawing.Point(890, 790)
$nextButton.Size = New-Object System.Drawing.Size(110, 28)
$form.Controls.Add($nextButton)

# UI event wiring. Each handler validates inputs before launching helpers and
# reports results back through the status box/message dialogs.
$newButton.Add_Click({ Set-Mode 'New Installation' })
$existingButton.Add_Click({ Set-Mode 'Existing Installation' })
$repairButton.Add_Click({ Set-Mode 'Repair / Update Existing Installation' })
$stepsList.Add_SelectedIndexChanged({ Update-StepView })
$backButton.Add_Click({ if ($stepsList.SelectedIndex -gt 0) { $stepsList.SelectedIndex-- } })
$nextButton.Add_Click({ if ($stepsList.SelectedIndex -lt ($stepsList.Items.Count - 1)) { $stepsList.SelectedIndex++ } })
$windowerRadio.Add_CheckedChanged({
    if ($windowerRadio.Checked) {
        Save-Settings
        if ($script:CurrentMode -eq 'New Installation') { Update-StepList }
    }
})
$ashitaRadio.Add_CheckedChanged({
    if ($ashitaRadio.Checked) {
        Save-Settings
        if ($script:CurrentMode -eq 'New Installation') { Update-StepList }
    }
})

$officialButton.Add_Click({
    try {
        Start-Process $script:OfficialFfxiInstallUrl
        $resultBox.Text = "Official Square Enix download page opened:`r`n$script:OfficialFfxiInstallUrl`r`n`r`nManual step: download and install PlayOnline Viewer and FINAL FANTASY XI, then return to this assistant."
    }
    catch {
        Show-Error "Could not open the official FFXI download page. Open this link manually:`r`n$script:OfficialFfxiInstallUrl`r`n`r`n$($_.Exception.Message)"
    }
})
$windowerWebsiteButton.Add_Click({
    try {
        $windowerRadio.Checked = $true
        Save-Settings
        Start-Process $script:WindowerUrl
        $resultBox.Text = "Windower selected and website opened:`r`n$script:WindowerUrl`r`n`r`nManual step: download Windower and run the downloaded executable yourself.`r`n`r`nNOTE: WINDOWER WILL INSTALL INTO WHATEVER DIRECTORY YOU PLACE THE DOWNLOADED EXECUTABLE FROM."
    }
    catch {
        Show-Error "Could not open the Windower website. Open this link manually:`r`n$script:WindowerUrl`r`n`r`n$($_.Exception.Message)"
    }
})
$ashitaWebsiteButton.Add_Click({
    try {
        $ashitaRadio.Checked = $true
        Save-Settings
        Start-Process $script:AshitaUrl
        $resultBox.Text = "Ashita selected and website opened:`r`n$script:AshitaUrl`r`n`r`nManual step: download Ashita and run the downloaded executable yourself.`r`n`r`nNOTE: ASHITA WILL INSTALL INTO WHATEVER DIRECTORY YOU PLACE THE DOWNLOADED EXECUTABLE FROM."
    }
    catch {
        Show-Error "Could not open the Ashita website. Open this link manually:`r`n$script:AshitaUrl`r`n`r`n$($_.Exception.Message)"
    }
})
$detectButton.Add_Click({ try { Detect-Paths } catch { Show-Error $_.Exception.Message } })
$polButton.Add_Click({
    try {
        $polFolder = Ensure-PlayOnlineFolder
        $pol = Join-Path $polFolder 'pol.exe'
        if (-not (Test-Path -LiteralPath $pol -PathType Leaf)) { throw "pol.exe not found: $pol" }
        Start-Process -FilePath $pol -WorkingDirectory $polFolder | Out-Null
        $resultBox.Text = "PlayOnline Viewer opened.`r`nRun updates or Check Files manually. This assistant will not click through PlayOnline for you."
    }
    catch { Show-Error $_.Exception.Message }
})

$openPolFolderButton.Add_Click({
    try {
        $polFolder = Ensure-PlayOnlineFolder
        Start-Process -FilePath 'explorer.exe' -ArgumentList (Quote-Argument $polFolder) | Out-Null
        $resultBox.Text = "PlayOnlineViewer folder opened:`r`n$polFolder`r`n`r`nManual step: set both pol.exe and xiloader.exe to Run as administrator from Properties > Compatibility."
    }
    catch { Show-Error $_.Exception.Message }
})

$openWindowerButton.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $windowerExeBox.Text -PathType Leaf)) {
            throw "Select Windower.exe first. Use the Windower.exe Browse button under Selected Paths."
        }
        if ([System.IO.Path]::GetFileName($windowerExeBox.Text) -ne 'Windower.exe') {
            throw "The Windower path must point to Windower.exe. Current value: $($windowerExeBox.Text)"
        }

        $windowerRadio.Checked = $true
        Save-Settings
        $windowerFolder = Split-Path -Parent $windowerExeBox.Text
        Start-Process -FilePath $windowerExeBox.Text -WorkingDirectory $windowerFolder | Out-Null
        $resultBox.Text = "Windower opened:`r`n$($windowerExeBox.Text)`r`n`r`nManual step: create or edit the Supernova profile in Windower."
    }
    catch { Show-Error $_.Exception.Message }
})

$repairPrepButton.Add_Click({
    try {
        $ffxiFolder = Ensure-FfxiFolder
        $polFolder = Ensure-PlayOnlineFolder
        if (-not (Confirm-Action "This will move VTABLE.DAT out of:`r`n$ffxiFolder`r`n`r`nThe file is moved into a backup folder first. After that, PlayOnline Viewer opens so you can run Check Files > FINAL FANTASY XI > File Repair yourself. Continue?")) { return }
        Save-Settings
        Invoke-Helper -ScriptName 'RepairSupernovaClient.ps1' -FriendlyName 'Repair preparation' -ElevationPath $ffxiFolder -Arguments @{
            FfxiFolder = $ffxiFolder
            PlayOnlineFolder = $polFolder
        } | Out-Null
        Start-Process -FilePath (Join-Path $polFolder 'pol.exe') -WorkingDirectory $polFolder | Out-Null
        $resultBox.Text = "Repair prep complete.`r`n`r`nIn PlayOnline Viewer:`r`n1. Choose Check Files.`r`n2. Select FINAL FANTASY XI.`r`n3. Run File Repair.`r`n4. Close PlayOnline when complete.`r`n5. Click Install Patch Files, then Install Supernova DATs here to reapply Supernova files."
    }
    catch { Show-Error $_.Exception.Message }
})

$installXiloaderButton.Add_Click({
    try {
        $polFolder = Ensure-PlayOnlineFolder
        Save-Settings
        Invoke-Helper -ScriptName 'InstallXiloader.ps1' -FriendlyName 'xiloader install' -ElevationPath $polFolder -Arguments @{ PlayOnlineFolder = $polFolder } | Out-Null
        [void](Show-Validation)
        Show-Info 'xiloader install/verify finished. xiloader.exe should now be beside pol.exe. Click Next Step to continue.'
    }
    catch { Show-Error $_.Exception.Message }
})

$installPatchButton.Add_Click({
    try {
        $ffxiFolder = Ensure-FfxiFolder
        if (-not (Confirm-Action "This will download the Supernova patch files, then copy them into:`r`n$ffxiFolder`r`n`r`nExisting files that would be replaced are backed up first. Continue?")) { return }
        Save-Settings
        Invoke-Helper -ScriptName 'ApplySupernovaPatch.ps1' -FriendlyName 'Supernova patch file install' -ElevationPath $ffxiFolder -Arguments @{
            FfxiFolder = $ffxiFolder
            InstallSelection = 'RootPatch'
        } | Out-Null
        [void](Show-Validation)
        Show-Info 'Supernova patch file step finished. Click Next Step to continue.'
    }
    catch { Show-Error $_.Exception.Message }
})

$installDatsButton.Add_Click({
    try {
        $ffxiFolder = Ensure-FfxiFolder
        if (-not (Confirm-Action "This will download the Supernova custom DATs, then copy them into:`r`n$ffxiFolder`r`n`r`nExisting files that would be replaced are backed up first. Folder paths such as ROM, ROM3, ROM4, and sound4 are preserved. Continue?")) { return }
        Save-Settings
        Invoke-Helper -ScriptName 'ApplySupernovaPatch.ps1' -FriendlyName 'Supernova custom DAT install' -ElevationPath $ffxiFolder -Arguments @{
            FfxiFolder = $ffxiFolder
            InstallSelection = 'CustomDats'
        } | Out-Null
        [void](Show-Validation)
        Show-Info 'Supernova DAT step finished. Click Next Step to continue.'
    }
    catch { Show-Error $_.Exception.Message }
})

$deleteVulgarButton.Add_Click({
    try {
        $ffxiFolder = Ensure-FfxiFolder
        if (-not (Confirm-Action "Optional cleanup: this will search only inside your selected FINAL FANTASY XI folder for vulgar2.dic:`r`n$ffxiFolder`r`n`r`nAny vulgar2.dic file found there will be backed up under LocalAppData before it is deleted from the game folder. Continue?")) { return }
        Save-Settings
        Invoke-Helper -ScriptName 'RemoveVulgarDictionary.ps1' -FriendlyName 'optional vulgar2.dic cleanup' -ElevationPath $ffxiFolder -Arguments @{
            FfxiFolder = $ffxiFolder
        } | Out-Null
        $resultBox.Text = "Optional vulgar2.dic cleanup finished.`r`nBackup/log folder:`r`n%LOCALAPPDATA%\SupernovaSetupAssistant"
        Show-Info 'Optional vulgar2.dic cleanup finished. The file was backed up first if it was found.'
    }
    catch { Show-Error $_.Exception.Message }
})

$installMsvcButton.Add_Click({
    try {
        $status = Get-Msvc2015RuntimeX86Status
        if ($status.Installed) {
            [void](Show-Validation)
            Show-Info "Microsoft Visual C++ 2015 x86 runtime is already installed.`r`nVersion: $($status.Version)`r`nSource: $($status.Source)"
            return
        }

        if (-not (Confirm-Action "This will download and install Microsoft Visual C++ Redistributable 2015 x86 from Microsoft:`r`n$script:Msvc2015RuntimeUrl`r`n`r`nWindows will ask for administrator approval because this installs a system runtime. It does not change your FFXI or PlayOnline files. Continue?")) { return }
        Save-Settings
        Invoke-Helper -ScriptName 'InstallMsvc2015Runtime.ps1' -FriendlyName 'Microsoft Visual C++ 2015 x86 runtime install' -ForceElevation -ElevationReason 'install a Microsoft runtime into Windows' -Arguments @{} | Out-Null
        [void](Show-Validation)
        Show-Info 'Microsoft Visual C++ 2015 x86 runtime install/verify finished. Click Next Step to continue.'
    }
    catch { Show-Error $_.Exception.Message }
})

$installAshitaBootloaderButton.Add_Click({
    try {
        Ensure-AshitaInputs
        $ashitaRadio.Checked = $true
        Save-Settings
        Invoke-Helper -ScriptName 'InstallAshitaBootloader.ps1' -FriendlyName 'Ashita xiloader bootloader install' -ElevationPath $ashitaFolderBox.Text -Arguments @{
            AshitaFolder = $ashitaFolderBox.Text
        } | Out-Null
        [void](Show-Validation)
        Show-Info 'Ashita xiloader bootloader install/verify finished. Click Next Step to continue.'
    }
    catch { Show-Error $_.Exception.Message }
})

$configureWindowerButton.Add_Click({
    try {
        Ensure-WindowerInputs
        [void](Ensure-XiloaderInstalled)
        Save-Settings
        if (-not (Test-WindowerProfileExists)) {
            Show-Info "Create a Windower profile named '$($windowerProfileBox.Text)' in Windower first, then come back and click Configure Windower again. This assistant will then back up settings.xml and set the profile to use xiloader.exe with the Supernova server argument."
            return
        }
        Invoke-Helper -ScriptName 'ConfigureWindower.ps1' -FriendlyName 'Windower configuration' -ElevationPath (Split-Path -Parent $windowerSettingsBox.Text) -Arguments @{
            SettingsXmlPath = $windowerSettingsBox.Text
            ProfileName = $windowerProfileBox.Text
            XiloaderArgs = "--server $script:ServerHost"
        } | Out-Null
        $windowerRadio.Checked = $true
        [void](Show-Validation)
        Show-Info 'Windower configuration finished. Click Validate Setup and make sure every item says PASS.'
    }
    catch { Show-Error $_.Exception.Message }
})

$updateWindowerArgsButton.Add_Click({
    try {
        Ensure-WindowerAccountInputs
        [void](Ensure-XiloaderInstalled)
        if (-not (Test-WindowerProfileExists)) {
            Show-Info "Create a Windower profile named '$($windowerProfileBox.Text)' in Windower first, then come back and click Update Windower Args again. This assistant will then back up settings.xml and update the profile args with the Supernova server, username, and password."
            return
        }

        $username = $windowerUsernameBox.Text.Trim()
        $password = $windowerPasswordBox.Text
        $args = "--server $script:ServerHost --user $username --password $password"
        $windowerRadio.Checked = $true
        Save-Settings
        Invoke-Helper -ScriptName 'ConfigureWindower.ps1' -FriendlyName 'Windower login args update' -ElevationPath (Split-Path -Parent $windowerSettingsBox.Text) -Arguments @{
            SettingsXmlPath = $windowerSettingsBox.Text
            ProfileName = $windowerProfileBox.Text
            XiloaderArgs = $args
        } | Out-Null
        [void](Show-Validation)
        Show-Info 'Windower args updated. Click Validate Setup and make sure every item says PASS.'
    }
    catch { Show-Error $_.Exception.Message }
})

$configureAshitaButton.Add_Click({
    try {
        Ensure-AshitaInputs
        $ashitaRadio.Checked = $true
        Save-Settings
        Invoke-Helper -ScriptName 'ConfigureAshita.ps1' -FriendlyName 'Ashita configuration' -ElevationPath $ashitaFolderBox.Text -Arguments @{
            AshitaFolder = $ashitaFolderBox.Text
            ConfigName = 'supernova.ini'
            XiloaderArgs = "--server $script:ServerHost"
        } | Out-Null
        [void](Show-Validation)
        Show-Info 'Ashita configuration finished. Click Validate Setup and make sure every item says PASS.'
    }
    catch { Show-Error $_.Exception.Message }
})

$updateAshitaCommandButton.Add_Click({
    try {
        Ensure-AshitaAccountInputs
        $username = $ashitaUsernameBox.Text.Trim()
        $password = $ashitaPasswordBox.Text
        $command = "--server $script:ServerHost --user $username --password $password"
        $ashitaRadio.Checked = $true
        Save-Settings
        Invoke-Helper -ScriptName 'ConfigureAshita.ps1' -FriendlyName 'Ashita account command update' -ElevationPath $ashitaFolderBox.Text -Arguments @{
            AshitaFolder = $ashitaFolderBox.Text
            ConfigName = 'supernova.ini'
            XiloaderArgs = $command
        } | Out-Null
        [void](Show-Validation)
        Show-Info 'Ashita command updated. Click Validate Setup and make sure every item says PASS.'
    }
    catch { Show-Error $_.Exception.Message }
})

$validateButton.Add_Click({
    try {
        Save-Settings
        $complete = Show-Validation
        if ($complete) {
            Show-Info 'Validation passed. Setup is ready. Start the game through the configured Windower or Ashita profile.'
        }
        else {
            Show-Info 'Setup is not ready yet. Review the MISSING items in the results box.'
        }
    }
    catch { Show-Error $_.Exception.Message }
})

$diagnosticButton.Add_Click({
    try {
        Save-Settings
        $output = Invoke-Helper -ScriptName 'ExportSupernovaDiagnostics.ps1' -FriendlyName 'Diagnostic export' -CaptureOutput -Arguments @{
            GameInstallFolder = $gameRootBox.Text
            PlayOnlineFolder = $polBox.Text
            FfxiFolder = $ffxiBox.Text
            WindowerExe = $windowerExeBox.Text
            WindowerSettings = $windowerSettingsBox.Text
            WindowerProfile = $windowerProfileBox.Text
            AshitaFolder = $ashitaFolderBox.Text
            SelectedLauncher = if ($windowerRadio.Checked) { 'Windower' } else { 'Ashita' }
        }
        $resultBox.Text = "Diagnostic report written:`r`n$output"
    }
    catch { Show-Error $_.Exception.Message }
})

$advancedXiloaderButton.Add_Click({
    try {
        [void](Ensure-XiloaderInstalled)
        if (-not (Confirm-Action "Advanced support only. Supernova players should normally launch through Windower or Ashita. Start xiloader directly anyway?")) { return }
        $xiloader = Join-Path $polBox.Text 'xiloader.exe'
        if (-not (Test-Path -LiteralPath $xiloader -PathType Leaf)) { throw "xiloader.exe not found: $xiloader" }
        Start-Process -FilePath $xiloader -ArgumentList "--server $script:ServerHost" -WorkingDirectory $polBox.Text | Out-Null
    }
    catch { Show-Error $_.Exception.Message }
})

$form.Add_FormClosing({
    if ($stepImageBox.Image) {
        $stepImageBox.Image.Dispose()
        $stepImageBox.Image = $null
    }
    try { Save-Settings } catch { Write-AssistantLog "Failed to save settings: $($_.Exception.Message)" }
})

# Startup: restore the last mode, run an initial validation, then show the form.
Set-Mode $script:CurrentMode
[void](Show-Validation)

try {
    [System.Windows.Forms.Application]::Run($form)
}
catch {
    Show-Error $_.Exception.Message
}
