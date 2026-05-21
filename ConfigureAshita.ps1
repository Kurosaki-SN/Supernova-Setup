# Configures Ashita v4 for Supernova by writing config\boot\supernova.ini.
# The xiloader bootloader should already be installed in ffxi-bootmod by
# InstallAshitaBootloader.ps1. Existing config files are backed up.
param(
    [Parameter(Mandatory = $true)]
    [string]$AshitaFolder,

    [string]$XiloaderPath = '',

    [string]$ConfigName = 'supernova.ini',

    [string]$XiloaderArgs = '--server login.supernovaffxi.com'
)

# Strict mode stops the helper if path checks or file writes fail.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Logs go under LocalAppData so troubleshooting data stays outside the Ashita
# install folder.
$appData = Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant'
$logPath = Join-Path $appData 'ConfigureAshita.log'

# Creates a directory only when it does not already exist.
function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Writes progress to both the console and a persistent log file.
function Write-SetupLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    New-DirectoryIfMissing -Path $appData
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $logPath -Value "[$stamp] $Message"
    Write-Host $Message
}

# Main configuration workflow: validate the Ashita install, make sure the
# bootloader exists in ffxi-bootmod, back up any existing config, then write
# config\boot\supernova.ini.
try {
    if (-not (Test-Path -LiteralPath $AshitaFolder -PathType Container)) {
        throw "Ashita folder not found: $AshitaFolder"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $AshitaFolder 'ashita-cli.exe') -PathType Leaf)) {
        throw "ashita-cli.exe not found in: $AshitaFolder"
    }
    if (-not $ConfigName.EndsWith('.ini', [StringComparison]::OrdinalIgnoreCase)) {
        $ConfigName = $ConfigName + '.ini'
    }

    # Ashita's Supernova profile should point at the bootloader copy inside
    # ffxi-bootmod, not the PlayOnlineViewer copy beside pol.exe.
    $bootloaderFolder = Join-Path $AshitaFolder 'ffxi-bootmod'
    $ashitaXiloader = Join-Path $bootloaderFolder 'xiloader.exe'

    if (-not (Test-Path -LiteralPath $bootloaderFolder -PathType Container)) {
        throw "ffxi-bootmod folder not found in: $AshitaFolder. Run Ashita's installer first, then click Install Ashita Bootloader."
    }

    if (-not (Test-Path -LiteralPath $ashitaXiloader -PathType Leaf)) {
        if (-not [string]::IsNullOrWhiteSpace($XiloaderPath) -and (Test-Path -LiteralPath $XiloaderPath -PathType Leaf)) {
            Copy-Item -LiteralPath $XiloaderPath -Destination $ashitaXiloader -Force
            Write-SetupLog "Copied xiloader.exe to $ashitaXiloader"
        }
        else {
            throw "xiloader.exe was not found in Ashita's ffxi-bootmod folder. Click Install Ashita Bootloader first."
        }
    }

    $bootConfigFolder = Join-Path $AshitaFolder 'config\boot'
    New-DirectoryIfMissing -Path $bootConfigFolder
    $configPath = Join-Path $bootConfigFolder $ConfigName

    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $backup = "$configPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $configPath -Destination $backup -Force
        Write-SetupLog "Backed up existing Ashita config to $backup"
    }

    # Ashita reads this INI when launching the profile. The command may include
    # username/password args if the player chose the saved-login step.
    $content = @"
[ashita.launcher]
autoclose = 1
name = Supernova

[ashita.boot]
file = $ashitaXiloader
command = $XiloaderArgs
gamemodule =
script =
args =

[ashita.language]
playonline = 2
ashita = 2

[ashita.logging]
level = 5
crashdumps = 1
"@

    Set-Content -LiteralPath $configPath -Value $content -Encoding ASCII
    Write-SetupLog "Wrote Ashita boot config to $configPath"
    exit 0
}
catch {
    Write-SetupLog "ERROR: $($_.Exception.Message)"
    exit 1
}
