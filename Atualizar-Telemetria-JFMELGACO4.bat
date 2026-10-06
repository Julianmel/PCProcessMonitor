@echo off
title Atualizar Telemetria Termica (LHM v0.9.6 + PawnIO) - JFMELGACO-4
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================================
echo  Atualizando Telemetria Termica para LHM v0.9.6 + PawnIO
echo  (Compativel com Windows 11, HVCI e Isolamento de Nucleo)
echo ============================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Tools\LibreHardwareMonitor\Atualizar-Para-LHM-v096-PawnIO.ps1"

echo.
echo ============================================================
echo  Procedimento concluido! Pressione qualquer tecla para fechar.
echo ============================================================
pause >nul
