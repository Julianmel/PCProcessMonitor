@echo off
title PCProcessMonitor - Painel de Desempenho da Rede
cd /d "%~dp0"
mode con: cols=215 lines=35
chcp 65001 >nul
echo ============================================================
echo  Iniciando PCProcessMonitor (Modo Usuario / Sem Elevacao)...
echo ============================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Monitor-Rede.ps1
pause
