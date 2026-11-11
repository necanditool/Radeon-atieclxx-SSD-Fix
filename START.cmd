@echo off
title Radeon-atieclxx-SSD-Fix
if not exist "%~dp0Skript\Oberflaeche.ps1" (
  echo Bitte die ZIP-Datei zuerst vollstaendig entpacken und dann START.cmd starten.
  echo Please extract the ZIP file completely first, then start START.cmd.
  pause
  exit /b 1
)
fltmc >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b)
powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Skript\Oberflaeche.ps1"
exit /b
