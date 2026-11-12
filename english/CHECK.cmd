@echo off
title Radeon-atieclxx-SSD-Fix - Status
if not exist "%~dp0Script\check.ps1" (
  echo Please extract the ZIP file completely first and then start CHECK.cmd.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Script\check.ps1"
echo.
pause
