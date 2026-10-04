@echo off
title Liberar Permissao Remota no WMI do LibreHardwareMonitor
cd /d "%~dp0"
chcp 65001 >nul
echo ============================================================
echo  Executando Liberacao de Permissao WMI do LibreHardwareMonitor...
echo ============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Liberar-PermissaoMonitorLHM.ps1
echo.
echo ============================================================
echo  Finalizado.
echo ============================================================
pause
