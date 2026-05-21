# Optional cleanup helper for Supernova setup. It searches only inside the
# selected FINAL FANTASY XI folder for vulgar2.dic, backs up any matches, then
# removes them from the game folder.
param(
    [Parameter(Mandatory = $true)]
    [string]$FfxiFolder
)

# Strict mode prevents the cleanup helper from continuing after path or backup
# errors.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Logs and backups are stored outside the game folder so cleanup remains
# auditable and reversible.
$appData = Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant'
$backupRoot = Join-Path $appData 'Backups'
$logPath = Join-Path $appData 'VulgarDictionaryCleanup.log'

# Creates a directory only when it does not already exist.
function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Writes progress to both the console and a persistent log file.
function Write-CleanupLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    New-DirectoryIfMissing -Path $appData
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $logPath -Value "[$stamp] $Message"
    Write-Host $Message
}

# Validates that the chosen folder is the FINAL FANTASY XI folder.
function Test-FfxiFolderLooksValid {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (
        (Test-Path -LiteralPath $Path -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Path 'ROM') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Path 'ROM3') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Path 'ROM4') -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $Path 'sound4') -PathType Container)
    )
}

# Confirms a matched file is still under the selected FFXI root before deleting.
function Test-PathInsideRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    return $pathFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

# Main cleanup workflow: locate vulgar2.dic files inside FFXI only, back them up
# with their relative paths preserved, then remove the originals.
function Backup-AndRemoveVulgarDictionary {
    param([Parameter(Mandatory = $true)][string]$TargetFfxiFolder)

    if (-not (Test-FfxiFolderLooksValid -Path $TargetFfxiFolder)) {
        throw "FINAL FANTASY XI folder is not valid or is missing ROM, ROM3, ROM4, or sound4: $TargetFfxiFolder"
    }

    New-DirectoryIfMissing -Path $appData
    New-DirectoryIfMissing -Path $backupRoot

    $rootFull = [System.IO.Path]::GetFullPath($TargetFfxiFolder).TrimEnd('\') + '\'
    $matches = @(Get-ChildItem -LiteralPath $TargetFfxiFolder -Filter 'vulgar2.dic' -File -Recurse -ErrorAction Stop)
    if ($matches.Count -eq 0) {
        Write-CleanupLog "No vulgar2.dic file was found under $TargetFfxiFolder"
        return
    }

    $backupDir = Join-Path $backupRoot ("VulgarDictionary-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-DirectoryIfMissing -Path $backupDir

    foreach ($match in $matches) {
        if (-not (Test-PathInsideRoot -Root $TargetFfxiFolder -Path $match.FullName)) {
            throw "Refusing to remove a file outside FINAL FANTASY XI: $($match.FullName)"
        }

        $relative = $match.FullName.Substring($rootFull.Length)
        $backupPath = Join-Path $backupDir $relative
        $backupParent = Split-Path -Parent $backupPath
        New-DirectoryIfMissing -Path $backupParent

        $candidate = $backupPath
        $suffix = 1
        while (Test-Path -LiteralPath $candidate) {
            $candidate = "$backupPath.$suffix.bak"
            $suffix++
        }

        Copy-Item -LiteralPath $match.FullName -Destination $candidate -Force
        Remove-Item -LiteralPath $match.FullName -Force
        Write-CleanupLog "Backed up and removed $relative"
    }

    Write-CleanupLog "Removed $($matches.Count) vulgar2.dic file(s). Backup folder: $backupDir"
}

# Entry point used by the setup assistant.
try {
    Backup-AndRemoveVulgarDictionary -TargetFfxiFolder $FfxiFolder
    exit 0
}
catch {
    Write-CleanupLog "ERROR: $($_.Exception.Message)"
    exit 1
}
