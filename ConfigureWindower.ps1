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

# Writes progress to both the console and a persistent log file.
function Write-SetupLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    New-DirectoryIfMissing -Path $appData
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    [void](Add-SharedLogLine -Path $logPath -Line "[$stamp] $Message")
    Write-Host $Message
}

function Test-WindowerProfileNameMatches {
    param(
        [Parameter(Mandatory = $true)]$Profile,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $target = $Name.Trim()
    if ($Profile.Attributes -and $Profile.Attributes['name']) {
        $attributeName = $Profile.Attributes['name'].Value
        if (-not [string]::IsNullOrWhiteSpace($attributeName) -and [string]::Equals($attributeName.Trim(), $target, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    $nameNode = $Profile.SelectSingleNode("*[local-name()='name']")
    if ($nameNode -and -not [string]::IsNullOrWhiteSpace($nameNode.InnerText) -and [string]::Equals($nameNode.InnerText.Trim(), $target, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    return $false
}

function Test-WindowerProfileIsUnnamed {
    param([Parameter(Mandatory = $true)]$Profile)

    if ($Profile.Attributes -and $Profile.Attributes['name'] -and -not [string]::IsNullOrWhiteSpace($Profile.Attributes['name'].Value)) {
        return $false
    }

    $nameNode = $Profile.SelectSingleNode("*[local-name()='name']")
    if ($nameNode -and -not [string]::IsNullOrWhiteSpace($nameNode.InnerText)) {
        return $false
    }

    return $true
}

function Set-WindowerProfileName {
    param(
        [Parameter(Mandatory = $true)][xml]$Document,
        [Parameter(Mandatory = $true)]$Profile,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not $Profile.Attributes['name']) {
        $attribute = $Document.CreateAttribute('name')
        $Profile.Attributes.Append($attribute) | Out-Null
    }
    $Profile.Attributes['name'].Value = $Name

    $nameNode = $Profile.SelectSingleNode("*[local-name()='name']")
    if ($nameNode) {
        $nameNode.InnerText = $Name
    }
}

# Windower profiles have appeared with the name either as an attribute or as a
# child element. Fresh Windower installs can also keep the first profile unnamed.
function Find-WindowerProfileNode {
    param(
        [Parameter(Mandatory = $true)][xml]$Document,
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$AllowSingleUnnamed
    )

    $profiles = @($Document.SelectNodes("//*[local-name()='profile']"))
    foreach ($profile in $profiles) {
        if (Test-WindowerProfileNameMatches -Profile $profile -Name $Name) {
            return $profile
        }
    }

    if ($AllowSingleUnnamed) {
        $unnamedProfiles = @($profiles | Where-Object { Test-WindowerProfileIsUnnamed -Profile $_ })
        if ($unnamedProfiles.Count -eq 1) {
            return $unnamedProfiles[0]
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
    $profile = Find-WindowerProfileNode -Document $doc -Name $ProfileName -AllowSingleUnnamed
    if (-not $profile) {
        Write-SetupLog "Profile '$ProfileName' was not found in settings.xml."
        Write-SetupLog "Create a Windower profile named '$ProfileName', then run this step again."
        exit 2
    }

    $backup = "$SettingsXmlPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $SettingsXmlPath -Destination $backup -Force
    Write-SetupLog "Backed up Windower settings to $backup"

    if (Test-WindowerProfileIsUnnamed -Profile $profile) {
        Set-WindowerProfileName -Document $doc -Profile $profile -Name $ProfileName
        Write-SetupLog "Named the single unnamed Windower profile '$ProfileName'."
    }

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
