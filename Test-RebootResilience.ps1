# Test-RebootResilience.ps1
# Script de reinicio e validacao de resiliencia dos nos remotos JFMELGACO-1, 2 e 3
# Mantem JFMELGACO-4 intacto

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$secPass = ConvertTo-SecureString "Monitor2026@" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("Monitor", $secPass)
$so = New-CimSessionOption -Protocol Dcom

$remoteNodes = @("JFMELGACO-2", "JFMELGACO-3", "JFMELGACO-1")

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [1/4] REGISTRANDO STATUS ANTERIOR AO REINICIO" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$preBootInfo = @{}
foreach ($node in $remoteNodes) {
    try {
        $cs = New-CimSession -ComputerName $node -Credential $cred -SessionOption $so -OperationTimeoutSec 10
        $os = Get-CimInstance -CimSession $cs -ClassName Win32_OperatingSystem
        $preBootInfo[$node] = $os.LastBootUpTime
        Write-Host "  - $node -> Ultimo Boot: $($os.LastBootUpTime)" -ForegroundColor Green
        Remove-CimSession $cs
    } catch {
        Write-Host "  - $node -> Falha ao consultar boot anterior: $($_.Exception.Message)" -ForegroundColor Yellow
        $preBootInfo[$node] = $null
    }
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [2/4] DISPARANDO ORDEM DE REINICIO REMOTO" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Dispara primeiro os nÃƒÂ³s clientes (2 e 3)
foreach ($client in @("JFMELGACO-2", "JFMELGACO-3")) {
    Write-Host "  Enviando Restart-Computer para $client..." -NoNewline
    try {
        Restart-Computer -ComputerName $client -Credential $cred -Force -ErrorAction Stop
        Write-Host " [OK]" -ForegroundColor Green
    } catch {
        Write-Host " [ERRO: $($_.Exception.Message)]" -ForegroundColor Red
    }
}

Start-Sleep -Seconds 3

# Dispara o servidor central (1)
Write-Host "  Enviando Restart-Computer para JFMELGACO-1 (Servidor Central)..." -NoNewline
try {
    Restart-Computer -ComputerName "JFMELGACO-1" -Credential $cred -Force -ErrorAction Stop
    Write-Host " [OK]" -ForegroundColor Green
} catch {
    Write-Host " [ERRO: $($_.Exception.Message)]" -ForegroundColor Red
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [3/4] AGUARDANDO E MONITORANDO RETORNO DOS NOS" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$startTime = Get-Date
$allBack = $false
$statusMap = @{}
foreach ($node in $remoteNodes) {
    $statusMap[$node] = @{ WentDown = $false; CameBack = $false }
}

$timeoutMinutes = 6

while (-not $allBack -and ((Get-Date) - $startTime).TotalMinutes -lt $timeoutMinutes) {
    Start-Sleep -Seconds 5
    $pending = 0

    foreach ($node in $remoteNodes) {
        $ping = Test-Connection -ComputerName $node -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $ping) {
            if (-not $statusMap[$node].WentDown) {
                $statusMap[$node].WentDown = $true
                Write-Host "  [$([datetime]::Now.ToString('HH:mm:ss'))] $node reiniciando (offline detectado)." -ForegroundColor Yellow
            }
        } else {
            if ($statusMap[$node].WentDown -and -not $statusMap[$node].CameBack) {
                # Verifica se a interface CIM/RPC jÃƒÂ¡ aceita conexÃƒÂ£o
                try {
                    $csTest = New-CimSession -ComputerName $node -Credential $cred -SessionOption $so -OperationTimeoutSec 5
                    $osTest = Get-CimInstance -CimSession $csTest -ClassName Win32_OperatingSystem -ErrorAction Stop
                    $statusMap[$node].CameBack = $true
                    $statusMap[$node].NewBoot = $osTest.LastBootUpTime
                    Remove-CimSession $csTest
                    Write-Host "  [$([datetime]::Now.ToString('HH:mm:ss'))] $node RETORNOU ONLINE! Novo Boot: $($osTest.LastBootUpTime)" -ForegroundColor Green
                } catch {
                    # Ainda subindo servicos
                }
            }
        }

        if (-not $statusMap[$node].CameBack) {
            $pending++
        }
    }

    if ($pending -eq 0) {
        $allBack = $true
    }
}

if (-not $allBack) {
    Write-Host "`n[AVISO] Tempo limite atingido ($timeoutMinutes min). Alguns nÃƒÂ³s podem ainda estar inicializando." -ForegroundColor Yellow
} else {
    Write-Host "`n[SUCESSO] Todos os 3 nÃƒÂ³s remotos reiniciaram e estÃƒÂ£o operacionais via rede/CIM!" -ForegroundColor Green
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
Write-Host " [4/4] VALIDANDO COLETOR CENTRAL E TELEMETRIA TERMICA" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Aguarda 30 segundos para o coletor central executar pelo menos uma rodada completa de amostragem
Write-Host "Aguardando 30 segundos para estabilizacao e rodada de telemetria..."
Start-Sleep -Seconds 30

# Verifica processos no JFMELGACO-1
try {
    $cs1 = New-CimSession -ComputerName "JFMELGACO-1" -Credential $cred -SessionOption $so -OperationTimeoutSec 10
    $procs = Get-CimInstance -CimSession $cs1 -ClassName Win32_Process | Where-Object { $_.Name -match "powershell|LibreHardwareMonitor" }
    Write-Host "`nProcessos em execucao no JFMELGACO-1:" -ForegroundColor Cyan
    $procs | Select-Object ProcessId, Name, CommandLine | Format-Table -AutoSize
    Remove-CimSession $cs1
} catch {
    Write-Host "Falha ao consultar processos em JFMELGACO-1: $($_.Exception.Message)" -ForegroundColor Red
}

# Le as ultimas linhas do log gerado em V: ou via UNC
$logDir = "V:\Documents\PCProcessMonitor\Data"
if (-not (Test-Path $logDir)) {
    $logDir = "\\JFMELGACO-1\Technoflora-1\Documents\PCProcessMonitor\Data"
}
$todayLog = if (Test-Path $logDir) {
    Get-ChildItem "$logDir\*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
} else { $null }

if ($todayLog) {
    Write-Host "`nUltimas linhas do log mais recente ($($todayLog.Name), Atualizado as $($todayLog.LastWriteTime)):" -ForegroundColor Cyan
    Get-Content $todayLog.FullName -Tail 15
} else {
    Write-Host "Nenhum arquivo de log encontrado em $logDir" -ForegroundColor Red
}
