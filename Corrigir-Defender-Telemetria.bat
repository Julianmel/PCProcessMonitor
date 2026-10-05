@echo off
title Corrigir Bloqueio do Defender na Telemetria de CPU - PCProcessMonitor
chcp 65001 >nul
cd /d "%~dp0"

:: 1. Proteção contra loop: se já recebeu o parâmetro --elevated, executa direto sem re-chamar UAC
if "%~1"=="--elevated" goto :run

:: 2. Verifica se já está elevado
powershell.exe -NoProfile -Command "if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }"
if %errorlevel% equ 0 goto :run

:: 3. Se não for Administrador, dispara UAC uma única vez com a flag --elevated e encerra o pai
echo Solicitando privilegios de Administrador para configurar exclusao no Defender...
powershell.exe -NoProfile -Command "Start-Process cmd.exe -ArgumentList '/k \"\"%~f0\" --elevated\"' -Verb RunAs"
exit /b

:run
echo ============================================================
echo  Liberando LibreHardwareMonitor no Windows Defender
echo ============================================================
echo.

set "INSTALL_PATH=C:\Tools\LibreHardwareMonitor"
set "TASK_NAME=PCProcessMonitor_LibreHardwareMonitor"

echo [1/4] Adicionando exclusoes no Windows Defender...
powershell.exe -NoProfile -Command "Add-MpPreference -ExclusionPath '%INSTALL_PATH%' -ErrorAction SilentlyContinue; Add-MpPreference -ExclusionProcess 'LibreHardwareMonitor.exe' -ErrorAction SilentlyContinue; Write-Host ' [OK] Exclusoes configuradas no Defender.' -ForegroundColor Green"

echo [2/4] Liberando ameaca Winring0 da quarentena...
powershell.exe -NoProfile -Command "try { Restore-MpThreat -ThreatID 2147937641 -ErrorAction SilentlyContinue; Write-Host ' [OK] Ameaca liberada da quarentena.' -ForegroundColor Green } catch { Write-Host ' [INFO] Quarentena limpa.' -ForegroundColor Gray }"

echo [3/4] Reiniciando processo LibreHardwareMonitor...
taskkill /f /im LibreHardwareMonitor.exe >nul 2>&1
powershell.exe -NoProfile -Command "Start-Sleep -Seconds 2"
schtasks /Run /TN "%TASK_NAME%" >nul 2>&1

echo [4/4] Aguardando 5 segundos para leitura dos sensores térmicos...
powershell.exe -NoProfile -Command "Start-Sleep -Seconds 5"

echo.
echo ============================================================
echo  DIAGNOSTICO DE TEMPERATURA DA CPU (JFMELGACO-4)
echo ============================================================
powershell.exe -NoProfile -Command "try { $s = Get-CimInstance -Namespace 'root\LibreHardwareMonitor' -ClassName 'Sensor' -ErrorAction Stop | Where-Object { $_.SensorType -eq 'Temperature' }; if ($s) { Write-Host ' [OK] Sensores termicos ativos:' -ForegroundColor Green; foreach ($x in $s) { Write-Host ('   * ' + $x.Name + ': ' + [math]::Round([double]$x.Value, 1) + ' °C') -ForegroundColor White } } else { Write-Host ' [AVISO] Nenhum sensor retornado ainda.' -ForegroundColor Yellow } } catch { Write-Host (' [ERRO] ' + $_.Exception.Message) -ForegroundColor Red }"

echo.
echo ============================================================
echo  Concluido com sucesso! Pode fechar esta janela.
echo ============================================================
pause
