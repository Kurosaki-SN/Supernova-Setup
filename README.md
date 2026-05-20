# Supernova FFXI Launcher

Portable Windows launcher helper for Supernova FFXI.

This package does not include Final Fantasy XI files, xiloader, Windower, Ashita, or copyrighted game assets. It only helps configure and launch an existing local installation.

## What It Does

- Launches `xiloader.exe` with `--server login.supernovaffxi.com`.
- Optionally includes `--user` and `--password` for autologin.
- Saves launcher settings under `%LOCALAPPDATA%\SupernovaFFXILauncher`.
- Can patch an existing Windower profile by adding:
  - `<args>--server login.supernovaffxi.com ...</args>`
  - `<executable>xiloader.exe</executable>`
- Can create an Ashita v4 boot config under `config\boot\supernova.ini`.
- Can download and apply the configured Supernova custom DATs zip and update patch zip, backing up overwritten files first.
- The installer can optionally download pinned `xiloader.exe` v2.0.1 and place it beside `pol.exe`.
- The installer can optionally download and apply the custom DATs and patch during installation.

## For Players

Regular players do not need Inno Setup. They only need the built installer:

```text
SupernovaFFXILauncherSetup.exe
```

During installation, select `Download and install Supernova-compatible xiloader v2.0.1` to have the installer place the pinned 2.0.x xiloader beside `pol.exe` in PlayOnlineViewer. Existing `xiloader.exe` files are backed up first. This step verifies the official v2.0.1 release MD5.

Select `Download and install Supernova custom DATs and patch` to have the installer download both Dropbox archives. The custom DAT archive maps DAT/music files into their documented FFXI subfolders, while the update patch archive installs root-level files such as DLLs, config files, and `polboot.exe` directly into the selected `FINAL FANTASY XI` folder. If FFXI or PlayOnline is installed under `Program Files`, Windows may show an administrator prompt for those setup steps.

## Run Without Installer

Double-click:

```bat
SupernovaLauncher.cmd
```

PowerShell may show a UAC prompt when launching tools if "Run launch target as administrator" is enabled.

## Recommended Setup

1. Install or update Final Fantasy XI normally.
2. Put `xiloader.exe` version 2.0.1 somewhere local, or use the installer's optional xiloader step.
3. Open the launcher and confirm the paths on the `Paths` tab.
4. For Windower, create a profile in Windower first, then use `Tools > Patch Windower Profile`.
5. For Ashita v4, use `Tools > Copy xiloader to Ashita`, then `Tools > Write Ashita Config`.
6. Use the `Launch` tab for direct, Windower, or Ashita launch.

## Developer Build

This section is only for someone rebuilding `SupernovaFFXILauncherSetup.exe` from source. Players who already have the `.exe` installer can ignore it.

Install Inno Setup, then compile:

```powershell
iscc .\installer\SupernovaLauncher.iss
```

The installer will be written to `installer\dist\SupernovaFFXILauncherSetup.exe`.

## Notes

- The password checkbox stores the password using Windows user-scoped encryption. It is intended for convenience, not shared-machine security.
- Autologin still passes the password to `xiloader` as a process argument because that is how the server setup documents the option.
- The patch tool extracts the zip into a temporary folder, rejects unsafe relative paths, and backs up files it overwrites.
