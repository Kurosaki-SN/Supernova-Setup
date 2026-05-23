# Inputs supplied by the installer or by a manual PowerShell run.
# FfxiFolder is the player's local FINAL FANTASY XI folder. CustomDatsUrl and
# PatchUrl can be overridden for future Supernova archive URLs without editing
# the rest of the script.
param(
    [Parameter(Mandatory = $true)]
    [string]$FfxiFolder,

    [string]$CustomDatsUrl = 'https://www.dropbox.com/scl/fi/8x60dqiegajxd5fw63viz/supernova-dats.zip?dl=1&e=1&file_subpath=%2Fsupernova-dats&rlkey=pxnn71t6jwcmyfdxudkrx5ywm',

    [string]$PatchUrl = 'https://www.dropbox.com/scl/fi/qx4l8slvbgcg76ko4h0bo/FFXI-UpdatePatch.zip?rlkey=ltvhrbzr9vtaf4pq3bm3hlc03&e=1&dl=1',

    [ValidateSet('All', 'CustomDats', 'RootPatch')]
    [string]$InstallSelection = 'All'
)

# Catch common mistakes and stop on errors so the installer can
# report a failed patch instead of silently continuing after a bad copy.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Dropbox and other modern download hosts require TLS 1.2 on many Windows
# systems. Set it explicitly so older PowerShell defaults do not stall/fail.
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
}
catch {
    Write-Host "Could not force TLS 1.2: $($_.Exception.Message)"
}

# Shared paths used for logs and backups. These live outside the FFXI folder so
# the patch process keeps a record of what it did without adding extra files to
# the game directory.
$appData = Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant'
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

# Validates that the selected folder is the FINAL FANTASY XI folder and not a
# parent folder or PlayOnlineViewer folder.
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

# Converts a custom DAT archive path into the matching path under the FFXI
# install. If the archive already contains ROM/sound folders, it preserves that
# structure. If the archive is flat, it maps the known Supernova DAT/music files
# to their documented destinations.
function Get-CustomDatsTargetRelativePath {
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

# Converts an update patch archive path into the matching path under the FFXI
# install. The update patch contains root-level game files such as DLLs, config
# files, and polboot.exe, so those files are installed directly into the selected
# FINAL FANTASY XI folder.
function Get-RootPatchTargetRelativePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    return $RelativePath.Replace('/', '\').TrimStart('\')
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

# Installs one Supernova archive into the FFXI folder. Both the custom DATs zip
# and update patch zip use this path so they get the same safety checks, path
# mapping, backup behavior, and cleanup.
function Install-SupernovaArchive {
    param(
        [Parameter(Mandatory = $true)][string]$TargetFfxiFolder,
        [Parameter(Mandatory = $true)][string]$DownloadUrl,
        [Parameter(Mandatory = $true)][string]$ArchiveLabel,
        [Parameter(Mandatory = $true)][string]$BackupDirectory,
        [Parameter(Mandatory = $true)]
        [ValidateSet('CustomDats', 'RootPatch')]
        [string]$InstallMode
    )

    # Use a unique temporary folder for every run so interrupted or parallel
    # installs cannot collide with each other.
    $safeLabel = $ArchiveLabel -replace '[^A-Za-z0-9]+', ''
    $work = Join-Path $env:TEMP ("Supernova$safeLabel-" + [guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $work "$safeLabel.zip"
    $extractPath = Join-Path $work 'extract'

    New-DirectoryIfMissing -Path $work
    New-DirectoryIfMissing -Path $extractPath

    try {
        # Download the zip to the temporary workspace. Progress output is muted
        # because the installer already shows its own status text.
        Write-PatchLog "Downloading $ArchiveLabel from $DownloadUrl"
        $previousProgressPreference = $ProgressPreference
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 600
        }
        finally {
            $ProgressPreference = $previousProgressPreference
        }

        # Expand the archive, then collect the extracted files. An empty archive
        # is treated as an error because there is nothing useful to install.
        Write-PatchLog "Extracting $ArchiveLabel archive"
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

        $files = @(Get-ChildItem -LiteralPath $extractPath -File -Recurse)
        if ($files.Count -eq 0) {
            throw "$ArchiveLabel zip did not contain any files."
        }

        # For each extracted file, verify the path is safe, translate it to the
        # destination inside FFXI, back up any existing file, and copy it.
        $rootPrefix = [System.IO.Path]::GetFullPath($extractPath).TrimEnd('\') + '\'
        foreach ($file in $files) {
            if (-not (Test-SafeExtractedFile -Root $extractPath -FilePath $file.FullName)) {
                throw "Unsafe file path in $ArchiveLabel zip: $($file.FullName)"
            }

            $relative = $file.FullName.Substring($rootPrefix.Length)
            if ($relative -match '(^|\\)\.\.(\\|$)') {
                throw "Unsafe relative path in $ArchiveLabel zip: $relative"
            }

            if ($InstallMode -eq 'CustomDats') {
                $targetRelative = Get-CustomDatsTargetRelativePath -RelativePath $relative
            }
            else {
                $targetRelative = Get-RootPatchTargetRelativePath -RelativePath $relative
            }

            $target = Join-Path $TargetFfxiFolder $targetRelative
            Write-PatchLog "Installing $targetRelative"
            Copy-FileWithBackup -Source $file.FullName -Destination $target -BackupDirectory $BackupDirectory -TargetRelativePath $targetRelative
        }
    }
    finally {
        # Temporary download/extract files are no longer needed after either a
        # success or a failure, so remove them before returning to the installer.
        if (Test-Path -LiteralPath $work) {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Main install workflow: validate the FFXI folder, create one timestamped backup
# folder for the whole run, install custom DATs first, then install the update
# patch on top.
function Apply-SupernovaPatch {
    param(
        [Parameter(Mandatory = $true)][string]$TargetFfxiFolder,
        [Parameter(Mandatory = $true)][string]$CustomDatsDownloadUrl,
        [Parameter(Mandatory = $true)][string]$PatchDownloadUrl,
        [Parameter(Mandatory = $true)]
        [ValidateSet('All', 'CustomDats', 'RootPatch')]
        [string]$Selection
    )

    if (-not (Test-Path -LiteralPath $TargetFfxiFolder -PathType Container)) {
        throw "FFXI folder not found: $TargetFfxiFolder"
    }
    if (-not (Test-FfxiFolderLooksValid -Path $TargetFfxiFolder)) {
        throw "The selected folder does not look like FINAL FANTASY XI. Choose the folder that contains ROM, ROM3, ROM4, and sound4. Do not choose PlayOnlineViewer, SquareEnix, or PlayOnline. Selected folder: $TargetFfxiFolder"
    }

    New-DirectoryIfMissing -Path $appData
    New-DirectoryIfMissing -Path $backupRoot

    $backupDir = Join-Path $backupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-DirectoryIfMissing -Path $backupDir

    if ($Selection -eq 'All' -or $Selection -eq 'CustomDats') {
        Install-SupernovaArchive -TargetFfxiFolder $TargetFfxiFolder -DownloadUrl $CustomDatsDownloadUrl -ArchiveLabel 'Supernova custom DATs' -BackupDirectory $backupDir -InstallMode 'CustomDats'
    }

    if ($Selection -eq 'All' -or $Selection -eq 'RootPatch') {
        Install-SupernovaArchive -TargetFfxiFolder $TargetFfxiFolder -DownloadUrl $PatchDownloadUrl -ArchiveLabel 'Supernova update patch' -BackupDirectory $backupDir -InstallMode 'RootPatch'
    }

    Write-PatchLog "Supernova install selection '$Selection' applied. Backups are in: $backupDir"
}

# Entry point used by the installer. A zero exit code means success; a non-zero
# exit code lets Inno Setup show a patch failure message.
try {
    Apply-SupernovaPatch -TargetFfxiFolder $FfxiFolder -CustomDatsDownloadUrl $CustomDatsUrl -PatchDownloadUrl $PatchUrl -Selection $InstallSelection
    exit 0
}
catch {
    Write-PatchLog "ERROR: $($_.Exception.Message)"
    exit 1
}
