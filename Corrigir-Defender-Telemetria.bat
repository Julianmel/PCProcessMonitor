@echo off
title Corrigir Bloqueio do Defender na Telemetria de CPU - PCProcessMonitor
chcp 65001 >nul
cd /d "%~dp0"

echo ============================================================
echo  Liberando LibreHardwareMonitor no Windows Defender
echo ============================================================
echo.

:: 1. Auto-elevação para Administrador
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Solicitando privilegios de Administrador para configurar exclusao no Defender...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd.exe -ArgumentList '/k """"%~f0""""' -Verb RunAs"
    exit /b
)

set "INSTALL_PATH=C:\Tools\LibreHardwareMonitor"
set "TASK_NAME=PCProcessMonitor_LibreHardwareMonitor"

echo [1/4] Adicionando exclusoes no Windows Defender...
powershell.exe -NoProfile -Command "Add-MpPreference -ExclusionPath '%INSTALL_PATH%' -ErrorAction SilentlyContinue; Add-MpPreference -ExclusionProcess 'LibreHardwareMonitor.exe' -ErrorAction SilentlyContinue; Write-Host ' [OK] Exclusoes configuradas no Defender.' -ForegroundColor Green"

echo [2/4] Restaurando driver de hardware da quarentena do Defender...
powershell.exe -NoProfile -Command "try { Restore-MpThreat -ThreatID 2147937641 -ErrorAction SilentlyContinue; Write-Host ' [OK] Ameaca Winring0 liberada/restaurada.' -ForegroundColor Green } catch { Write-Host ' [INFO] Nenhuma ameaca pendente para restaurar.' -ForegroundColor Gray }"

echo [3/4] Reiniciando processo LibreHardwareMonitor com exclusao ativa...
taskkill /f /im LibreHardwareMonitor.exe >nul 2>&1
powershell.exe -NoProfile -Command "Start-Sleep -Seconds 2"

:: Inicia a tarefa agendada
schtasks /Run /TN "%TASK_NAME%" >nul 2>&1
if %errorlevel% neq 0 (
    if exist "%INSTALL_PATH%\LibreHardwareMonitor.exe" (
        start "" "%INSTALL_PATH%\LibreHardwareMonitor.exe"
    )
)

echo [4/4] Aguardando 5 segundos para leitura dos sensores térmicos...
powershell.exe -NoProfile -Command "Start-Sleep -Seconds 5"

echo.
echo ============================================================
echo  DIAGNOSTICO DE TEMPERATURA DA CPU (JFMELGACO-4)
echo ============================================================
powershell.exe -NoProfile -Command "try { $s = Get-CimInstance -Namespace 'root\LibreHardwareMonitor' -ClassName 'Sensor' -ErrorAction Stop | Where-Object { $_.SensorType -eq 'Temperature' }; if ($s) { Write-Host ' [OK] Sensores termicos restaurados com sucesso:' -ForegroundColor Green; foreach ($x in $s) { Write-Host ('   * ' + $x.Name + ': ' + [math]::Round([double]$x.Value, 1) + ' °C') -ForegroundColor White } } else { Write-Host ' [AVISO] Nenhum sensor retornado ainda.' -ForegroundColor Yellow } } catch { Write-Host (' [ERRO] ' + $_.Exception.Message) -ForegroundColor Red }"

echo.
echo ============================================================
echo  Concluido! Pressione qualquer tecla para fechar...
echo ============================================================
pause
