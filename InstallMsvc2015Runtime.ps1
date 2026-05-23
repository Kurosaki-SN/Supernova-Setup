# Downloads and installs the latest supported Microsoft Visual C++ 2015-2022
# Redistributable x86 package. This helper does not touch PlayOnline or FFXI files.
param(
    [string]$DownloadPageUrl = 'https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist',

    [string]$VcRedistX86Url = 'https://aka.ms/vc14/vc_redist.x86.exe',

    [switch]$Force
)

# Stop on failures so the setup assistant can report a failed runtime install
# instead of silently continuing with a missing system dependency.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Logs live under LocalAppData so support can inspect what happened without
# adding files to the player's game installation.
$appData = Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant'
$logPath = Join-Path $appData 'MsvcRuntimeInstall.log'
$minimumRuntimeVersion = [version]'14.40.0.0'

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
function Write-MsvcLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    New-DirectoryIfMissing -Path $appData
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    [void](Add-SharedLogLine -Path $logPath -Line "[$stamp] $Message")
    Write-Host $Message
}

function ConvertTo-VersionOrNull {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $clean = $Value.Trim().TrimStart('v', 'V')
    try {
        return [version]$clean
    }
    catch {
        return $null
    }
}

function Get-FileVersionOrNull {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    return ConvertTo-VersionOrNull -Value (Get-Item -LiteralPath $Path).VersionInfo.FileVersion
}

# Reads the registry and key x86 runtime DLLs normally written by the supported
# VC++ 2015-2022 runtime family.
function Get-Msvc2015RuntimeX86Status {
    $runtimeRegistryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x86',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86'
    )

    $installed = $false
    $version = 'missing'
    $source = ''

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
                $installed = $true
                if (($props.PSObject.Properties.Name -contains 'Version') -and -not [string]::IsNullOrWhiteSpace([string]$props.Version)) {
                    $version = [string]$props.Version
                }
                $source = $path
                break
            }
        }
        catch {
            Write-MsvcLog "Registry check failed for ${path}: $($_.Exception.Message)"
        }
    }

    if (-not $installed) {
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
                $installed = $true
                $source = $path
                $version = 'unknown'
                if (($props.PSObject.Properties.Name -contains 'Version') -and -not [string]::IsNullOrWhiteSpace([string]$props.Version)) {
                    $version = [string]$props.Version
                }
                break
            }
            catch {
                Write-MsvcLog "Bundle registry check failed for ${path}: $($_.Exception.Message)"
            }
        }
    }

    $msvcp140Path = Join-Path $env:WINDIR 'SysWOW64\MSVCP140.dll'
    $vcruntime140Path = Join-Path $env:WINDIR 'SysWOW64\VCRUNTIME140.dll'
    $fileVersion = Get-FileVersionOrNull -Path $msvcp140Path
    $registryVersion = ConvertTo-VersionOrNull -Value $version
    $effectiveVersion = if ($fileVersion) { $fileVersion } else { $registryVersion }
    $hasRequiredFiles = (
        (Test-Path -LiteralPath $msvcp140Path -PathType Leaf) -and
        (Test-Path -LiteralPath $vcruntime140Path -PathType Leaf)
    )
    $meetsRequirement = (
        $installed -and
        $hasRequiredFiles -and
        $effectiveVersion -ne $null -and
        $effectiveVersion -ge $minimumRuntimeVersion
    )

    return [pscustomobject]@{
        Installed = $installed
        MeetsRequirement = $meetsRequirement
        Version = $version
        RuntimeFileVersion = if ($fileVersion) { $fileVersion.ToString() } else { 'missing' }
        RequiredFilesPresent = $hasRequiredFiles
        Source = $source
    }
}

# Confirms the downloaded EXE is signed by Microsoft before executing it.
function Assert-MicrosoftSignature {
    param([Parameter(Mandatory = $true)][string]$Path)

    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw "The downloaded Microsoft runtime installer signature is not valid. Status: $($signature.Status)."
    }

    if ($null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Subject -notmatch 'Microsoft') {
        throw 'The downloaded runtime installer was not signed by Microsoft.'
    }

    Write-MsvcLog "Verified Microsoft signature: $($signature.SignerCertificate.Subject)"
}

# Quotes a Windows process argument when passing a path that might contain
# spaces, such as a user profile under C:\Users.
function Quote-ProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

# Main workflow: skip only when the x86 runtime is modern enough, otherwise
# download the official Microsoft x86 redist, verify its signature, and run it.
function Install-Msvc2015RuntimeX86 {
    param(
        [Parameter(Mandatory = $true)][string]$PageUrl,
        [Parameter(Mandatory = $true)][string]$DownloadUrl,
        [bool]$ForceInstall
    )

    New-DirectoryIfMissing -Path $appData

    $before = Get-Msvc2015RuntimeX86Status
    if ($before.MeetsRequirement -and -not $ForceInstall) {
        Write-MsvcLog "MSVC 2015-2022 x86 runtime is already current. Version=$($before.Version); RuntimeFileVersion=$($before.RuntimeFileVersion); Source=$($before.Source)"
        return
    }

    if ($before.Installed) {
        Write-MsvcLog "MSVC 2015-2022 x86 runtime needs repair/update. Version=$($before.Version); RuntimeFileVersion=$($before.RuntimeFileVersion); RequiredFilesPresent=$($before.RequiredFilesPresent); Source=$($before.Source)"
    }

    $work = Join-Path $env:TEMP ('SupernovaMsvcRuntime-' + [guid]::NewGuid().ToString('N'))
    $downloadPath = Join-Path $work 'vc_redist.x86.exe'
    New-DirectoryIfMissing -Path $work

    try {
        Write-MsvcLog "Official Microsoft page: $PageUrl"
        Write-MsvcLog "Downloading MSVC 2015-2022 x86 runtime from $DownloadUrl"
        $previousProgressPreference = $ProgressPreference
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $downloadPath -UseBasicParsing
        }
        finally {
            $ProgressPreference = $previousProgressPreference
        }

        Assert-MicrosoftSignature -Path $downloadPath

        $redistLog = Join-Path $appData 'vc_redist_x86_install.log'
        Write-MsvcLog "Starting Microsoft installer. Log: $redistLog"
        $installerArgs = "/install /quiet /norestart /log $(Quote-ProcessArgument -Value $redistLog)"
        $process = Start-Process -FilePath $downloadPath -ArgumentList $installerArgs -Wait -PassThru
        $successCodes = @(0, 3010, 1638)
        if ($successCodes -notcontains $process.ExitCode) {
            throw "Microsoft runtime installer failed with exit code $($process.ExitCode)."
        }

        if ($process.ExitCode -eq 3010) {
            Write-MsvcLog 'Microsoft installer finished successfully and reported that Windows may need a restart later.'
        }
        elseif ($process.ExitCode -eq 1638) {
            Write-MsvcLog 'Microsoft installer reported that another compatible VC++ runtime version is already installed.'
        }
        else {
            Write-MsvcLog 'Microsoft installer finished successfully.'
        }

        $after = Get-Msvc2015RuntimeX86Status
        if (-not $after.MeetsRequirement) {
            throw "The Microsoft installer finished, but the MSVC 2015-2022 x86 runtime is still not current. Version=$($after.Version); RuntimeFileVersion=$($after.RuntimeFileVersion); RequiredFilesPresent=$($after.RequiredFilesPresent)"
        }

        Write-MsvcLog "Verified MSVC 2015-2022 x86 runtime after install. Version=$($after.Version); RuntimeFileVersion=$($after.RuntimeFileVersion); Source=$($after.Source)"
    }
    finally {
        if (Test-Path -LiteralPath $work) {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Entry point used by the setup assistant.
try {
    Install-Msvc2015RuntimeX86 -PageUrl $DownloadPageUrl -DownloadUrl $VcRedistX86Url -ForceInstall ([bool]$Force)
    exit 0
}
catch {
    Write-MsvcLog "ERROR: $($_.Exception.Message)"
    exit 1
}
