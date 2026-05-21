@echo off
REM Start a scoped environment so SCRIPT_DIR does not leak into the caller.
setlocal
REM %~dp0 is the folder that contains this command file after install.
set "SCRIPT_DIR=%~dp0"
REM Keep launcher errors visible on test machines instead of letting the console
REM close immediately after a PowerShell startup failure.
if "%LOCALAPPDATA%"=="" (
    set "LOG_DIR=%TEMP%\SupernovaSetupAssistant"
) else (
    set "LOG_DIR=%LOCALAPPDATA%\SupernovaSetupAssistant"
)
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
set "CRASH_LOG=%LOG_DIR%\LauncherCrash.log"
set "DESKTOP_CRASH_LOG=%USERPROFILE%\Desktop\SupernovaSetupAssistant-LauncherCrash.log"
set "POWERSHELL_EXE=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%POWERSHELL_EXE%" set "POWERSHELL_EXE=powershell.exe"
echo ==== Supernova Setup Assistant launch %DATE% %TIME% ====>>"%CRASH_LOG%"
echo Script folder: "%SCRIPT_DIR%">>"%CRASH_LOG%"
echo PowerShell: "%POWERSHELL_EXE%">>"%CRASH_LOG%"
REM Bypass applies only to this process so the assistant can run on systems
REM where unsigned local PowerShell scripts are blocked by default.
"%POWERSHELL_EXE%" -NoProfile -STA -ExecutionPolicy Bypass -File "%SCRIPT_DIR%SupernovaSetupAssistant.ps1" 1>>"%CRASH_LOG%" 2>>&1
if errorlevel 1 (
    copy /Y "%CRASH_LOG%" "%DESKTOP_CRASH_LOG%" >nul 2>nul
    echo Supernova Setup Assistant could not start.
    echo.
    echo A crash log was written to this hidden AppData path:
    echo %CRASH_LOG%
    echo.
    echo A copy was also placed on the Desktop here:
    echo %DESKTOP_CRASH_LOG%
    echo.
    start "" notepad.exe "%CRASH_LOG%"
    pause
)
REM End the scoped environment before returning to Windows.
endlocal
