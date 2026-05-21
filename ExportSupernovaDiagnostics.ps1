# Writes a plain-text diagnostic report that can be shared for support.
# It does not modify the game install; it only reads paths, hashes, configs, and logs.
param(
    [string]$PlayOnlineFolder = '',
    [string]$FfxiFolder = '',
    [string]$GameInstallFolder = '',
    [string]$WindowerExe = '',
    [string]$WindowerSettings = '',
    [string]$WindowerProfile = 'Supernova',
    [string]$AshitaFolder = '',
    [string]$SelectedLauncher = '',
    [string]$OutputPath = ''
)

# Strict mode keeps the diagnostic export predictable; read failures are handled
# inside individual helper functions so one bad path does not abort the report.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Appends one line to the report buffer.
function Add-Line {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Text = ''
    )
    $Lines.Add($Text) | Out-Null
}

# Summarizes a file without dumping its contents. Hash/version data helps support
# confirm xiloader or patch files without exposing account details.
function Get-FileSummary {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return 'missing'
    }

    $item = Get-Item -LiteralPath $Path
    $md5 = (Get-FileHash -Algorithm MD5 -LiteralPath $Path).Hash
    $version = $item.VersionInfo.FileVersionRaw
    if (-not $version) {
        $version = 'n/a'
    }
    return "present; size=$($item.Length); md5=$md5; fileVersion=$version"
}

# Joins paths only when the base path is present, which keeps missing-path checks
# from throwing noisy errors.
function Join-OptionalPath {
    param([string]$Base, [string]$Child)
    if ([string]::IsNullOrWhiteSpace($Base)) {
        return ''
    }
    return Join-Path $Base $Child
}

# Checks for optional files/folders while safely handling blank base paths.
function Test-OptionalPath {
    param(
        [string]$Base,
        [string]$Child,
        [ValidateSet('Leaf', 'Container')]
        [string]$PathType
    )

    $path = Join-OptionalPath -Base $Base -Child $Child
    if ([string]::IsNullOrWhiteSpace($path)) {
        return $false
    }
    return Test-Path -LiteralPath $path -PathType $PathType
}

# Reads Windows compatibility flags to see whether a file is set to Run as
# administrator.
function Test-RunAsAdminCompatibilityFlag {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
    }
    catch {
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
            continue
        }
    }

    return $false
}

# Converts the Run as administrator registry check into support-friendly text.
function Get-RunAsAdminStatus {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return 'file missing'
    }
    if (Test-RunAsAdminCompatibilityFlag -Path $Path) {
        return 'Run as administrator enabled'
    }
    return 'Run as administrator missing'
}

# Reads Windower settings.xml and reports whether the selected profile points to
# xiloader and the Supernova server. It intentionally reports only whether
# username/password args exist, not the actual password.
function Get-WindowerStatus {
    param([string]$SettingsPath, [string]$ProfileName)
    if ([string]::IsNullOrWhiteSpace($SettingsPath) -or -not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
        return 'settings.xml missing'
    }

    try {
        [xml]$doc = Get-Content -LiteralPath $SettingsPath -Raw
        $profiles = $doc.SelectNodes("//*[local-name()='profile']")
        foreach ($profile in $profiles) {
            $matchesName = $false
            if ($profile.Attributes -and $profile.Attributes['name'] -and $profile.Attributes['name'].Value -eq $ProfileName) {
                $matchesName = $true
            }
            $nameNode = $profile.SelectSingleNode("*[local-name()='name']")
            if ($nameNode -and $nameNode.InnerText -eq $ProfileName) {
                $matchesName = $true
            }
            if ($matchesName) {
                $args = $profile.SelectSingleNode("*[local-name()='args']")
                $exe = $profile.SelectSingleNode("*[local-name()='executable']")
                $exeText = if ($exe) { $exe.InnerText } else { 'missing' }
                $argsText = if ($args) { $args.InnerText } else { 'missing' }
                $usesServer = $argsText -match 'login\.supernovaffxi\.com'
                $usesAccountArgs = ($argsText -match '--user\s+\S+') -and ($argsText -match '--password\s+\S+')
                $serverStatus = if ($usesServer) { 'args include Supernova server' } else { 'args missing Supernova server' }
                $accountStatus = if ($usesAccountArgs) { 'username/password args present' } else { 'username/password args missing' }
                return "profile found; executable=$exeText; $serverStatus; $accountStatus"
            }
        }
        return "profile '$ProfileName' missing"
    }
    catch {
        return "settings.xml read error: $($_.Exception.Message)"
    }
}

# Reads Ashita's Supernova boot config and reports the bootloader/server/account
# command status without printing the saved password.
function Get-AshitaStatus {
    param([string]$Folder)
    if ([string]::IsNullOrWhiteSpace($Folder) -or -not (Test-Path -LiteralPath $Folder -PathType Container)) {
        return 'Ashita folder missing'
    }

    $cli = Join-Path $Folder 'ashita-cli.exe'
    $bootloader = Join-Path $Folder 'ffxi-bootmod\xiloader.exe'
    $config = Join-Path $Folder 'config\boot\supernova.ini'
    $parts = @()
    $parts += if (Test-Path -LiteralPath $cli -PathType Leaf) { 'ashita-cli.exe present' } else { 'ashita-cli.exe missing' }
    $parts += if (Test-Path -LiteralPath $bootloader -PathType Leaf) { 'ffxi-bootmod xiloader.exe present' } else { 'ffxi-bootmod xiloader.exe missing' }
    if (Test-Path -LiteralPath $config -PathType Leaf) {
        $configContent = Get-Content -LiteralPath $config -Raw
        $usesServer = $configContent -match 'login\.supernovaffxi\.com'
        $usesBootloader = $configContent -match [regex]::Escape((Join-Path $Folder 'ffxi-bootmod\xiloader.exe'))
        $usesAccountCommand = ($configContent -match '--user\s+\S+') -and ($configContent -match '--password\s+\S+')
        $parts += if ($usesServer) { 'supernova.ini present with Supernova server' } else { 'supernova.ini present without Supernova server' }
        $parts += if ($usesBootloader) { 'supernova.ini points at ffxi-bootmod xiloader.exe' } else { 'supernova.ini does not point at ffxi-bootmod xiloader.exe' }
        $parts += if ($usesAccountCommand) { 'supernova.ini includes username/password command' } else { 'supernova.ini missing username/password command' }
    }
    else {
        $parts += 'supernova.ini missing'
    }
    return ($parts -join '; ')
}

# Reports whether the optional vulgar2.dic cleanup target still exists.
function Get-VulgarDictionaryStatus {
    param([string]$Folder)
    if ([string]::IsNullOrWhiteSpace($Folder) -or -not (Test-Path -LiteralPath $Folder -PathType Container)) {
        return 'FFXI folder missing'
    }

    try {
        $rootFull = [System.IO.Path]::GetFullPath($Folder).TrimEnd('\') + '\'
        $matches = @(Get-ChildItem -LiteralPath $Folder -Filter 'vulgar2.dic' -File -Recurse -ErrorAction Stop)
        if ($matches.Count -eq 0) {
            return 'not found'
        }

        $relative = @()
        foreach ($match in $matches) {
            $full = [System.IO.Path]::GetFullPath($match.FullName)
            if ($full.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
                $relative += $full.Substring($rootFull.Length)
            }
        }
        return "present; count=$($matches.Count); paths=$($relative -join ', ')"
    }
    catch {
        return "search error: $($_.Exception.Message)"
    }
}

# Reads registry locations used by VC++ 2015 and compatible newer runtimes.
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
                return "installed; version=$version; source=$path"
            }
        }
        catch {
            return "registry read error: $($_.Exception.Message)"
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
            return "installed; version=$version; source=$path"
        }
        catch {
            return "registry read error: $($_.Exception.Message)"
        }
    }

    return 'missing'
}

# Adds a missing-requirement message only when a validation condition fails.
function Add-MissingIfFalse {
    param(
        [System.Collections.Generic.List[string]]$Missing,
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        $Missing.Add($Message) | Out-Null
    }
}

# Adds the tail of a recent helper log to the report so support can see the last
# failure without asking the player to find logs manually.
function Add-RecentLog {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Path
    )
    Add-Line $Lines "Log: $Path"
    try {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            Get-Content -LiteralPath $Path -Tail 20 | ForEach-Object { Add-Line $Lines "  $_" }
        }
        else {
            Add-Line $Lines '  missing'
        }
    }
    catch {
        Add-Line $Lines "  unreadable: $($_.Exception.Message)"
    }
}

# Choose an output path. By default the report goes to the desktop so it is easy
# for a player to attach to a support message.
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if ([string]::IsNullOrWhiteSpace($desktop)) {
        $desktop = Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant'
    }
    $OutputPath = Join-Path $desktop ("SupernovaSetupDiagnostic-{0}.txt" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

# Report header and selected paths.
$lines = [System.Collections.Generic.List[string]]::new()
Add-Line $lines 'Supernova Setup Assistant Diagnostic Report'
Add-Line $lines ("Generated: {0}" -f (Get-Date))
Add-Line $lines ''
Add-Line $lines 'Paths'
Add-Line $lines "  Game install folder: $GameInstallFolder"
Add-Line $lines "  PlayOnlineViewer: $PlayOnlineFolder"
Add-Line $lines "  FINAL FANTASY XI: $FfxiFolder"
Add-Line $lines "  Windower.exe: $WindowerExe"
Add-Line $lines "  Windower settings.xml: $WindowerSettings"
Add-Line $lines "  Ashita folder: $AshitaFolder"
Add-Line $lines "  Selected play method: $SelectedLauncher"
Add-Line $lines ''

# Detected files and representative patch/DAT checks.
Add-Line $lines 'Detected Files'
Add-Line $lines "  pol.exe: $(Get-FileSummary (Join-OptionalPath -Base $PlayOnlineFolder -Child 'pol.exe'))"
Add-Line $lines "  xiloader.exe: $(Get-FileSummary (Join-OptionalPath -Base $PlayOnlineFolder -Child 'xiloader.exe'))"
Add-Line $lines "  pol.exe compatibility: $(Get-RunAsAdminStatus -Path (Join-OptionalPath -Base $PlayOnlineFolder -Child 'pol.exe'))"
Add-Line $lines "  xiloader.exe compatibility: $(Get-RunAsAdminStatus -Path (Join-OptionalPath -Base $PlayOnlineFolder -Child 'xiloader.exe'))"
Add-Line $lines "  Ashita ffxi-bootmod\xiloader.exe: $(Get-FileSummary (Join-OptionalPath -Base $AshitaFolder -Child 'ffxi-bootmod\xiloader.exe'))"
Add-Line $lines "  MSVC 2015 x86 runtime: $(Get-Msvc2015RuntimeX86Status)"
Add-Line $lines "  FFXi.dll: $(Get-FileSummary (Join-OptionalPath -Base $FfxiFolder -Child 'FFXi.dll'))"
Add-Line $lines "  VTABLE.DAT: $(Get-FileSummary (Join-OptionalPath -Base $FfxiFolder -Child 'VTABLE.DAT'))"
Add-Line $lines "  vulgar2.dic: $(Get-VulgarDictionaryStatus -Folder $FfxiFolder)"
Add-Line $lines "  ROM4\1\69.dat: $(Get-FileSummary (Join-OptionalPath -Base $FfxiFolder -Child 'ROM4\1\69.dat'))"
Add-Line $lines "  ROM\27\57.dat: $(Get-FileSummary (Join-OptionalPath -Base $FfxiFolder -Child 'ROM\27\57.dat'))"
Add-Line $lines "  ROM\27\58.dat: $(Get-FileSummary (Join-OptionalPath -Base $FfxiFolder -Child 'ROM\27\58.dat'))"
Add-Line $lines "  sound4\win\music\data\music176.bgw: $(Get-FileSummary (Join-OptionalPath -Base $FfxiFolder -Child 'sound4\win\music\data\music176.bgw'))"
Add-Line $lines ''

# Launcher configuration summary.
Add-Line $lines 'Windower/Ashita Configuration'
Add-Line $lines "  Windower: $(Get-WindowerStatus -SettingsPath $WindowerSettings -ProfileName $WindowerProfile)"
Add-Line $lines "  Ashita: $(Get-AshitaStatus -Folder $AshitaFolder)"
Add-Line $lines ''

# Missing requirements section mirrors the assistant's final validation but is
# formatted for support review.
Add-Line $lines 'Missing Requirements'
$missing = [System.Collections.Generic.List[string]]::new()
$gameRootValid = $false
if (-not [string]::IsNullOrWhiteSpace($GameInstallFolder)) {
    $gameRootValid = (
        (Test-Path -LiteralPath (Join-Path $GameInstallFolder 'PlayOnlineViewer\pol.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $GameInstallFolder 'FINAL FANTASY XI\ROM') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $GameInstallFolder 'FINAL FANTASY XI\ROM3') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $GameInstallFolder 'FINAL FANTASY XI\ROM4') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $GameInstallFolder 'FINAL FANTASY XI\sound4') -PathType Container)
    )
}
Add-MissingIfFalse $missing $gameRootValid 'Game install folder containing PlayOnlineViewer and FINAL FANTASY XI'
Add-MissingIfFalse $missing ((Get-Msvc2015RuntimeX86Status) -match '^installed;') 'Microsoft Visual C++ 2015 x86 runtime'
Add-MissingIfFalse $missing (Test-OptionalPath -Base $PlayOnlineFolder -Child 'pol.exe' -PathType Leaf) 'PlayOnlineViewer folder with pol.exe'
Add-MissingIfFalse $missing (Test-OptionalPath -Base $PlayOnlineFolder -Child 'xiloader.exe' -PathType Leaf) 'xiloader.exe beside pol.exe'
Add-MissingIfFalse $missing (Test-RunAsAdminCompatibilityFlag -Path (Join-OptionalPath -Base $PlayOnlineFolder -Child 'pol.exe')) 'pol.exe set to Run as administrator'
Add-MissingIfFalse $missing (Test-RunAsAdminCompatibilityFlag -Path (Join-OptionalPath -Base $PlayOnlineFolder -Child 'xiloader.exe')) 'xiloader.exe set to Run as administrator'
Add-MissingIfFalse $missing (Test-OptionalPath -Base $FfxiFolder -Child 'ROM' -PathType Container) 'FINAL FANTASY XI\ROM folder'
Add-MissingIfFalse $missing (Test-OptionalPath -Base $FfxiFolder -Child 'ROM3' -PathType Container) 'FINAL FANTASY XI\ROM3 folder'
Add-MissingIfFalse $missing (Test-OptionalPath -Base $FfxiFolder -Child 'ROM4' -PathType Container) 'FINAL FANTASY XI\ROM4 folder'
Add-MissingIfFalse $missing (Test-OptionalPath -Base $FfxiFolder -Child 'sound4' -PathType Container) 'FINAL FANTASY XI\sound4 folder'
Add-MissingIfFalse $missing (Test-OptionalPath -Base $FfxiFolder -Child 'ROM4\1\69.dat' -PathType Leaf) 'Supernova DAT representative ROM4\1\69.dat'
Add-MissingIfFalse $missing (Test-OptionalPath -Base $FfxiFolder -Child 'FFXi.dll' -PathType Leaf) 'Supernova patch representative FFXi.dll'
if ($SelectedLauncher -eq 'Windower') {
    $windowerExePresent = (-not [string]::IsNullOrWhiteSpace($WindowerExe)) -and (Test-Path -LiteralPath $WindowerExe -PathType Leaf)
    Add-MissingIfFalse $missing $windowerExePresent 'Windower.exe'
    $windowerStatus = Get-WindowerStatus -SettingsPath $WindowerSettings -ProfileName $WindowerProfile
    Add-MissingIfFalse $missing ($windowerStatus -match 'profile found; executable=xiloader\.exe; args include Supernova server') 'Windower Supernova profile configured'
}
elseif ($SelectedLauncher -eq 'Ashita') {
    $ashitaCliPresent = $false
    $ashitaBootloaderPresent = $false
    if (-not [string]::IsNullOrWhiteSpace($AshitaFolder)) {
        $ashitaCliPresent = Test-Path -LiteralPath (Join-Path $AshitaFolder 'ashita-cli.exe') -PathType Leaf
        $ashitaBootloaderPresent = Test-Path -LiteralPath (Join-Path $AshitaFolder 'ffxi-bootmod\xiloader.exe') -PathType Leaf
    }
    Add-MissingIfFalse $missing $ashitaCliPresent 'Ashita folder with ashita-cli.exe'
    Add-MissingIfFalse $missing $ashitaBootloaderPresent 'Ashita ffxi-bootmod\xiloader.exe'
    $ashitaStatus = Get-AshitaStatus -Folder $AshitaFolder
    Add-MissingIfFalse $missing ($ashitaStatus -match 'supernova\.ini present with Supernova server') 'Ashita supernova.ini with Supernova server'
    Add-MissingIfFalse $missing ($ashitaStatus -match 'supernova\.ini points at ffxi-bootmod xiloader\.exe') 'Ashita supernova.ini points at ffxi-bootmod\xiloader.exe'
    Add-MissingIfFalse $missing ($ashitaStatus -match 'supernova\.ini includes username/password command') 'Ashita supernova.ini username/password command'
}
else {
    $missing.Add('Windower or Ashita selected') | Out-Null
}
if ($missing.Count -eq 0) {
    Add-Line $lines '  none detected'
}
else {
    $missing | ForEach-Object { Add-Line $lines "  $_" }
}
Add-Line $lines ''

# Recent logs from each helper script.
Add-Line $lines 'Recent Logs'
Add-RecentLog $lines (Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant\ConfigureWindower.log')
Add-RecentLog $lines (Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant\ConfigureAshita.log')
Add-RecentLog $lines (Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant\AshitaBootloaderInstall.log')
Add-RecentLog $lines (Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant\RepairSupernovaClient.log')
Add-RecentLog $lines (Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant\PatchInstall.log')
Add-RecentLog $lines (Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant\XiloaderInstall.log')
Add-RecentLog $lines (Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant\MsvcRuntimeInstall.log')
Add-RecentLog $lines (Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant\VulgarDictionaryCleanup.log')

# Write the finished report and print the path so the UI can show it.
$outDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$lines | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host $OutputPath
