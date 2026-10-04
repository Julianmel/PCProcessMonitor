@echo off
title Habilitar Telemetria Termica de CPU (PCProcessMonitor)
cd /d "%~dp0"
chcp 65001 >nul
echo ============================================================
echo  Iniciando configuracao de telemetria termica...
echo ============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Instalar-TelemetriaTemperatura.ps1
echo.
echo ============================================================
echo  Script finalizado.
echo ============================================================
pause
