@echo off
title Configurar LibreHardwareMonitor como SYSTEM (PCProcessMonitor)
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================================
echo  Configurando Tarefa Agendada como SYSTEM com Elevacao
echo ============================================================
echo.

:: Verifica se esta executando como Administrador
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando privilegios de Administrador...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/c ""%~f0""' -Verb RunAs"
    exit /b
)

set "TASK_NAME=PCProcessMonitor_LibreHardwareMonitor"
set "EXE_PATH=C:\Tools\LibreHardwareMonitor\LibreHardwareMonitor.exe"

if not exist "%EXE_PATH%" (
    echo [ERRO] Binario nao encontrado em: %EXE_PATH%
    pause
    exit /b 1
)

:: Encerra processos do LHM que possam estar rodando sem elevacao
taskkill /f /im LibreHardwareMonitor.exe >nul 2>&1

:: Registra a tarefa agendada para rodar como SYSTEM (maxima permissao de driver, sem precisar de senha)
echo Registrando tarefa agendada para inicializacao no boot e logon como SYSTEM...
schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
schtasks /Create /TN "%TASK_NAME%" /TR "\"%EXE_PATH%\"" /SC ONSTART /RU "SYSTEM" /RL HIGHEST /F
schtasks /Create /TN "%TASK_NAME%_Logon" /TR "\"%EXE_PATH%\"" /SC ONLOGON /RU "SYSTEM" /RL HIGHEST /F

:: Inicia a tarefa imediatamente
echo.
echo Iniciando LibreHardwareMonitor com privilegios de SYSTEM...
schtasks /Run /TN "%TASK_NAME%"

echo.
echo ============================================================
echo  [SUCESSO] Tarefa configurada como SYSTEM com sucesso!
echo  O LibreHardwareMonitor agora iniciara com privilégios de kernel
echo  automaticamente em todo boot/reinicializacao, mesmo sem login.
echo ============================================================
echo.
timeout /t 5
