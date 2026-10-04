@echo off
title Configurar LibreHardwareMonitor como SYSTEM (PCProcessMonitor)
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================================
echo  Configurando Tarefa Agendada como SYSTEM com Elevacao
echo ============================================================
echo.

:: Copia para C:\Tools para contornar perda da unidade de rede (V:) na elevacao UAC
set "LOCAL_SETUP=C:\Tools\PCProcessMonitor_Setup"
if not exist "%LOCAL_SETUP%" mkdir "%LOCAL_SETUP%"
if /i not "%~dp0"=="%LOCAL_SETUP%\" (
    echo Preparando execucao local a partir de C:\...
    copy /y "%~f0" "%LOCAL_SETUP%\Corrigir-TarefaLHM-SYSTEM.bat" >nul 2>&1
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/k """"%LOCAL_SETUP%\Corrigir-TarefaLHM-SYSTEM.bat""""' -Verb RunAs"
    exit /b
)

:: Verifica se esta executando como Administrador
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando privilegios de Administrador...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/k """"%~f0""""' -Verb RunAs"
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
echo Encerrando eventuais processos do LHM sem elevacao...
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
echo  O LibreHardwareMonitor agora iniciara com privilegios de kernel
echo  automaticamente em todo boot/reinicializacao, mesmo sem login.
echo ============================================================
echo.
pause
