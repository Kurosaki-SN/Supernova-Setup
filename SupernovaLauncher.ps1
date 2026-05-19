Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:AppName = 'Supernova FFXI Launcher'
$script:ServerHost = 'login.supernovaffxi.com'
$script:PatchUrl = 'https://www.dropbox.com/scl/fi/qx4l8slvbgcg76ko4h0bo/FFXI-UpdatePatch.zip?rlkey=ltvhrbzr9vtaf4pq3bm3hlc03&e=1&dl=1'
$script:SettingsDir = Join-Path $env:LOCALAPPDATA 'SupernovaFFXILauncher'
$script:SettingsPath = Join-Path $script:SettingsDir 'settings.json'
$script:BackupRoot = Join-Path $script:SettingsDir 'Backups'
$script:LogPath = Join-Path $script:SettingsDir 'launcher.log'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function New-DirectoryIfMissing {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)
    New-DirectoryIfMissing -Path $script:SettingsDir
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $script:LogPath -Value "[$stamp] $Message"
}

function Show-Info {
    param([Parameter(Mandatory)][string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, $script:AppName, 'OK', 'Information') | Out-Null
}

function Show-Error {
    param([Parameter(Mandatory)][string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, $script:AppName, 'OK', 'Error') | Out-Null
}

function Confirm-Action {
    param([Parameter(Mandatory)][string]$Message)
    $result = [System.Windows.Forms.MessageBox]::Show($Message, $script:AppName, 'YesNo', 'Question')
    return $result -eq [System.Windows.Forms.DialogResult]::Yes
}

function Get-KnownFolder {
    param(
        [Parameter(Mandatory)][string[]]$Candidates,
        [Parameter(Mandatory)][string]$Fallback
    )

    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    return $Fallback
}

function Get-DefaultPlayOnlineFolder {
    $pf86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $pf = [Environment]::GetFolderPath('ProgramFiles')
    return Get-KnownFolder -Candidates @(
        (Join-Path $pf86 'PlayOnline\SquareEnix\PlayOnlineViewer'),
        (Join-Path $pf 'PlayOnline\SquareEnix\PlayOnlineViewer'),
        'E:\PlayOnline\SquareEnix\PlayOnlineViewer'
    ) -Fallback (Join-Path $pf86 'PlayOnline\SquareEnix\PlayOnlineViewer')
}

function Get-DefaultFfxiFolder {
    $pf86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $pf = [Environment]::GetFolderPath('ProgramFiles')
    return Get-KnownFolder -Candidates @(
        (Join-Path $pf86 'PlayOnline\SquareEnix\FINAL FANTASY XI'),
        (Join-Path $pf 'PlayOnline\SquareEnix\FINAL FANTASY XI'),
        'E:\PlayOnline\SquareEnix\FINAL FANTASY XI'
    ) -Fallback (Join-Path $pf86 'PlayOnline\SquareEnix\FINAL FANTASY XI')
}

function Get-DefaultWindowerExe {
    $pf86 = [Environment]::GetFolderPath('ProgramFilesX86')
    return Get-KnownFolder -Candidates @(
        (Join-Path $pf86 'Windower4\Windower.exe'),
        (Join-Path $HOME 'Desktop\Windower4\Windower.exe'),
        'C:\Windower4\Windower.exe'
    ) -Fallback (Join-Path $pf86 'Windower4\Windower.exe')
}

function Get-DefaultWindowerSettings {
    $windowerExe = Get-DefaultWindowerExe
    return Join-Path (Split-Path -Parent $windowerExe) 'settings.xml'
}

function Get-DefaultAshitaFolder {
    return Get-KnownFolder -Candidates @(
        'C:\Ashita',
        (Join-Path $HOME 'Desktop\Ashita'),
        (Join-Path $HOME 'Downloads\Ashita')
    ) -Fallback 'C:\Ashita'
}

function Get-DefaultSettings {
    $polFolder = Get-DefaultPlayOnlineFolder
    $ashitaFolder = Get-DefaultAshitaFolder

    [pscustomobject]@{
        PlayOnlineFolder = $polFolder
        FfxiFolder = Get-DefaultFfxiFolder
        XiloaderPath = Join-Path $polFolder 'xiloader.exe'
        Username = ''
        PasswordProtected = ''
        RememberPassword = $false
        RunElevated = $true
        WindowerExe = Get-DefaultWindowerExe
        WindowerSettings = Get-DefaultWindowerSettings
        WindowerProfile = 'Supernova'
        AshitaFolder = $ashitaFolder
        AshitaConfigName = 'supernova.ini'
    }
}

function Load-Settings {
    $defaults = Get-DefaultSettings
    if (-not (Test-Path -LiteralPath $script:SettingsPath)) {
        return $defaults
    }

    try {
        $loaded = Get-Content -LiteralPath $script:SettingsPath -Raw | ConvertFrom-Json
        foreach ($name in $defaults.PSObject.Properties.Name) {
            if ($loaded.PSObject.Properties.Name -notcontains $name) {
                $loaded | Add-Member -NotePropertyName $name -NotePropertyValue $defaults.$name
            }
        }
        return $loaded
    }
    catch {
        Write-Log "Failed to read settings: $($_.Exception.Message)"
        return $defaults
    }
}

function Save-Settings {
    param([Parameter(Mandatory)]$Settings)
    New-DirectoryIfMissing -Path $script:SettingsDir
    $Settings | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:SettingsPath -Encoding UTF8
}

function Protect-Password {
    param([string]$Password)
    if ([string]::IsNullOrEmpty($Password)) {
        return ''
    }

    $secure = ConvertTo-SecureString -String $Password -AsPlainText -Force
    return ConvertFrom-SecureString -SecureString $secure
}

function Unprotect-Password {
    param([string]$ProtectedPassword)
    if ([string]::IsNullOrWhiteSpace($ProtectedPassword)) {
        return ''
    }

    $bstr = [IntPtr]::Zero
    try {
        $secure = ConvertTo-SecureString -String $ProtectedPassword
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    catch {
        Write-Log "Failed to unprotect saved password: $($_.Exception.Message)"
        return ''
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Quote-ProcessArgument {
    param([Parameter(Mandatory)][string]$Value)
    if ($Value -notmatch '[\s"]') {
        return $Value
    }

    $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $escaped + '"'
}

function Join-ProcessArguments {
    param([string[]]$Arguments)
    return (($Arguments | Where-Object { -not [string]::IsNullOrEmpty($_) } | ForEach-Object { Quote-ProcessArgument $_ }) -join ' ')
}

function Start-ExternalProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = '',
        [bool]$RunElevated = $false
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "File not found: $FilePath"
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = Join-ProcessArguments -Arguments $Arguments
    $psi.UseShellExecute = $true

    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $psi.WorkingDirectory = $WorkingDirectory
    }

    if ($RunElevated) {
        $psi.Verb = 'runas'
    }

    Write-Log "Starting: $FilePath $($psi.Arguments)"
    [System.Diagnostics.Process]::Start($psi) | Out-Null
}

function Browse-File {
    param(
        [string]$Title,
        [string]$Filter = 'Executable files (*.exe)|*.exe|All files (*.*)|*.*',
        [string]$InitialDirectory = ''
    )

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = $Title
    $dialog.Filter = $Filter
    if (-not [string]::IsNullOrWhiteSpace($InitialDirectory) -and (Test-Path -LiteralPath $InitialDirectory)) {
        $dialog.InitialDirectory = $InitialDirectory
    }

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.FileName
    }

    return $null
}

function Browse-Folder {
    param(
        [string]$Description,
        [string]$SelectedPath = ''
    )

    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $false
    if (-not [string]::IsNullOrWhiteSpace($SelectedPath) -and (Test-Path -LiteralPath $SelectedPath)) {
        $dialog.SelectedPath = $SelectedPath
    }

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $dialog.SelectedPath
    }

    return $null
}

function Build-XiloaderArguments {
    param(
        [string]$Username,
        [string]$Password
    )

    $args = @('--server', $script:ServerHost)
    if (-not [string]::IsNullOrWhiteSpace($Username)) {
        $args += @('--user', $Username.Trim())
    }
    if (-not [string]::IsNullOrWhiteSpace($Password)) {
        $args += @('--password', $Password)
    }

    return $args
}

function Get-XiloaderCommandText {
    param(
        [string]$Username,
        [string]$Password
    )

    return Join-ProcessArguments -Arguments (Build-XiloaderArguments -Username $Username -Password $Password)
}

function Copy-FileWithBackup {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$BackupDirectory,
        [string]$BackupRelativePath = ''
    )

    $destinationDirectory = Split-Path -Parent $Destination
    New-DirectoryIfMissing -Path $destinationDirectory

    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        if ([string]::IsNullOrWhiteSpace($BackupRelativePath)) {
            $BackupRelativePath = Split-Path -Leaf $Destination
        }

        $backupPath = Join-Path $BackupDirectory $BackupRelativePath
        New-DirectoryIfMissing -Path (Split-Path -Parent $backupPath)
        $suffix = 1
        while (Test-Path -LiteralPath $backupPath) {
            $backupPath = Join-Path $BackupDirectory ("{0}.{1}.bak" -f $BackupRelativePath, $suffix)
            $suffix++
        }
        Copy-Item -LiteralPath $Destination -Destination $backupPath -Force
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Test-SafeExtractedFile {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$FilePath
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $fileFull = [System.IO.Path]::GetFullPath($FilePath)
    return $fileFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)
}

function Get-PatchTargetRelativePath {
    param([Parameter(Mandatory)][string]$RelativePath)

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

function Apply-PatchZip {
    param([Parameter(Mandatory)][string]$FfxiFolder)

    if (-not (Test-Path -LiteralPath $FfxiFolder -PathType Container)) {
        throw "FFXI folder not found: $FfxiFolder"
    }

    $message = "This will download the Supernova patch zip and copy its contents into:`r`n$FfxiFolder`r`n`r`nExisting overwritten files are backed up first. Continue?"
    if (-not (Confirm-Action -Message $message)) {
        return
    }

    New-DirectoryIfMissing -Path $script:SettingsDir
    New-DirectoryIfMissing -Path $script:BackupRoot

    $work = Join-Path $env:TEMP ('SupernovaPatch-' + [guid]::NewGuid().ToString('N'))
    $zipPath = Join-Path $work 'FFXI-UpdatePatch.zip'
    $extractPath = Join-Path $work 'extract'
    $backupDir = Join-Path $script:BackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')

    New-DirectoryIfMissing -Path $work
    New-DirectoryIfMissing -Path $extractPath
    New-DirectoryIfMissing -Path $backupDir

    try {
        $previousProgressPreference = $ProgressPreference
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $script:PatchUrl -OutFile $zipPath -UseBasicParsing
        }
        finally {
            $ProgressPreference = $previousProgressPreference
        }

        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

        $files = Get-ChildItem -LiteralPath $extractPath -File -Recurse
        if ($files.Count -eq 0) {
            throw 'Patch zip did not contain any files.'
        }

        foreach ($file in $files) {
            if (-not (Test-SafeExtractedFile -Root $extractPath -FilePath $file.FullName)) {
                throw "Unsafe file path in patch zip: $($file.FullName)"
            }

            $rootPrefix = [System.IO.Path]::GetFullPath($extractPath).TrimEnd('\') + '\'
            $relative = $file.FullName.Substring($rootPrefix.Length)
            if ($relative -match '(^|\\)\.\.(\\|$)') {
                throw "Unsafe relative path in patch zip: $relative"
            }

            $targetRelative = Get-PatchTargetRelativePath -RelativePath $relative
            $target = Join-Path $FfxiFolder $targetRelative
            Copy-FileWithBackup -Source $file.FullName -Destination $target -BackupDirectory $backupDir -BackupRelativePath $targetRelative
        }

        Show-Info "Patch applied. Backups are in:`r`n$backupDir"
    }
    finally {
        if (Test-Path -LiteralPath $work) {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Find-WindowerProfileNode {
    param(
        [Parameter(Mandatory)][xml]$Document,
        [Parameter(Mandatory)][string]$ProfileName
    )

    $profiles = $Document.SelectNodes("//*[local-name()='profile']")
    foreach ($profile in $profiles) {
        if ($profile.Attributes -and $profile.Attributes['name'] -and $profile.Attributes['name'].Value -eq $ProfileName) {
            return $profile
        }

        $nameNode = $profile.SelectSingleNode("*[local-name()='name']")
        if ($nameNode -and $nameNode.InnerText -eq $ProfileName) {
            return $profile
        }
    }

    return $null
}

function Set-XmlChildText {
    param(
        [Parameter(Mandatory)][xml]$Document,
        [Parameter(Mandatory)]$Parent,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )

    $child = $Parent.SelectSingleNode("*[local-name()='$Name']")
    if (-not $child) {
        $child = $Document.CreateElement($Name)
        $Parent.AppendChild($child) | Out-Null
    }
    $child.InnerText = $Value
}

function Update-WindowerProfile {
    param(
        [Parameter(Mandatory)][string]$SettingsXmlPath,
        [Parameter(Mandatory)][string]$ProfileName,
        [Parameter(Mandatory)][string]$XiloaderCommand
    )

    if (-not (Test-Path -LiteralPath $SettingsXmlPath -PathType Leaf)) {
        throw "Windower settings.xml not found: $SettingsXmlPath"
    }
    if ([string]::IsNullOrWhiteSpace($ProfileName)) {
        throw 'Enter the Windower profile name first.'
    }

    [xml]$doc = Get-Content -LiteralPath $SettingsXmlPath -Raw
    $profile = Find-WindowerProfileNode -Document $doc -ProfileName $ProfileName.Trim()
    if (-not $profile) {
        throw "Could not find a Windower profile named '$ProfileName'. Create it in Windower first, then run this again."
    }

    $backup = "$SettingsXmlPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $SettingsXmlPath -Destination $backup -Force

    Set-XmlChildText -Document $doc -Parent $profile -Name 'args' -Value $XiloaderCommand
    Set-XmlChildText -Document $doc -Parent $profile -Name 'executable' -Value 'xiloader.exe'
    $doc.Save($SettingsXmlPath)

    Show-Info "Windower profile updated.`r`n`r`nBackup:`r`n$backup"
}

function New-AshitaBootConfig {
    param(
        [Parameter(Mandatory)][string]$AshitaFolder,
        [Parameter(Mandatory)][string]$ConfigName,
        [Parameter(Mandatory)][string]$XiloaderPath,
        [Parameter(Mandatory)][string]$XiloaderCommand
    )

    if (-not (Test-Path -LiteralPath $AshitaFolder -PathType Container)) {
        throw "Ashita folder not found: $AshitaFolder"
    }
    if (-not (Test-Path -LiteralPath $XiloaderPath -PathType Leaf)) {
        throw "xiloader.exe not found: $XiloaderPath"
    }
    if ([string]::IsNullOrWhiteSpace($ConfigName)) {
        throw 'Enter an Ashita config file name first.'
    }

    if (-not $ConfigName.EndsWith('.ini', [StringComparison]::OrdinalIgnoreCase)) {
        $ConfigName = $ConfigName + '.ini'
    }

    $bootDir = Join-Path $AshitaFolder 'config\boot'
    New-DirectoryIfMissing -Path $bootDir
    $configPath = Join-Path $bootDir $ConfigName

    if (Test-Path -LiteralPath $configPath) {
        $backup = "$configPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $configPath -Destination $backup -Force
    }

    $content = @"
[ashita.launcher]
autoclose = 1
name = Supernova

[ashita.boot]
file = $XiloaderPath
command = $XiloaderCommand
gamemodule =
script =
args =

[ashita.language]
playonline = 2
ashita = 2

[ashita.logging]
level = 5
crashdumps = 1
"@

    Set-Content -LiteralPath $configPath -Value $content -Encoding ASCII
    Show-Info "Ashita boot config written:`r`n$configPath"
    return $configPath
}

function Install-XiloaderForAshita {
    param(
        [Parameter(Mandatory)][string]$AshitaFolder,
        [Parameter(Mandatory)][string]$XiloaderPath
    )

    if (-not (Test-Path -LiteralPath $XiloaderPath -PathType Leaf)) {
        throw "xiloader.exe not found: $XiloaderPath"
    }
    if (-not (Test-Path -LiteralPath $AshitaFolder -PathType Container)) {
        throw "Ashita folder not found: $AshitaFolder"
    }

    $preferred = Join-Path $AshitaFolder 'ffxi-bootmod'
    if (-not (Test-Path -LiteralPath $preferred -PathType Container)) {
        $preferred = Join-Path $AshitaFolder 'bootloader'
    }
    New-DirectoryIfMissing -Path $preferred

    $destination = Join-Path $preferred 'xiloader.exe'
    Copy-Item -LiteralPath $XiloaderPath -Destination $destination -Force
    Show-Info "xiloader.exe copied to:`r`n$destination"
    return $destination
}

$settings = Load-Settings
$savedPassword = Unprotect-Password -ProtectedPassword $settings.PasswordProtected

$form = New-Object System.Windows.Forms.Form
$form.Text = $script:AppName
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(780, 640)
$form.MinimumSize = New-Object System.Drawing.Size(760, 620)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)

function New-TabPage {
    param([string]$Text)
    $page = New-Object System.Windows.Forms.TabPage
    $page.Text = $Text
    $page.Padding = New-Object System.Windows.Forms.Padding(12)
    $tabs.TabPages.Add($page) | Out-Null
    return $page
}

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 160)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, 24)
    $label.TextAlign = 'MiddleLeft'
    return $label
}

function New-TextBox {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 460)
    $box = New-Object System.Windows.Forms.TextBox
    $box.Text = $Text
    $box.Location = New-Object System.Drawing.Point($X, $Y)
    $box.Size = New-Object System.Drawing.Size($Width, 24)
    return $box
}

function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 110)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($Width, 30)
    return $button
}

$launchPage = New-TabPage -Text 'Launch'
$pathsPage = New-TabPage -Text 'Paths'
$toolsPage = New-TabPage -Text 'Tools'

$launchPage.Controls.Add((New-Label -Text 'Server' -X 18 -Y 20))
$serverBox = New-TextBox -Text $script:ServerHost -X 180 -Y 20 -Width 480
$serverBox.ReadOnly = $true
$launchPage.Controls.Add($serverBox)

$launchPage.Controls.Add((New-Label -Text 'Username' -X 18 -Y 60))
$usernameBox = New-TextBox -Text $settings.Username -X 180 -Y 60 -Width 260
$launchPage.Controls.Add($usernameBox)

$launchPage.Controls.Add((New-Label -Text 'Password' -X 18 -Y 100))
$passwordBox = New-TextBox -Text $savedPassword -X 180 -Y 100 -Width 260
$passwordBox.UseSystemPasswordChar = $true
$launchPage.Controls.Add($passwordBox)

$rememberPasswordBox = New-Object System.Windows.Forms.CheckBox
$rememberPasswordBox.Text = 'Remember password for this Windows user'
$rememberPasswordBox.Location = New-Object System.Drawing.Point(180, 132)
$rememberPasswordBox.Size = New-Object System.Drawing.Size(300, 24)
$rememberPasswordBox.Checked = [bool]$settings.RememberPassword
$launchPage.Controls.Add($rememberPasswordBox)

$runElevatedBox = New-Object System.Windows.Forms.CheckBox
$runElevatedBox.Text = 'Run launch target as administrator'
$runElevatedBox.Location = New-Object System.Drawing.Point(180, 162)
$runElevatedBox.Size = New-Object System.Drawing.Size(300, 24)
$runElevatedBox.Checked = [bool]$settings.RunElevated
$launchPage.Controls.Add($runElevatedBox)

$launchDirectButton = New-Button -Text 'Launch xiloader' -X 180 -Y 210 -Width 150
$launchWindowerButton = New-Button -Text 'Launch Windower' -X 340 -Y 210 -Width 150
$launchAshitaButton = New-Button -Text 'Launch Ashita' -X 500 -Y 210 -Width 150
$launchPage.Controls.AddRange(@($launchDirectButton, $launchWindowerButton, $launchAshitaButton))

$launchPage.Controls.Add((New-Label -Text 'xiloader args' -X 18 -Y 270))
$commandPreviewBox = New-TextBox -Text '' -X 180 -Y 270 -Width 480
$commandPreviewBox.ReadOnly = $true
$launchPage.Controls.Add($commandPreviewBox)

$saveButton = New-Button -Text 'Save Settings' -X 180 -Y 320 -Width 150
$copyArgsButton = New-Button -Text 'Copy Args' -X 340 -Y 320 -Width 110
$launchPage.Controls.AddRange(@($saveButton, $copyArgsButton))

$pathsPage.Controls.Add((New-Label -Text 'PlayOnline folder' -X 18 -Y 20))
$polFolderBox = New-TextBox -Text $settings.PlayOnlineFolder -X 180 -Y 20
$browsePolButton = New-Button -Text 'Browse' -X 650 -Y 18 -Width 80
$pathsPage.Controls.AddRange(@($polFolderBox, $browsePolButton))

$pathsPage.Controls.Add((New-Label -Text 'FFXI folder' -X 18 -Y 60))
$ffxiFolderBox = New-TextBox -Text $settings.FfxiFolder -X 180 -Y 60
$browseFfxiButton = New-Button -Text 'Browse' -X 650 -Y 58 -Width 80
$pathsPage.Controls.AddRange(@($ffxiFolderBox, $browseFfxiButton))

$pathsPage.Controls.Add((New-Label -Text 'xiloader.exe' -X 18 -Y 100))
$xiloaderBox = New-TextBox -Text $settings.XiloaderPath -X 180 -Y 100
$browseXiloaderButton = New-Button -Text 'Browse' -X 650 -Y 98 -Width 80
$pathsPage.Controls.AddRange(@($xiloaderBox, $browseXiloaderButton))

$pathsPage.Controls.Add((New-Label -Text 'Windower.exe' -X 18 -Y 160))
$windowerExeBox = New-TextBox -Text $settings.WindowerExe -X 180 -Y 160
$browseWindowerExeButton = New-Button -Text 'Browse' -X 650 -Y 158 -Width 80
$pathsPage.Controls.AddRange(@($windowerExeBox, $browseWindowerExeButton))

$pathsPage.Controls.Add((New-Label -Text 'Windower settings.xml' -X 18 -Y 200))
$windowerSettingsBox = New-TextBox -Text $settings.WindowerSettings -X 180 -Y 200
$browseWindowerSettingsButton = New-Button -Text 'Browse' -X 650 -Y 198 -Width 80
$pathsPage.Controls.AddRange(@($windowerSettingsBox, $browseWindowerSettingsButton))

$pathsPage.Controls.Add((New-Label -Text 'Windower profile' -X 18 -Y 240))
$windowerProfileBox = New-TextBox -Text $settings.WindowerProfile -X 180 -Y 240 -Width 260
$pathsPage.Controls.Add($windowerProfileBox)

$pathsPage.Controls.Add((New-Label -Text 'Ashita folder' -X 18 -Y 300))
$ashitaFolderBox = New-TextBox -Text $settings.AshitaFolder -X 180 -Y 300
$browseAshitaButton = New-Button -Text 'Browse' -X 650 -Y 298 -Width 80
$pathsPage.Controls.AddRange(@($ashitaFolderBox, $browseAshitaButton))

$pathsPage.Controls.Add((New-Label -Text 'Ashita config' -X 18 -Y 340))
$ashitaConfigBox = New-TextBox -Text $settings.AshitaConfigName -X 180 -Y 340 -Width 260
$pathsPage.Controls.Add($ashitaConfigBox)

$patchButton = New-Button -Text 'Download/Apply Patch' -X 180 -Y 28 -Width 170
$toolsPage.Controls.Add($patchButton)

$windowerUpdateButton = New-Button -Text 'Patch Windower Profile' -X 180 -Y 78 -Width 170
$toolsPage.Controls.Add($windowerUpdateButton)

$ashitaInstallXiloaderButton = New-Button -Text 'Copy xiloader to Ashita' -X 180 -Y 128 -Width 170
$ashitaConfigButton = New-Button -Text 'Write Ashita Config' -X 360 -Y 128 -Width 160
$toolsPage.Controls.AddRange(@($ashitaInstallXiloaderButton, $ashitaConfigButton))

$openLogButton = New-Button -Text 'Open Log Folder' -X 180 -Y 190 -Width 170
$toolsPage.Controls.Add($openLogButton)

$notesBox = New-Object System.Windows.Forms.TextBox
$notesBox.Multiline = $true
$notesBox.ReadOnly = $true
$notesBox.ScrollBars = 'Vertical'
$notesBox.Location = New-Object System.Drawing.Point(180, 250)
$notesBox.Size = New-Object System.Drawing.Size(500, 210)
$notesBox.Text = "Setup notes:`r`n`r`n1. xiloader.exe should be version 2.0.0 or newer for Supernova.`r`n2. Windower users should create a profile in Windower first, then this launcher can add the Supernova args and executable entries.`r`n3. Ashita v4 users can generate config\boot\supernova.ini here, then launch through ashita-cli.exe.`r`n4. The patch tool downloads the configured Dropbox zip and backs up overwritten files."
$toolsPage.Controls.Add($notesBox)

function Read-UiSettings {
    $protectedPassword = ''
    if ($rememberPasswordBox.Checked) {
        $protectedPassword = Protect-Password -Password $passwordBox.Text
    }

    [pscustomobject]@{
        PlayOnlineFolder = $polFolderBox.Text
        FfxiFolder = $ffxiFolderBox.Text
        XiloaderPath = $xiloaderBox.Text
        Username = $usernameBox.Text
        PasswordProtected = $protectedPassword
        RememberPassword = $rememberPasswordBox.Checked
        RunElevated = $runElevatedBox.Checked
        WindowerExe = $windowerExeBox.Text
        WindowerSettings = $windowerSettingsBox.Text
        WindowerProfile = $windowerProfileBox.Text
        AshitaFolder = $ashitaFolderBox.Text
        AshitaConfigName = $ashitaConfigBox.Text
    }
}

function Save-UiSettings {
    Save-Settings -Settings (Read-UiSettings)
    Show-Info 'Settings saved.'
}

function Update-CommandPreview {
    $commandPreviewBox.Text = Get-XiloaderCommandText -Username $usernameBox.Text -Password $passwordBox.Text
}

$usernameBox.Add_TextChanged({ Update-CommandPreview })
$passwordBox.Add_TextChanged({ Update-CommandPreview })
Update-CommandPreview

$browsePolButton.Add_Click({
    $path = Browse-Folder -Description 'Choose the PlayOnlineViewer folder.' -SelectedPath $polFolderBox.Text
    if ($path) {
        $polFolderBox.Text = $path
        $candidate = Join-Path $path 'xiloader.exe'
        if (Test-Path -LiteralPath $candidate) {
            $xiloaderBox.Text = $candidate
        }
    }
})

$browseFfxiButton.Add_Click({
    $path = Browse-Folder -Description 'Choose the FINAL FANTASY XI folder.' -SelectedPath $ffxiFolderBox.Text
    if ($path) {
        $ffxiFolderBox.Text = $path
    }
})

$browseXiloaderButton.Add_Click({
    $path = Browse-File -Title 'Choose xiloader.exe' -InitialDirectory (Split-Path -Parent $xiloaderBox.Text)
    if ($path) {
        $xiloaderBox.Text = $path
    }
})

$browseWindowerExeButton.Add_Click({
    $path = Browse-File -Title 'Choose Windower.exe' -InitialDirectory (Split-Path -Parent $windowerExeBox.Text)
    if ($path) {
        $windowerExeBox.Text = $path
        $settingsPath = Join-Path (Split-Path -Parent $path) 'settings.xml'
        if (Test-Path -LiteralPath $settingsPath) {
            $windowerSettingsBox.Text = $settingsPath
        }
    }
})

$browseWindowerSettingsButton.Add_Click({
    $path = Browse-File -Title 'Choose Windower settings.xml' -Filter 'XML files (*.xml)|*.xml|All files (*.*)|*.*' -InitialDirectory (Split-Path -Parent $windowerSettingsBox.Text)
    if ($path) {
        $windowerSettingsBox.Text = $path
    }
})

$browseAshitaButton.Add_Click({
    $path = Browse-Folder -Description 'Choose the Ashita folder.' -SelectedPath $ashitaFolderBox.Text
    if ($path) {
        $ashitaFolderBox.Text = $path
    }
})

$saveButton.Add_Click({
    try { Save-UiSettings } catch { Show-Error $_.Exception.Message }
})

$copyArgsButton.Add_Click({
    Update-CommandPreview
    [System.Windows.Forms.Clipboard]::SetText($commandPreviewBox.Text)
    Show-Info 'xiloader arguments copied to the clipboard.'
})

$launchDirectButton.Add_Click({
    try {
        Save-Settings -Settings (Read-UiSettings)
        Start-ExternalProcess -FilePath $xiloaderBox.Text -Arguments (Build-XiloaderArguments -Username $usernameBox.Text -Password $passwordBox.Text) -WorkingDirectory (Split-Path -Parent $xiloaderBox.Text) -RunElevated $runElevatedBox.Checked
    }
    catch { Show-Error $_.Exception.Message }
})

$launchWindowerButton.Add_Click({
    try {
        Save-Settings -Settings (Read-UiSettings)
        Start-ExternalProcess -FilePath $windowerExeBox.Text -Arguments @('-p', $windowerProfileBox.Text) -WorkingDirectory (Split-Path -Parent $windowerExeBox.Text) -RunElevated $runElevatedBox.Checked
    }
    catch { Show-Error $_.Exception.Message }
})

$launchAshitaButton.Add_Click({
    try {
        Save-Settings -Settings (Read-UiSettings)
        $configName = $ashitaConfigBox.Text
        if (-not $configName.EndsWith('.ini', [StringComparison]::OrdinalIgnoreCase)) {
            $configName = $configName + '.ini'
        }
        $ashitaCli = Join-Path $ashitaFolderBox.Text 'ashita-cli.exe'
        Start-ExternalProcess -FilePath $ashitaCli -Arguments @($configName) -WorkingDirectory $ashitaFolderBox.Text -RunElevated $runElevatedBox.Checked
    }
    catch { Show-Error $_.Exception.Message }
})

$patchButton.Add_Click({
    try {
        Save-Settings -Settings (Read-UiSettings)
        Apply-PatchZip -FfxiFolder $ffxiFolderBox.Text
    }
    catch { Show-Error $_.Exception.Message }
})

$windowerUpdateButton.Add_Click({
    try {
        Save-Settings -Settings (Read-UiSettings)
        Update-WindowerProfile -SettingsXmlPath $windowerSettingsBox.Text -ProfileName $windowerProfileBox.Text -XiloaderCommand (Get-XiloaderCommandText -Username $usernameBox.Text -Password $passwordBox.Text)
    }
    catch { Show-Error $_.Exception.Message }
})

$ashitaInstallXiloaderButton.Add_Click({
    try {
        Save-Settings -Settings (Read-UiSettings)
        $copied = Install-XiloaderForAshita -AshitaFolder $ashitaFolderBox.Text -XiloaderPath $xiloaderBox.Text
        $xiloaderBox.Text = $copied
    }
    catch { Show-Error $_.Exception.Message }
})

$ashitaConfigButton.Add_Click({
    try {
        Save-Settings -Settings (Read-UiSettings)
        New-AshitaBootConfig -AshitaFolder $ashitaFolderBox.Text -ConfigName $ashitaConfigBox.Text -XiloaderPath $xiloaderBox.Text -XiloaderCommand (Get-XiloaderCommandText -Username $usernameBox.Text -Password $passwordBox.Text) | Out-Null
    }
    catch { Show-Error $_.Exception.Message }
})

$openLogButton.Add_Click({
    try {
        New-DirectoryIfMissing -Path $script:SettingsDir
        $explorerPath = Join-Path $env:WINDIR 'explorer.exe'
        Start-ExternalProcess -FilePath $explorerPath -Arguments @($script:SettingsDir) -RunElevated $false
    }
    catch { Show-Error $_.Exception.Message }
})

$form.Add_FormClosing({
    try {
        Save-Settings -Settings (Read-UiSettings)
    }
    catch {
        Write-Log "Failed to save settings on close: $($_.Exception.Message)"
    }
})

try {
    [System.Windows.Forms.Application]::Run($form)
}
catch {
    Show-Error $_.Exception.Message
}
