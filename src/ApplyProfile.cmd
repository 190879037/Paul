@echo off
REM Use script directory (works wherever ClearyDisplay is installed)
set "APPDIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%APPDIR%ApplyProfile.ps1" -Force
