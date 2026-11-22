@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
set "SCRIPT_DIR=%~dp0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%01_INSTALL_ALL.ps1"
set "RC=%ERRORLEVEL%"
exit /b %RC%
