# Supernova Setup Assistant

Guided Windows setup helper for the Supernova FFXI private server.

This is not a replacement for Windower or Ashita. Supernova players should configure and play through Windower or Ashita; direct `xiloader.exe` launch is kept only as an advanced support tool.

## What It Does

- Guides new, existing, and repair/update installs with a step-by-step wizard.
- Opens the official Square Enix FFXI install page instead of bundling client files: `https://www.playonline.com/ff11us/download/media/install_win.html`.
- Downloads and installs/verifies Microsoft Visual C++ Redistributable 2015 x86 from Microsoft's official page.
- Downloads pinned Supernova-compatible `xiloader.exe` v2.0.1, verifies it, backs up any existing copy, and places it beside `pol.exe`.
- Guides the player to set both `pol.exe` and `xiloader.exe` to **Run as administrator**, then validates both compatibility flags.
- Opens Windower and Ashita websites for manual download and install. Windower is the recommended play method.
- Installs Supernova custom DATs and root-level patch files into `FINAL FANTASY XI`, using bundled Supernova zip archives when they are included with the installer.
- Backs up overwritten files before replacing them.
- Offers an optional `vulgar2.dic` cleanup that backs up the file before removing it from the selected `FINAL FANTASY XI` folder.
- Configures a Windower profile named `Supernova` with:
  - `<executable>xiloader.exe</executable>`
  - `<args>--server login.supernovaffxi.com</args>`
- Windower users can update the profile args after account creation to:
  - `<args>--server login.supernovaffxi.com --user your_username --password your_password</args>`
- The Windower password is not saved in the assistant settings, but it is written into Windower `settings.xml` when the login args are updated.
- Writes Ashita `config\boot\supernova.ini` and points it at `ffxi-bootmod\xiloader.exe`.
- Ashita users are guided to run the Ashita installer, then install the pinned xiloader v2.0.1 bootloader into `ffxi-bootmod`.
- Ashita configuration sets the boot file to `ffxi-bootmod\xiloader.exe`, first with `--server login.supernovaffxi.com`, then after account creation with `--server login.supernovaffxi.com --user your_username --password your_password`.
- The Ashita password is not saved in the assistant settings, but it is written into Ashita's profile config when the account command is updated.
- Exports a diagnostic report with detected paths, hashes, config status, logs, and missing setup requirements.

## For Players

Players do not need Inno Setup. They only need the built installer:

```text
SupernovaInstallHelper.exe
```

Run the installer, then launch **Supernova Setup Assistant**. The assistant installs itself under your user profile and only asks for administrator approval when a selected PlayOnline or FFXI folder is protected by Windows.

## Setup Paths

Choose one of the main wizard flows:

- **New Installation**: opens the official FFXI download page, guides the user to install PlayOnline Viewer and Final Fantasy XI Online, select the parent game install folder that contains both installed folders, run PlayOnline updates, save Existing User settings, install Supernova patch files, walk through Check Files/File Repair with guide screenshots, install the MSVC 2015 x86 runtime, install Supernova DATs, optionally remove `vulgar2.dic`, download xiloader beside `pol.exe`, set both `pol.exe` and `xiloader.exe` to run as administrator, then branches based on the selected play method. Windower users are guided to start Windower, create a profile with the plus button, edit it with the pencil icon, create a desktop shortcut with the pin icon, configure the profile XML, launch the profile to create an account, then update the Windower args with their username and password. Ashita users are guided to install Ashita, install the xiloader bootloader into `ffxi-bootmod`, configure the Supernova entry, create a desktop shortcut, launch the profile to create an account, then update the Ashita command with their username and password.
- **Existing Installation**: detects your current PlayOnline/FFXI folders, installs or verifies the MSVC runtime and xiloader, applies Supernova files, then configures Windower or Ashita.
- **Repair / Update Existing Installation**: moves `VTABLE.DAT` into a backup folder, opens PlayOnline, guides you through Check Files > FINAL FANTASY XI > File Repair, then reapplies Supernova files.

The assistant does not automate PlayOnline UI clicks.

The setup is ready only when **Validate Setup** shows every item as `PASS`.

## Run Without Installer

Double-click:

```bat
SupernovaSetupAssistant.cmd
```

## Developer Build

This section is only for someone rebuilding the installer from source. Players who already have `SupernovaInstallHelper.exe` can ignore it.

Install Inno Setup, then compile:

```powershell
iscc .\installer\SupernovaSetupAssistant.iss
```

The installer will be written to:

```text
installer\dist\SupernovaInstallHelper.exe
```

## Safe Testing

To test without touching your real install, create fake folders inside this project, for example:

```text
safe-test\GameRoot\PlayOnlineViewer\pol.exe
safe-test\GameRoot\PlayOnlineViewer\xiloader.exe
safe-test\GameRoot\FINAL FANTASY XI\ROM
safe-test\GameRoot\FINAL FANTASY XI\ROM3
safe-test\GameRoot\FINAL FANTASY XI\ROM4\1
safe-test\GameRoot\FINAL FANTASY XI\sound4
```

Browse the assistant to those copied or fake folders. Do not click the real install/patch buttons against your live game folder unless you intend to change it.

## Notes

- Supernova server host: `login.supernovaffxi.com`.
- MSVC 2015 x86 runtime is downloaded from Microsoft's official Visual C++ Redistributable page: `https://www.microsoft.com/en-ca/download/details.aspx?id=48145`.
- Windower download page: `https://www.windower.net/`.
- Ashita download page: `https://www.ashitaxi.com/`.
- NOTE: WINDOWER WILL INSTALL INTO WHATEVER DIRECTORY YOU PLACE THE DOWNLOADED EXECUTABLE FROM.
- NOTE: ASHITA WILL INSTALL INTO WHATEVER DIRECTORY YOU PLACE THE DOWNLOADED EXECUTABLE FROM.
- xiloader is downloaded from the pinned LandSandBoat v2.0.1 release asset and checked by MD5.
- Ashita bootloader xiloader is downloaded from the pinned LandSandBoat v2.0.1 release asset and checked by MD5 before being placed in `ffxi-bootmod`.
- DATs and patch files are installed from bundled Supernova zip archives when present under the assistant `payload` folder. If those archives are missing, the helper falls back to the configured Supernova Dropbox links at install time.
- Optional `vulgar2.dic` cleanup only searches inside the selected `FINAL FANTASY XI` folder and stores a backup under `%LOCALAPPDATA%\SupernovaSetupAssistant\Backups`.
- Logs and backups are stored under `%LOCALAPPDATA%\SupernovaSetupAssistant`.
