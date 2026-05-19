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
- Can download and apply the configured Dropbox patch zip, backing up overwritten files first.
- The installer can optionally download and apply the patch during installation.

## Run It

Double-click:

```bat
SupernovaLauncher.cmd
```

PowerShell may show a UAC prompt when launching tools if "Run launch target as administrator" is enabled.

## Recommended Setup

1. Install or update Final Fantasy XI normally.
2. Put `xiloader.exe` version 2.0.0 or newer somewhere local.
3. Open the launcher and confirm the paths on the `Paths` tab.
4. For Windower, create a profile in Windower first, then use `Tools > Patch Windower Profile`.
5. For Ashita v4, use `Tools > Copy xiloader to Ashita`, then `Tools > Write Ashita Config`.
6. Use the `Launch` tab for direct, Windower, or Ashita launch.

## Build The Installer

Install Inno Setup, then compile:

```powershell
iscc .\installer\SupernovaLauncher.iss
```

The installer will be written to `installer\dist\SupernovaFFXILauncherSetup.exe`.

During installation, select `Download and apply the Supernova FFXI patch now` to have the installer download the Dropbox patch and place the known DAT/music files into their documented FFXI subfolders. If FFXI is installed under `Program Files`, Windows may show an administrator prompt for the patch step.

## Notes

- The password checkbox stores the password using Windows user-scoped encryption. It is intended for convenience, not shared-machine security.
- Autologin still passes the password to `xiloader` as a process argument because that is how the server setup documents the option.
- The patch tool extracts the zip into a temporary folder, rejects unsafe relative paths, and backs up files it overwrites.
