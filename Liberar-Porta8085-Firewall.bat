@echo off
title Liberar Porta 8085 no Windows Firewall (JFMELGACO-4)
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================================
echo  Liberando Porta 8085 no Windows Firewall para Rede Local...
echo ============================================================
echo.

netsh advfirewall firewall delete rule name="LibreHardwareMonitor_HTTP_8085" >nul 2>&1
netsh advfirewall firewall add rule name="LibreHardwareMonitor_HTTP_8085" dir=in action=allow protocol=TCP localport=8085 profile=any description="Permite telemetria termica do LibreHardwareMonitor para a rede local"

echo.
echo ============================================================
echo  Regra configurada com sucesso! Pressione qualquer tecla para sair.
echo ============================================================
pause >nul
