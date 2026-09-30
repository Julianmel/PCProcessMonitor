@echo off
title Configurar Usuario Monitor e Telemetria
echo ============================================================
echo  Solicitando privilegios de Administrador para configuracao...
echo ============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%~dp0Configurar-MonitorLocal.ps1""' -Verb RunAs"
