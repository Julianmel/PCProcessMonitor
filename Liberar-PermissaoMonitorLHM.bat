@echo off
title Liberar Permissao Remota no WMI do LibreHardwareMonitor
cd /d "%~dp0"
chcp 65001 >nul
echo ============================================================
echo  Solicitando privilegios de Administrador...
echo ============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File ""%~dp0Liberar-PermissaoMonitorLHM.ps1""' -Verb RunAs"
