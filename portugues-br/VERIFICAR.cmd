@echo off
title Radeon-atieclxx-SSD-Fix - Status
if not exist "%~dp0Script\verificar.ps1" (
  echo Extraia o arquivo ZIP por completo primeiro e depois inicie o VERIFICAR.cmd.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Script\verificar.ps1"
echo.
pause
