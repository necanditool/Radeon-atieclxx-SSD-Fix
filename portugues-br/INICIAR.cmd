@echo off
title Radeon-atieclxx-SSD-Fix
if not exist "%~dp0Script\Janela.ps1" (
  echo Extraia o arquivo ZIP por completo primeiro e depois inicie o INICIAR.cmd.
  pause
  exit /b 1
)
fltmc >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b)
powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0Script\Janela.ps1"
exit /b
