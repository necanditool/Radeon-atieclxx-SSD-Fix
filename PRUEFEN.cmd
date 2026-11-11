@echo off
title Radeon-atieclxx-SSD-Fix - Status
if not exist "%~dp0Skript\pruefen.ps1" (
  echo Bitte die ZIP-Datei zuerst vollstaendig entpacken und dann PRUEFEN.cmd starten.
  echo Please extract the ZIP file completely first, then start PRUEFEN.cmd.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Skript\pruefen.ps1"
echo.
pause
