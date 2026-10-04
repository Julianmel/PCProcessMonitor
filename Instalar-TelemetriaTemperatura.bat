@echo off
title Habilitar Telemetria Térmica de CPU (PCProcessMonitor)
echo ============================================================
echo  Solicitando privilégios de Administrador...
echo ============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%~dp0Instalar-TelemetriaTemperatura.ps1""' -Verb RunAs"
