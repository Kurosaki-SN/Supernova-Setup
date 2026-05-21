# Downloads the pinned LandSandBoat xiloader v2.0.1 build and installs it as
# Ashita's bootloader under the ffxi-bootmod folder.
param(
    [Parameter(Mandatory = $true)]
    [string]$AshitaFolder,

    [string]$XiloaderUrl = 'https://github.com/LandSandBoat/xiloader/releases/download/v2.0.1/xiloader.exe',

    [string]$ExpectedMd5 = '122F8AA1E07ACB5D061DDC141D071340'
)

# Strict mode stops the helper instead of continuing after a bad download, hash
# mismatch, or failed copy.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Logs and backups live under LocalAppData so the Ashita folder only receives
# the bootloader file itself.
$appData = Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant'
$backupRoot = Join-Path $appData 'Backups'
$logPath = Join-Path $appData 'AshitaBootloaderInstall.log'

# Creates a directory only when it does not already exist.
function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Writes progress to both the console and a persistent log file.
function Write-BootloaderLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    New-DirectoryIfMissing -Path $appData
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $logPath -Value "[$stamp] $Message"
    Write-Host $Message
}

# Returns an uppercase MD5 hash so the downloaded xiloader can be compared with
# the pinned v2.0.1 release hash.
function Get-Md5 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm MD5 -LiteralPath $Path).Hash.ToUpperInvariant()
}

# Backs up an existing Ashita bootloader before replacing it.
function Backup-ExistingBootloader {
    param([Parameter(Mandatory = $true)][string]$ExistingPath)

    if (-not (Test-Path -LiteralPath $ExistingPath -PathType Leaf)) {
        return $null
    }

    $backupDir = Join-Path $backupRoot ("AshitaBootloader-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-DirectoryIfMissing -Path $backupDir
    $backupPath = Join-Path $backupDir 'xiloader.exe'
    Copy-Item -LiteralPath $ExistingPath -Destination $backupPath -Force
    return $backupPath
}

# Main workflow: validate the Ashita folder, download the pinned xiloader build,
# verify the hash, back up any existing ffxi-bootmod copy, then install it.
function Install-AshitaBootloader {
    param(
        [Parameter(Mandatory = $true)][string]$TargetAshitaFolder,
        [Parameter(Mandatory = $true)][string]$DownloadUrl,
        [Parameter(Mandatory = $true)][string]$PinnedMd5
    )

    if (-not (Test-Path -LiteralPath $TargetAshitaFolder -PathType Container)) {
        throw "Ashita folder not found: $TargetAshitaFolder"
    }

    if (-not (Test-Path -LiteralPath (Join-Path $TargetAshitaFolder 'ashita-cli.exe') -PathType Leaf)) {
        throw "ashita-cli.exe was not found in: $TargetAshitaFolder. Select the main Ashita folder after installing Ashita."
    }

    $bootloaderFolder = Join-Path $TargetAshitaFolder 'ffxi-bootmod'
    if (-not (Test-Path -LiteralPath $bootloaderFolder -PathType Container)) {
        throw "ffxi-bootmod folder was not found in: $TargetAshitaFolder. Run Ashita's installer first, then select the main Ashita folder."
    }

    New-DirectoryIfMissing -Path $appData
    New-DirectoryIfMissing -Path $backupRoot

    $work = Join-Path $env:TEMP ('SupernovaAshitaBootloader-' + [guid]::NewGuid().ToString('N'))
    $downloadPath = Join-Path $work 'xiloader.exe'
    $destinationPath = Join-Path $bootloaderFolder 'xiloader.exe'
    New-DirectoryIfMissing -Path $work

    try {
        Write-BootloaderLog "Downloading xiloader v2.0.1 from $DownloadUrl"
        $previousProgressPreference = $ProgressPreference
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $downloadPath -UseBasicParsing
        }
        finally {
            $ProgressPreference = $previousProgressPreference
        }

        $downloadedMd5 = Get-Md5 -Path $downloadPath
        if ($downloadedMd5 -ne $PinnedMd5.ToUpperInvariant()) {
            throw "Downloaded xiloader MD5 mismatch. Expected $PinnedMd5 but got $downloadedMd5."
        }
        Write-BootloaderLog "Verified xiloader v2.0.1 MD5: $downloadedMd5"

        if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
            $existingMd5 = Get-Md5 -Path $destinationPath
            if ($existingMd5 -eq $downloadedMd5) {
                Write-BootloaderLog "Ashita ffxi-bootmod xiloader.exe is already the pinned v2.0.1 build."
                return
            }

            $backupPath = Backup-ExistingBootloader -ExistingPath $destinationPath
            Write-BootloaderLog "Backed up existing Ashita bootloader to $backupPath"
        }

        Copy-Item -LiteralPath $downloadPath -Destination $destinationPath -Force
        Write-BootloaderLog "Installed xiloader.exe to $destinationPath"
    }
    finally {
        if (Test-Path -LiteralPath $work) {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Entry point used by the setup assistant. Non-zero exits tell the UI that the
# bootloader step failed.
try {
    Install-AshitaBootloader -TargetAshitaFolder $AshitaFolder -DownloadUrl $XiloaderUrl -PinnedMd5 $ExpectedMd5
    exit 0
}
catch {
    Write-BootloaderLog "ERROR: $($_.Exception.Message)"
    exit 1
}
