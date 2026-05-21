# Prepares a retail PlayOnline file repair without automating the PlayOnline UI.
# It moves VTABLE.DAT out of the FFXI folder with a backup, then optionally opens
# PlayOnline Viewer so the user can manually run Check Files > FINAL FANTASY XI.
param(
    [Parameter(Mandatory = $true)]
    [string]$FfxiFolder,

    [Parameter(Mandatory = $true)]
    [string]$PlayOnlineFolder,

    [switch]$LaunchPlayOnline
)

# Strict mode stops the repair prep if folder validation or the VTABLE.DAT move
# fails.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Repair prep stores moved files in a dedicated LocalAppData backup area instead
# of deleting them.
$appData = Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant'
$backupRoot = Join-Path $appData 'RepairBackups'
$logPath = Join-Path $appData 'RepairSupernovaClient.log'

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

# Validates that the selected path is the FINAL FANTASY XI folder.
function Test-FfxiFolderLooksValid {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (
        (Test-Path -LiteralPath $Path -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Path 'ROM') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Path 'ROM4') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Path 'sound4') -PathType Container)
    )
}

# Main repair-prep workflow: validate folders, move VTABLE.DAT into a backup
# folder if it exists, and optionally launch PlayOnline for manual repair.
try {
    if (-not (Test-Path -LiteralPath $FfxiFolder -PathType Container)) {
        throw "FINAL FANTASY XI folder not found: $FfxiFolder"
    }
    if (-not (Test-FfxiFolderLooksValid -Path $FfxiFolder)) {
        throw "The selected folder does not look like FINAL FANTASY XI. Choose the folder that contains ROM, ROM4, and sound4. Do not choose PlayOnlineViewer, SquareEnix, or PlayOnline. Selected folder: $FfxiFolder"
    }
    if (-not (Test-Path -LiteralPath $PlayOnlineFolder -PathType Container)) {
        throw "PlayOnlineViewer folder not found: $PlayOnlineFolder"
    }

    $polPath = Join-Path $PlayOnlineFolder 'pol.exe'
    if (-not (Test-Path -LiteralPath $polPath -PathType Leaf)) {
        throw "pol.exe not found: $polPath"
    }

    New-DirectoryIfMissing -Path $backupRoot
    $backupDir = Join-Path $backupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-DirectoryIfMissing -Path $backupDir

    $vtablePath = Join-Path $FfxiFolder 'VTABLE.DAT'
    if (Test-Path -LiteralPath $vtablePath -PathType Leaf) {
        $backupPath = Join-Path $backupDir 'VTABLE.DAT'
        Move-Item -LiteralPath $vtablePath -Destination $backupPath -Force
        Write-SetupLog "Moved VTABLE.DAT to $backupPath"
    }
    else {
        Write-SetupLog 'VTABLE.DAT was not present; continuing repair prep.'
    }

    if ($LaunchPlayOnline) {
        Start-Process -FilePath $polPath -WorkingDirectory $PlayOnlineFolder | Out-Null
        Write-SetupLog "Launched PlayOnline Viewer: $polPath"
    }

    exit 0
}
catch {
    Write-SetupLog "ERROR: $($_.Exception.Message)"
    exit 1
}
