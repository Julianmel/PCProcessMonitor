[CmdletBinding()]
param(
    [string]$TargetComputer = "JFMELGACO-2"
)

$secPass = ConvertTo-SecureString "Monitor2026@" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("Monitor", $secPass)
$opt = New-CimSessionOption -Protocol Dcom
$s = New-CimSession -ComputerName $TargetComputer -Credential $cred -SessionOption $opt -OperationTimeoutSec 10

Write-Host "Conectado ao $TargetComputer. Lendo Start-LHMHeadless.ps1 local..." -ForegroundColor Cyan
$scriptContent = Get-Content (Join-Path $PSScriptRoot "Start-LHMHeadless.ps1") -Raw -Encoding UTF8
$bytes = [System.Text.Encoding]::UTF8.GetBytes($scriptContent)
$b64 = [Convert]::ToBase64String($bytes)

# Comando para gravar Start-LHMHeadless.ps1 remotamente
$remoteWriteScript = "[System.IO.File]::WriteAllBytes('C:\Tools\LibreHardwareMonitor\Start-LHMHeadless.ps1', [Convert]::FromBase64String('$b64'))"
$encodedBytes = [System.Text.Encoding]::Unicode.GetBytes($remoteWriteScript)
$encodedCommand = [Convert]::ToBase64String($encodedBytes)

$cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
$res = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd } -CimSession $s
Write-Host "Gravação do Start-LHMHeadless.ps1 disparada (ReturnValue: $($res.ReturnValue))." -ForegroundColor White

Start-Sleep -Seconds 4

# Encerrar instâncias anteriores do LibreHardwareMonitor
Write-Host "Encerrando instâncias antigas de LibreHardwareMonitor..." -ForegroundColor Gray
Get-CimInstance Win32_Process -CimSession $s | Where-Object { $_.Name -like "*LibreHardwareMonitor*" } | ForEach-Object {
    Invoke-CimMethod -InputObject $_ -MethodName Terminate | Out-Null
}

Start-Sleep -Seconds 2

# Criar e disparar Tarefa Agendada no boot sob SYSTEM
$taskName = "PCProcessMonitor_LibreHardwareMonitor"
$taskScript = @"
schtasks /Delete /TN "$taskName" /F
schtasks /Delete /TN "${taskName}_Logon" /F
schtasks /Create /TN "$taskName" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"C:\Tools\LibreHardwareMonitor\Start-LHMHeadless.ps1\"" /SC ONSTART /RU "SYSTEM" /RL HIGHEST /F
schtasks /Run /TN "$taskName"
"@
$taskEncoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($taskScript))
$cmdTask = "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $taskEncoded"
$resTask = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmdTask } -CimSession $s
Write-Host "Configuração da Tarefa Agendada disparada (ReturnValue: $($resTask.ReturnValue))." -ForegroundColor White

Write-Host "Aguardando 7 segundos para inicialização dos sensores..." -ForegroundColor Yellow
Start-Sleep -Seconds 7

# Verificar sensores
$sensors = Get-CimInstance -Namespace "root/LibreHardwareMonitor" -ClassName "Sensor" -CimSession $s -ErrorAction SilentlyContinue | Where-Object { $_.SensorType -eq "Temperature" }
Write-Host "Total de sensores de temperatura encontrados: $($sensors.Count)" -ForegroundColor Green
$sensors | Select-Object Name, Value, Identifier | Format-Table -AutoSize

Remove-CimSession $s -ErrorAction SilentlyContinue
