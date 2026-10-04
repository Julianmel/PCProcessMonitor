@echo off
title Habilitar Telemetria Termica de CPU (PCProcessMonitor)
cd /d "%~dp0"
chcp 65001 >nul
echo ============================================================
echo  Iniciando configuracao de telemetria termica...
echo ============================================================

:: Copia arquivos para diretorio local em C:\Tools para permitir elevacao a partir de drives de rede (V:)
set "LOCAL_SETUP=C:\Tools\PCProcessMonitor_Setup"
if not exist "%LOCAL_SETUP%" mkdir "%LOCAL_SETUP%"
copy /y "%~dp0Instalar-TelemetriaTemperatura.ps1" "%LOCAL_SETUP%\" >nul 2>&1
copy /y "%~dp0Start-LHMHeadless.ps1" "%LOCAL_SETUP%\" >nul 2>&1
copy /y "%~dp0Liberar-PermissaoMonitorLHM.ps1" "%LOCAL_SETUP%\" >nul 2>&1

:: Executa a partir de C: com elevacao de Administrador garantida
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File ""%LOCAL_SETUP%\Instalar-TelemetriaTemperatura.ps1""' -Verb RunAs"

echo.
echo ============================================================
echo  Janela de Administrador disparada na sua tela.
echo ============================================================
pause
