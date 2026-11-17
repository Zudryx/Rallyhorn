@echo off
rem Installs the newest Rallyhorn build, TEST builds included (GitHub
rem pre-releases). Use "Update Rallyhorn.bat" for normal releases.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-Rallyhorn.ps1" -Testing %*
echo.
pause
