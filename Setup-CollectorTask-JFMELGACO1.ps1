# Setup-CollectorTask-JFMELGACO1.ps1
# Configura a inicialização automática do coletor central no boot do JFMELGACO-1

$secPass = ConvertTo-SecureString "Monitor2026@" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("Monitor", $secPass)
$so = New-CimSessionOption -Protocol Dcom
$cs = New-CimSession -ComputerName "JFMELGACO-1" -Credential $cred -SessionOption $so

$remoteScript = '
$taskName = "PCProcessMonitor_CentralCollector"
try { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue } catch {}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\Shared\Documents\PCProcessMonitor\Monitor-Rede.ps1""" -WorkingDirectory "C:\Shared\Documents\PCProcessMonitor"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([System.TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
'

$bytes = [System.Text.Encoding]::Unicode.GetBytes($remoteScript)
$encoded = [Convert]::ToBase64String($bytes)
$cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"

Write-Host "Registrando Tarefa Agendada no JFMELGACO-1..." -ForegroundColor Cyan
$res = Invoke-CimMethod -CimSession $cs -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd }
Write-Host "Comando disparado: ReturnValue=$($res.ReturnValue), ProcessId=$($res.ProcessId)" -ForegroundColor Green

Start-Sleep -Seconds 4

$task = Get-CimInstance -CimSession $cs -ClassName MSFT_ScheduledTask -Namespace "Root\Microsoft\Windows\TaskScheduler" -Filter "TaskName='PCProcessMonitor_CentralCollector'" -ErrorAction SilentlyContinue
if ($task) {
    Write-Host "Tarefa 'PCProcessMonitor_CentralCollector' registrada com sucesso! Estado: $($task.State)" -ForegroundColor Green
} else {
    Write-Host "Aviso: Tarefa não encontrada." -ForegroundColor Yellow
}

Remove-CimSession $cs
