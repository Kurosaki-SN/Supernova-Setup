@echo off
REM Start a scoped environment so SCRIPT_DIR does not leak into the caller.
setlocal
REM %~dp0 is the folder that contains this command file after install.
set "SCRIPT_DIR=%~dp0"
REM Keep launcher errors visible on test machines instead of letting the console
REM close immediately after a PowerShell startup failure.
set "LOG_DIR=%LOCALAPPDATA%\SupernovaSetupAssistant"
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
set "CRASH_LOG=%LOG_DIR%\LauncherCrash.log"
REM Bypass applies only to this process so the assistant can run on systems
REM where unsigned local PowerShell scripts are blocked by default.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%SupernovaSetupAssistant.ps1" 1>>"%CRASH_LOG%" 2>>&1
if errorlevel 1 (
    echo Supernova Setup Assistant could not start.
    echo.
    echo A crash log was written to:
    echo %CRASH_LOG%
    echo.
    start "" notepad.exe "%CRASH_LOG%"
    pause
)
REM End the scoped environment before returning to Windows.
endlocal
