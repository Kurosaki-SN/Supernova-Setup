@echo off
REM Start a scoped environment so SCRIPT_DIR does not leak into the caller.
setlocal
REM %~dp0 is the folder that contains this command file after install.
set "SCRIPT_DIR=%~dp0"
REM Bypass applies only to this process so the assistant can run on systems
REM where unsigned local PowerShell scripts are blocked by default.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%SupernovaSetupAssistant.ps1"
REM End the scoped environment before returning to Windows.
endlocal
