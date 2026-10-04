@echo off
title Habilitar Telemetria Termica de CPU (PCProcessMonitor)
echo ============================================================
echo  Solicitando privilegios de Administrador...
echo ============================================================
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File ""%~dp0Instalar-TelemetriaTemperatura.ps1""' -Verb RunAs"
