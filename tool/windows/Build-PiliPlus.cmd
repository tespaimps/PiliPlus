@echo off
where pwsh.exe >nul 2>nul
if errorlevel 1 (
    echo PowerShell 7 is required to run this build.
    pause
    exit /b 1
)
pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0.tools\package-with-progress.ps1" %*
set "build_exit=%errorlevel%"
pause
exit /b %build_exit%
