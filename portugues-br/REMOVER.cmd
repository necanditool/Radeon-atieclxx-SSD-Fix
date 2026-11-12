@echo off
title Radeon-atieclxx-SSD-Fix - Remover
if not exist "%~dp0Script\remover.ps1" (
  echo Extraia o arquivo ZIP por completo primeiro e depois inicie o REMOVER.cmd.
  pause
  exit /b 1
)
fltmc >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Script\remover.ps1"
echo.
pause
