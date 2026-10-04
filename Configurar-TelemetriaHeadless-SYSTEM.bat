@echo off
title Configurar Telemetria Termica Headless (SYSTEM no Boot) - PCProcessMonitor
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================================
echo  Configurando Telemetria Headless no Boot (sem login)
echo ============================================================
echo.

:: 1. Auto-copia para C:\Tools\PCProcessMonitor_Setup para contornar perda da unidade de rede (V:) na elevacao UAC
set "LOCAL_SETUP=C:\Tools\PCProcessMonitor_Setup"
if not exist "%LOCAL_SETUP%" mkdir "%LOCAL_SETUP%"
if /i not "%~dp0"=="%LOCAL_SETUP%\" (
    echo Preparando instalacao local a partir de C:\...
    copy /y "%~f0" "%LOCAL_SETUP%\Configurar-TelemetriaHeadless-SYSTEM.bat" >nul 2>&1
    if exist "%~dp0Start-LHMHeadless.ps1" copy /y "%~dp0Start-LHMHeadless.ps1" "%LOCAL_SETUP%\Start-LHMHeadless.ps1" >nul 2>&1
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/k """"%LOCAL_SETUP%\Configurar-TelemetriaHeadless-SYSTEM.bat""""' -Verb RunAs"
    exit /b
)

:: 2. Verifica privilegios de Administrador
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando privilegios de Administrador...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/k """"%~f0""""' -Verb RunAs"
    exit /b
)

set "INSTALL_PATH=C:\Tools\LibreHardwareMonitor"
set "HEADLESS_PS1=%INSTALL_PATH%\Start-LHMHeadless.ps1"
set "TASK_NAME=PCProcessMonitor_LibreHardwareMonitor"

if not exist "%INSTALL_PATH%" (
    echo [ERRO] Diretorio do LibreHardwareMonitor nao encontrado em: %INSTALL_PATH%
    echo Execute primeiro o Instalar-TelemetriaTemperatura.ps1.
    pause
    exit /b 1
)

:: Copia Start-LHMHeadless.ps1 para C:\Tools\LibreHardwareMonitor caso esteja presente no setup
if exist "%LOCAL_SETUP%\Start-LHMHeadless.ps1" (
    copy /y "%LOCAL_SETUP%\Start-LHMHeadless.ps1" "%HEADLESS_PS1%" >nul 2>&1
)

if not exist "%HEADLESS_PS1%" (
    echo [ERRO] Script Start-LHMHeadless.ps1 nao encontrado em: %HEADLESS_PS1%
    pause
    exit /b 1
)

:: 3. Encerra processos anteriores do LHM para liberar drivers
echo [1/4] Finalizando instancias anteriores do LibreHardwareMonitor...
taskkill /f /im LibreHardwareMonitor.exe >nul 2>&1

:: 4. Remove tarefas antigas de logon
echo [2/4] Removendo tarefas agendadas anteriores...
schtasks /Delete /TN "%TASK_NAME%" /F >nul 2>&1
schtasks /Delete /TN "%TASK_NAME%_Logon" /F >nul 2>&1
schtasks /Delete /TN "PCProcessMonitor_TelemetriaHeadless" /F >nul 2>&1

:: 5. Cria nova tarefa agendada AtStartup sob SYSTEM
echo [3/4] Registrando servico headless no boot (SYSTEM no startup)...
set "ACTION_CMD=powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""%HEADLESS_PS1%"""
schtasks /Create /TN "%TASK_NAME%" /TR "%ACTION_CMD%" /SC ONSTART /RU "SYSTEM" /RL HIGHEST /F

:: 6. Dispara a tarefa imediatamente para ativacao
echo [4/4] Iniciando servico headless agora...
schtasks /Run /TN "%TASK_NAME%"

echo.
echo Aguardando 5 segundos para inicializacao dos sensores WMI...
powershell.exe -NoProfile -Command "Start-Sleep -Seconds 5"

echo.
echo ============================================================
echo  DIAGNOSTICO DE SENSORES WMI (root\LibreHardwareMonitor)
echo ============================================================
powershell.exe -NoProfile -Command "try { $s = Get-CimInstance -Namespace 'root\LibreHardwareMonitor' -ClassName 'Sensor' -ErrorAction Stop | Where-Object { $_.SensorType -eq 'Temperature' }; if ($s) { Write-Host ' [OK] Sensores ativos:' -ForegroundColor Green; foreach ($x in $s) { Write-Host ('   - ' + $x.Name + ': ' + [math]::Round([double]$x.Value, 1) + ' °C') -ForegroundColor White } } else { Write-Host ' [AVISO] Nenhum sensor retornado ainda.' -ForegroundColor Yellow } } catch { Write-Host (' [ERRO] WMI: ' + $_.Exception.Message) -ForegroundColor Red }"

echo.
echo ============================================================
echo  [SUCESSO] Telemetria Headless no Boot configurada!
echo  Os sensores de CPU iniciarao no boot sob SYSTEM sem login.
echo ============================================================
echo.
pause
