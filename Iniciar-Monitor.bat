@echo off
title PCProcessMonitor - Painel de Desempenho da Rede
cd /d "%~dp0"
echo ============================================================
echo  Iniciando PCProcessMonitor (Modo Usuario / Sem Elevacao)...
echo ============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Monitor-Rede.ps1
pause
