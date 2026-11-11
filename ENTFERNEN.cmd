@echo off
title Radeon-atieclxx-SSD-Fix - Entfernen / Remove
if not exist "%~dp0Skript\entfernen.ps1" (
  echo Bitte die ZIP-Datei zuerst vollstaendig entpacken und dann ENTFERNEN.cmd starten.
  echo Please extract the ZIP file completely first, then start ENTFERNEN.cmd.
  pause
  exit /b 1
)
fltmc >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Skript\entfernen.ps1"
echo.
pause
