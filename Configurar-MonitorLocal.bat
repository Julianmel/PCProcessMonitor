@echo off
title Configurar Usuario Monitor - JFMELGACO3
echo Solicitando privilegios de Administrador...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%~dp0Configurar-MonitorLocal.ps1""' -Verb RunAs"
