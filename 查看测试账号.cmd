@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0scripts\desktop.ps1" -Action Accounts
if errorlevel 1 pause
