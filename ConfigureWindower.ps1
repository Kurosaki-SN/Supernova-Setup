# Configures a Windower profile for Supernova without launching the game.
# The script updates settings.xml only after making a timestamped backup.
param(
    [Parameter(Mandatory = $true)]
    [string]$SettingsXmlPath,

    [string]$ProfileName = 'Supernova',

    [string]$XiloaderArgs = '--server login.supernovaffxi.com'
)

# Strict mode makes missing variables and failed commands stop the helper before
# it can save a partially updated settings.xml.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Logs go under LocalAppData so support can inspect what happened without adding
# files to the Windower folder.
$appData = Join-Path $env:LOCALAPPDATA 'SupernovaSetupAssistant'
$logPath = Join-Path $appData 'ConfigureWindower.log'

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

# Windower profiles have appeared with the name either as an attribute or as a
# child element, so this supports both forms.
function Find-WindowerProfileNode {
    param(
        [Parameter(Mandatory = $true)][xml]$Document,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $profiles = $Document.SelectNodes("//*[local-name()='profile']")
    foreach ($profile in $profiles) {
        if ($profile.Attributes -and $profile.Attributes['name'] -and $profile.Attributes['name'].Value -eq $Name) {
            return $profile
        }

        $nameNode = $profile.SelectSingleNode("*[local-name()='name']")
        if ($nameNode -and $nameNode.InnerText -eq $Name) {
            return $profile
        }
    }

    return $null
}

# Creates or updates a child XML element under the selected Windower profile.
# This is used for both <args> and <executable>.
function Set-XmlChildText {
    param(
        [Parameter(Mandatory = $true)][xml]$Document,
        [Parameter(Mandatory = $true)]$Parent,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Value
    )

    $child = $Parent.SelectSingleNode("*[local-name()='$Name']")
    if (-not $child) {
        $child = $Document.CreateElement($Name)
        $Parent.AppendChild($child) | Out-Null
    }
    $child.InnerText = $Value
}

# Main configuration workflow: validate settings.xml, find the requested profile,
# back up the file, then write the Supernova xiloader entries.
try {
    if (-not (Test-Path -LiteralPath $SettingsXmlPath -PathType Leaf)) {
        throw "Windower settings.xml not found: $SettingsXmlPath"
    }

    [xml]$doc = Get-Content -LiteralPath $SettingsXmlPath -Raw
    $profile = Find-WindowerProfileNode -Document $doc -Name $ProfileName
    if (-not $profile) {
        Write-SetupLog "Profile '$ProfileName' was not found in settings.xml."
        Write-SetupLog "Create a Windower profile named '$ProfileName', then run this step again."
        exit 2
    }

    $backup = "$SettingsXmlPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $SettingsXmlPath -Destination $backup -Force
    Write-SetupLog "Backed up Windower settings to $backup"

    Set-XmlChildText -Document $doc -Parent $profile -Name 'args' -Value $XiloaderArgs
    Set-XmlChildText -Document $doc -Parent $profile -Name 'executable' -Value 'xiloader.exe'
    $doc.Save($SettingsXmlPath)

    Write-SetupLog "Configured Windower profile '$ProfileName' for Supernova."
    exit 0
}
catch {
    Write-SetupLog "ERROR: $($_.Exception.Message)"
    exit 1
}
