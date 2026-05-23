# Inputs supplied by the installer or by a manual PowerShell run.
# PlayOnlineFolder should be the PlayOnlineViewer folder that contains pol.exe.
# XiloaderUrl and ExpectedMd5 are pinned to the official LandSandBoat v2.0.1
# release asset for Supernova's supported 2.0.x line. The MD5 check keeps the
# installer from accepting a changed or incomplete download.
param(
    [Parameter(Mandatory = $true)]
    [string]$PlayOnlineFolder,

    [string]$XiloaderUrl = 'https://github.com/LandSandBoat/xiloader/releases/download/v2.0.1/xiloader.exe',

    [string]$ExpectedMd5 = '122F8AA1E07ACB5D061DDC141D071340'
)

# Stop on failures so the installer can report a failed xiloader install instead
# of silently leaving a partial or bad file behind.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Logs and backups live outside PlayOnline so players can inspect or restore
# previous xiloader.exe copies without adding extra files to the game folder.
$appData = Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant'
$backupRoot = Join-Path $appData 'Backups'
$logPath = Join-Path $appData 'XiloaderInstall.log'

# Creates a directory only when it does not already exist.
function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Add-SharedLogLine {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Line
    )

    $lastError = $null
    for ($attempt = 1; $attempt -le 5; $attempt++) {
        $stream = $null
        $writer = $null
        try {
            $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
            $writer = New-Object System.IO.StreamWriter -ArgumentList $stream, ([System.Text.Encoding]::UTF8)
            $writer.WriteLine($Line)
            return $true
        }
        catch {
            $lastError = $_
            if ($attempt -lt 5) {
                Start-Sleep -Milliseconds (50 * $attempt)
            }
        }
        finally {
            if ($writer) {
                $writer.Dispose()
            }
            elseif ($stream) {
                $stream.Dispose()
            }
        }
    }

    try {
        $message = if ($lastError) { $lastError.Exception.Message } else { 'unknown error' }
        Write-Host "Could not write log '$Path': $message"
    }
    catch {
    }
    return $false
}

# Writes progress to both the installer console and a persistent log file.
function Write-XiloaderLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    New-DirectoryIfMissing -Path $appData
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    [void](Add-SharedLogLine -Path $logPath -Line "[$stamp] $Message")
    Write-Host $Message
}

# Returns an uppercase MD5 hash for a file. GitHub's v2.0.1 release notes publish
# the MD5 for the pinned xiloader build, so this verifies the expected binary.
function Get-Md5 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -Algorithm MD5 -LiteralPath $Path).Hash.ToUpperInvariant()
}

# Backs up an existing destination file into a timestamped LocalAppData folder.
function Backup-ExistingXiloader {
    param([Parameter(Mandatory = $true)][string]$ExistingPath)

    if (-not (Test-Path -LiteralPath $ExistingPath -PathType Leaf)) {
        return $null
    }

    $backupDir = Join-Path $backupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-DirectoryIfMissing -Path $backupDir

    $backupPath = Join-Path $backupDir 'xiloader.exe'
    $suffix = 1
    while (Test-Path -LiteralPath $backupPath) {
        $backupPath = Join-Path $backupDir ("xiloader.exe.$suffix.bak")
        $suffix++
    }

    Copy-Item -LiteralPath $ExistingPath -Destination $backupPath -Force
    return $backupPath
}

# Main workflow: validate the PlayOnline folder, download the pinned official
# xiloader v2.0.1 release asset, verify its MD5, back up any existing
# xiloader.exe, then install the new file beside pol.exe.
function Install-Xiloader {
    param(
        [Parameter(Mandatory = $true)][string]$TargetPlayOnlineFolder,
        [Parameter(Mandatory = $true)][string]$DownloadUrl,
        [Parameter(Mandatory = $true)][string]$PinnedMd5
    )

    if (-not (Test-Path -LiteralPath $TargetPlayOnlineFolder -PathType Container)) {
        throw "PlayOnlineViewer folder not found: $TargetPlayOnlineFolder"
    }

    $polPath = Join-Path $TargetPlayOnlineFolder 'pol.exe'
    if (-not (Test-Path -LiteralPath $polPath -PathType Leaf)) {
        throw "pol.exe was not found in: $TargetPlayOnlineFolder"
    }

    New-DirectoryIfMissing -Path $appData
    New-DirectoryIfMissing -Path $backupRoot

    $work = Join-Path $env:TEMP ('SupernovaXiloader-' + [guid]::NewGuid().ToString('N'))
    $downloadPath = Join-Path $work 'xiloader.exe'
    $destinationPath = Join-Path $TargetPlayOnlineFolder 'xiloader.exe'
    New-DirectoryIfMissing -Path $work

    try {
        Write-XiloaderLog "Downloading pinned xiloader from $DownloadUrl"
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
        Write-XiloaderLog "Verified official v2.0.1 release MD5: $downloadedMd5"

        $fileVersionRaw = (Get-Item -LiteralPath $downloadPath).VersionInfo.FileVersionRaw
        if ($fileVersionRaw) {
            Write-XiloaderLog "Embedded Windows file version resource: $fileVersionRaw"
        }

        if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
            $existingMd5 = Get-Md5 -Path $destinationPath
            if ($existingMd5 -eq $downloadedMd5) {
                Write-XiloaderLog "xiloader.exe is already the pinned Supernova-compatible version."
                return
            }

            $backupPath = Backup-ExistingXiloader -ExistingPath $destinationPath
            Write-XiloaderLog "Backed up existing xiloader.exe to $backupPath"
        }

        Copy-Item -LiteralPath $downloadPath -Destination $destinationPath -Force
        Write-XiloaderLog "Installed xiloader.exe to $destinationPath"
    }
    finally {
        if (Test-Path -LiteralPath $work) {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Entry point used by the installer. A zero exit code means success; a non-zero
# exit code lets Inno Setup show an install failure message.
try {
    Install-Xiloader -TargetPlayOnlineFolder $PlayOnlineFolder -DownloadUrl $XiloaderUrl -PinnedMd5 $ExpectedMd5
    exit 0
}
catch {
    Write-XiloaderLog "ERROR: $($_.Exception.Message)"
    exit 1
}
