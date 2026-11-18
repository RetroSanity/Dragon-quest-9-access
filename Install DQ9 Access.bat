@echo off
rem Dragon Quest IX Access: puts the mod into your own copy of the Dragon Quest IX PC version.
rem Double-click this. Run it again at any time (for example after updating the PC version).
setlocal
cd /d "%~dp0"
title Dragon Quest IX Access - install
set "PS1=%~dp0mod\installer\install.ps1"
if not exist "%PS1%" set "PS1=%~dp0installer\install.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
echo.
pause
