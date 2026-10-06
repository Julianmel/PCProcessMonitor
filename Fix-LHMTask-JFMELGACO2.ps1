# Fix-LHMTask-JFMELGACO2.ps1
# Repara a Tarefa Agendada do LibreHardwareMonitor no JFMELGACO-2

$secPass = ConvertTo-SecureString "Monitor2026@" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("Monitor", $secPass)
$so = New-CimSessionOption -Protocol Dcom
$cs = New-CimSession -ComputerName "JFMELGACO-2" -Credential $cred -SessionOption $so

# Comando que será executado no JFMELGACO-2 sob a conta com privilégios de Administrador
$remoteScript = '
$taskName = "PCProcessMonitor_LibreHardwareMonitor"
try { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue } catch {}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\Tools\LibreHardwareMonitor\Start-LHMHeadless.ps1""" -WorkingDirectory "C:\Tools\LibreHardwareMonitor"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([System.TimeSpan]::Zero)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
Start-Sleep -Seconds 2
Start-ScheduledTask -TaskName $taskName
'

$bytes = [System.Text.Encoding]::Unicode.GetBytes($remoteScript)
$encoded = [Convert]::ToBase64String($bytes)
$cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"

Write-Host "Enviando comando de reparo para JFMELGACO-2..." -ForegroundColor Cyan
$res = Invoke-CimMethod -CimSession $cs -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd }
Write-Host "Processo de reparo disparado: ReturnValue=$($res.ReturnValue), ProcessId=$($res.ProcessId)" -ForegroundColor Green

Write-Host "Aguardando 10 segundos para inicialização dos sensores..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Verificar se a tarefa está em execução
$task = Get-CimInstance -CimSession $cs -ClassName MSFT_ScheduledTask -Namespace "Root\Microsoft\Windows\TaskScheduler" -Filter "TaskName='PCProcessMonitor_LibreHardwareMonitor'" -ErrorAction SilentlyContinue
Write-Host "Estado da Tarefa: $($task.State)" -ForegroundColor Cyan

# Verificar sensores WMI
try {
    $sensors = @(Get-CimInstance -CimSession $cs -Namespace "root/LibreHardwareMonitor" -ClassName "Sensor" -Filter "SensorType='Temperature'" -ErrorAction Stop)
    Write-Host "Total de sensores de temperatura encontrados no JFMELGACO-2: $($sensors.Count)" -ForegroundColor Green
    foreach ($s in $sensors) {
        Write-Host "  Sensor: $($s.Name) = $($s.Value) °C" -ForegroundColor Yellow
    }
} catch {
    Write-Host "Erro ao consultar sensores WMI: $($_.Exception.Message)" -ForegroundColor Red
}

Remove-CimSession $cs
