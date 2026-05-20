# Inputs supplied by the installer or by a manual PowerShell run.
# FfxiFolder is the player's local FINAL FANTASY XI folder; PatchUrl can be
# overridden for future Supernova patch URLs without editing the rest of the script.
param(
    [Parameter(Mandatory = $true)]
    [string]$FfxiFolder,

    [string]$PatchUrl = 'https://www.dropbox.com/scl/fi/qx4l8slvbgcg76ko4h0bo/FFXI-UpdatePatch.zip?rlkey=ltvhrbzr9vtaf4pq3bm3hlc03&e=1&dl=1'
)

# Catch common mistakes and stop on errors so the installer can
# report a failed patch instead of silently continuing after a bad copy.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Shared paths used for logs and backups. These live outside the FFXI folder so
# the patch process keeps a record of what it did without adding extra files to
# the game directory.
$appData = Join-Path $env:LOCALAPPDATA 'SupernovaFFXILauncher'
$backupRoot = Join-Path $appData 'Backups'
$logPath = Join-Path $appData 'PatchInstall.log'

# Creates a directory only when it does not already exist. Several other
# functions call this before writing logs, backups, extracted files, or targets.
function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Writes progress to both the installer console and a persistent log file.
# The log is useful if a player reports that patching failed on their machine.
function Write-PatchLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    New-DirectoryIfMissing -Path $appData
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $logPath -Value "[$stamp] $Message"
    Write-Host $Message
}

# Confirms an extracted file is still inside the temporary extraction folder.
# This protects against zip entries with odd paths that try to escape the temp folder.
function Test-SafeExtractedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$FilePath
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $fileFull = [System.IO.Path]::GetFullPath($FilePath)
    return $fileFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

# Converts a path from the downloaded zip into the matching path under the FFXI
# install. If the zip already contains ROM/sound folders, it preserves that
# structure. If the zip is flat, it maps the known Supernova files to their
# documented destinations.
function Get-PatchTargetRelativePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $clean = $RelativePath.Replace('/', '\').TrimStart('\')
    $parts = @($clean -split '\\' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $knownRoots = @(
        'rom', 'rom2', 'rom3', 'rom4', 'rom5', 'rom6', 'rom7', 'rom8', 'rom9',
        'sound', 'sound2', 'sound3', 'sound4'
    )

    for ($i = 0; $i -lt $parts.Count; $i++) {
        if ($knownRoots -contains $parts[$i].ToLowerInvariant()) {
            return (@($parts[$i..($parts.Count - 1)]) -join '\')
        }
    }

    $leaf = [System.IO.Path]::GetFileName($clean).ToLowerInvariant()
    switch ($leaf) {
        'music176.bgw' { return 'sound4\win\music\data\music176.bgw' }
        '69.dat' { return 'ROM4\1\69.dat' }
        '57.dat' { return 'ROM\27\57.dat' }
        '58.dat' { return 'ROM\27\58.dat' }
        default { return $clean }
    }
}

# Copies a patch file into the FFXI folder. If a target file already exists, it
# is copied into the timestamped backup folder first using the same relative path.
function Copy-FileWithBackup {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$BackupDirectory,
        [Parameter(Mandatory = $true)][string]$TargetRelativePath
    )

    $destinationDirectory = Split-Path -Parent $Destination
    New-DirectoryIfMissing -Path $destinationDirectory

    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $backupPath = Join-Path $BackupDirectory $TargetRelativePath
        $backupDirectoryForFile = Split-Path -Parent $backupPath
        New-DirectoryIfMissing -Path $backupDirectoryForFile

        $suffix = 1
        $candidate = $backupPath
        while (Test-Path -LiteralPath $candidate) {
            $candidate = "$backupPath.$suffix.bak"
            $suffix++
        }

        Copy-Item -LiteralPath $Destination -Destination $candidate -Force
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

# Main patch workflow: validate the FFXI folder, download the patch zip, extract
# it to a temporary folder, place each file into the right FFXI subfolder, and
# clean up temporary files afterward.
function Apply-SupernovaPatch {
    param(
        [Parameter(Mandatory = $true)][string]$TargetFfxiFolder,
        [Parameter(Mandatory = $true)][string]$DownloadUrl
    )

    if (-not (Test-Path -LiteralPath $TargetFfxiFolder -PathType Container)) {
        throw "FFXI folder not found: $TargetFfxiFolder"
    }

    New-DirectoryIfMissing -Path $appData
    New-DirectoryIfMissing -Path $backupRoot

    # Use a unique temporary folder for every run so interrupted or parallel
    # installs cannot collide with each other.
    $work = Join-Path $env:TEMP ('SupernovaPatch-' + [guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $work 'FFXI-UpdatePatch.zip'
    $extractPath = Join-Path $work 'extract'
    $backupDir = Join-Path $backupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')

    New-DirectoryIfMissing -Path $work
    New-DirectoryIfMissing -Path $extractPath
    New-DirectoryIfMissing -Path $backupDir

    try {
        # Download the zip to the temporary workspace. Progress output is muted
        # because the installer already shows its own status text.
        Write-PatchLog "Downloading patch from $DownloadUrl"
        $previousProgressPreference = $ProgressPreference
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipPath -UseBasicParsing
        }
        finally {
            $ProgressPreference = $previousProgressPreference
        }

        # Expand the archive, then collect the extracted files. An empty archive
        # is treated as an error because there is nothing useful to install.
        Write-PatchLog "Extracting patch archive"
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

        $files = @(Get-ChildItem -LiteralPath $extractPath -File -Recurse)
        if ($files.Count -eq 0) {
            throw 'Patch zip did not contain any files.'
        }

        # For each extracted file, verify the path is safe, translate it to the
        # destination inside FFXI, back up any existing file, and copy the patch.
        $rootPrefix = [System.IO.Path]::GetFullPath($extractPath).TrimEnd('\') + '\'
        foreach ($file in $files) {
            if (-not (Test-SafeExtractedFile -Root $extractPath -FilePath $file.FullName)) {
                throw "Unsafe file path in patch zip: $($file.FullName)"
            }

            $relative = $file.FullName.Substring($rootPrefix.Length)
            if ($relative -match '(^|\\)\.\.(\\|$)') {
                throw "Unsafe relative path in patch zip: $relative"
            }

            $targetRelative = Get-PatchTargetRelativePath -RelativePath $relative
            $target = Join-Path $TargetFfxiFolder $targetRelative
            Write-PatchLog "Installing $targetRelative"
            Copy-FileWithBackup -Source $file.FullName -Destination $target -BackupDirectory $backupDir -TargetRelativePath $targetRelative
        }

        Write-PatchLog "Patch applied. Backups are in: $backupDir"
    }
    finally {
        # Temporary download/extract files are no longer needed after either a
        # success or a failure, so remove them before returning to the installer.
        if (Test-Path -LiteralPath $work) {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Entry point used by the installer. A zero exit code means success; a non-zero
# exit code lets Inno Setup show a patch failure message.
try {
    Apply-SupernovaPatch -TargetFfxiFolder $FfxiFolder -DownloadUrl $PatchUrl
    exit 0
}
catch {
    Write-PatchLog "ERROR: $($_.Exception.Message)"
    exit 1
}
