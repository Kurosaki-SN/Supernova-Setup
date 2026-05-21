# Downloads and installs the Microsoft Visual C++ Redistributable for Visual
# Studio 2015 x86 package. This helper does not touch PlayOnline or FFXI files.
param(
    [string]$DownloadPageUrl = 'https://www.microsoft.com/en-ca/download/details.aspx?id=48145',

    [string]$VcRedistX86Url = 'https://download.microsoft.com/download/9/3/F/93FCF1E7-E6A4-478B-96E7-D4B285925B00/vc_redist.x86.exe',

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

# Creates a directory only when it does not already exist.
function New-DirectoryIfMissing {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

# Writes progress to both the installer console and a persistent log file.
function Write-MsvcLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    New-DirectoryIfMissing -Path $appData
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $logPath -Value "[$stamp] $Message"
    Write-Host $Message
}

# Reads the registry locations normally written by the VC++ 2015 x86 runtime.
# Newer 2015-2022 redistributables also satisfy this requirement because they
# use the same VC runtime family.
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
                return [pscustomobject]@{
                    Installed = $true
                    Version = $version
                    Source = $path
                }
            }
        }
        catch {
            Write-MsvcLog "Registry check failed for ${path}: $($_.Exception.Message)"
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
            return [pscustomobject]@{
                Installed = $true
                Version = $version
                Source = $path
            }
        }
        catch {
            Write-MsvcLog "Bundle registry check failed for ${path}: $($_.Exception.Message)"
        }
    }

    return [pscustomobject]@{
        Installed = $false
        Version = 'missing'
        Source = ''
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

# Main workflow: skip if the runtime is already installed, otherwise download
# the official Microsoft x86 redist, verify its signature, and run it quietly.
function Install-Msvc2015RuntimeX86 {
    param(
        [Parameter(Mandatory = $true)][string]$PageUrl,
        [Parameter(Mandatory = $true)][string]$DownloadUrl,
        [bool]$ForceInstall
    )

    New-DirectoryIfMissing -Path $appData

    $before = Get-Msvc2015RuntimeX86Status
    if ($before.Installed -and -not $ForceInstall) {
        Write-MsvcLog "MSVC 2015 x86 runtime is already installed. Version=$($before.Version); Source=$($before.Source)"
        return
    }

    $work = Join-Path $env:TEMP ('SupernovaMsvcRuntime-' + [guid]::NewGuid().ToString('N'))
    $downloadPath = Join-Path $work 'vc_redist.x86.exe'
    New-DirectoryIfMissing -Path $work

    try {
        Write-MsvcLog "Official Microsoft page: $PageUrl"
        Write-MsvcLog "Downloading MSVC 2015 x86 runtime from $DownloadUrl"
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
        if (-not $after.Installed) {
            throw 'The Microsoft installer finished, but the MSVC 2015 x86 runtime could not be verified in the registry.'
        }

        Write-MsvcLog "Verified MSVC 2015 x86 runtime after install. Version=$($after.Version); Source=$($after.Source)"
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
