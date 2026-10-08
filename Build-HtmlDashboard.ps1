# ============================================================
# GERADOR DE DASHBOARD HTML - JFMELGACO (v1.2.1)
# ============================================================
param(
    [string]$LogFile = $null,
    [string]$OutputFile = "$PSScriptRoot\dashboard_desempenho.html"
)

if ([string]::IsNullOrWhiteSpace($LogFile) -or -not (Test-Path $LogFile)) {
    $searchPaths = @(
        "\\JFMELGACO-1\Technoflora-1\Documents\PCProcessMonitor\Data",
        "\\JFMELGACO-1\Technoflora-1\Documents\PCProcessMonitor",
        "$PSScriptRoot\Data",
        $PSScriptRoot
    )
    $candidateFiles = foreach ($p in $searchPaths) {
        if (Test-Path $p) {
            Get-ChildItem -Path $p -Filter "*Processmonitor*.txt" -ErrorAction SilentlyContinue
        }
    }
    $latest = $candidateFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) {
        $LogFile = $latest.FullName
    } else {
        Write-Error "Nenhum arquivo de log encontrado."
        return
    }
}

function Parse-MetricNumber([string]$str) {
    if ([string]::IsNullOrWhiteSpace($str) -or $str -eq 'N/D') { return 0.0 }
    $clean = $str.Trim()
    if ($clean -match '^\d{1,3}(,\d{3})+(\.\d+)?$') {
        $clean = $clean -replace ',', ''
    } elseif ($clean -match '^\d{1,3}(\.\d{3})+(,\d+)?$') {
        $clean = ($clean -replace '\.', '') -replace ',', '.'
    } else {
        $clean = $clean -replace ',', '.'
    }
    $val = 0.0
    if ([double]::TryParse($clean, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$val)) {
        return $val
    }
    return 0.0
}

Write-Host "Lendo arquivo de log: $LogFile ..." -ForegroundColor Cyan
$lines = [System.IO.File]::ReadAllLines($LogFile, [System.Text.Encoding]::UTF8)

# Carregamento da lista canônica de máquinas (machines.json com fallback e ordenação alfabética estrita)
$machinesJsonPath = Join-Path $PSScriptRoot "machines.json"
if (-not (Test-Path $machinesJsonPath)) { $machinesJsonPath = Join-Path $PSScriptRoot "Data\machines.json" }
$pcsList = @('JFMELGACO-1', 'JFMELGACO-2', 'JFMELGACO-3', 'JFMELGACO-4')
if (Test-Path $machinesJsonPath) {
    try {
        $loadedPcs = Get-Content -Raw $machinesJsonPath -Encoding UTF8 | ConvertFrom-Json
        if ($loadedPcs -and $loadedPcs.Count -gt 0) {
            $pcsList = @($loadedPcs | Sort-Object)
        }
    } catch {}
}

$pattern = '^(?:ONLINE|OFFLINE|SEM ACESSO)\s+(?<pc>[A-Za-z0-9_-]+)(?:\s+\(Local\))?(?:\s+\[[^\]]+\]\s+(?<cpu>\d+)%\s+\[[^\]]+\]\s+(?<ramUsed>[\d\.,]+)\s*\/\s*(?<ramTotal>[\d\.,]+)\s*GB\s*\((?<ramPct>\d+)%\)\s+(?<diskFree>[\d\.,]+)\s*GB\s*liv\s*\(\s*(?<diskPct>\d+)%\s*us\)\s+(?:R:\s*(?<ioRVal>[\d\.,]+|N\/D)(?:\s*(?<ioRUnit>KB\/s|MB\/s))?\s*\|\s*W:\s*(?<ioWVal>[\d\.,]+|N\/D)(?:\s*(?<ioWUnit>KB\/s|MB\/s))?\s+)?Rx:\s*(?<rxVal>[\d\.,]+|N\/D)(?:\s*(?<rxUnit>KB\/s|MB\/s))?\s*\|\s*Tx:\s*(?<txVal>[\d\.,]+|N\/D)(?:\s*(?<txUnit>KB\/s|MB\/s))?)?'

$timestamps = [System.Collections.Generic.List[string]]::new()
$machineData = @{}
foreach ($pc in $pcsList) {
    $machineData[$pc] = @{
        cpu      = [System.Collections.Generic.List[object]]::new()
        ramPct   = [System.Collections.Generic.List[object]]::new()
        ramUsed  = [System.Collections.Generic.List[object]]::new()
        diskFree = [System.Collections.Generic.List[object]]::new()
        diskPct  = [System.Collections.Generic.List[object]]::new()
        ioR      = [System.Collections.Generic.List[object]]::new()
        ioW      = [System.Collections.Generic.List[object]]::new()
        rx       = [System.Collections.Generic.List[object]]::new()
        tx       = [System.Collections.Generic.List[object]]::new()
        ping     = [System.Collections.Generic.List[object]]::new()
        uptime   = [System.Collections.Generic.List[object]]::new()
        bootDate = [System.Collections.Generic.List[object]]::new()
        temp     = [System.Collections.Generic.List[object]]::new()
        internet = [System.Collections.Generic.List[object]]::new()
        ramTotal = 0
        diskTotal= 0
    }
}

$currentTs = $null
$currentBlockPcs = @{}

function Flush-Block {
    if ($null -ne $currentTs) {
        $timestamps.Add($currentTs)
        foreach ($p in $pcsList) {
            if ($currentBlockPcs.ContainsKey($p)) {
                $obj = $currentBlockPcs[$p]
                $machineData[$p].cpu.Add($obj.cpu)
                $machineData[$p].ramPct.Add($obj.ramPct)
                $machineData[$p].ramUsed.Add($obj.ramUsed)
                $machineData[$p].diskFree.Add($obj.diskFree)
                $machineData[$p].diskPct.Add($obj.diskPct)
                $machineData[$p].ioR.Add($obj.ioR)
                $machineData[$p].ioW.Add($obj.ioW)
                $machineData[$p].rx.Add($obj.rx)
                $machineData[$p].tx.Add($obj.tx)
                $machineData[$p].ping.Add($obj.ping)
                $machineData[$p].uptime.Add($obj.uptime)
                $machineData[$p].bootDate.Add($obj.bootDate)
                $machineData[$p].temp.Add($obj.temp)
                $machineData[$p].internet.Add($obj.internet)
                if ($obj.ramTotal -gt 0) { $machineData[$p].ramTotal = $obj.ramTotal }
            } else {
                $machineData[$p].cpu.Add($null)
                $machineData[$p].ramPct.Add($null)
                $machineData[$p].ramUsed.Add($null)
                $machineData[$p].diskFree.Add($null)
                $machineData[$p].diskPct.Add($null)
                $machineData[$p].ioR.Add(0)
                $machineData[$p].ioW.Add(0)
                $machineData[$p].rx.Add(0)
                $machineData[$p].tx.Add(0)
                $machineData[$p].ping.Add($null)
                $machineData[$p].uptime.Add($null)
                $machineData[$p].bootDate.Add($null)
                $machineData[$p].temp.Add($null)
                $machineData[$p].internet.Add(0)
            }
        }
        $currentBlockPcs.Clear()
    }
}

$detectedLocalHost = $null
foreach ($line in $lines) {
    if ($line -match '^(?:\[)?(?<hora>\d{2}:\d{2}:\d{2})(?:\])?\s+========') {
        Flush-Block
        $currentTs = $matches['hora']
        continue
    }

    if ($line -match 'Host Local identificado:\s*(?<lh>[^\s]+)') {
        $detectedLocalHost = $matches['lh']
    }

    if ($null -eq $currentTs) { continue }

    if ($line -match '^(?<status>ONLINE|OFFLINE|SEM ACESSO)\s+(?<pc>[A-Za-z0-9_-]+)(?:\s+\(Local\))?(?:\s+|$)') {
        $lineStatus = $matches['status']
        $rawPc = $matches['pc']
        $pc = $rawPc
        if ($pc -eq 'JFMELGACO3') { $pc = 'JFMELGACO-4' }
        if (-not ($pcsList -contains $pc)) { continue }

        if ($line -match '\(Local\)' -and -not $detectedLocalHost) {
            $detectedLocalHost = $pc
        }

        # Parsing desacoplado e robusto de métricas adicionais
        $pingVal = $null
        if ($line -match 'Ping:\s*(?<ping>\d+|---|N\/D)\s*ms') {
            $rawP = $matches['ping']
            if ($rawP -ne '---' -and $rawP -ne 'N/D') { $pingVal = [int]$rawP }
        }

        $uptimeVal = $null
        if ($line -match 'Uptime:\s*(?<uptime>[^\|\r\n]+?)(?=\s*\(Boot:|\s*Temp:|\s*$)') {
            $rawU = $matches['uptime'].Trim()
            if ($rawU -ne '---' -and $rawU -ne 'N/D') { $uptimeVal = $rawU }
        }

        $bootVal = $null
        if ($line -match '\(Boot:\s*(?<boot>[^\)]+)\)') {
            $rawB = $matches['boot'].Trim()
            if ($rawB -ne '---' -and $rawB -ne 'N/D') { $bootVal = $rawB }
        }

        $tempVal = $null
        if ($line -match 'Temp:\s*(?<temp>\d+)') {
            $tempVal = [int]$matches['temp']
        }

        if ($lineStatus -eq 'ONLINE' -and $line -match $pattern -and -not [string]::IsNullOrWhiteSpace($matches['cpu'])) {
            $baseMatches = $matches
            $cpu = [int]$baseMatches['cpu']
            $ramPct = [int]$baseMatches['ramPct']
            $ramUsed = Parse-MetricNumber $baseMatches['ramUsed']
            $ramTotal = Parse-MetricNumber $baseMatches['ramTotal']
            $diskFree = Parse-MetricNumber $baseMatches['diskFree']
            $diskPct = [int]$baseMatches['diskPct']
            
            $ioR = Parse-MetricNumber $baseMatches['ioRVal']
            if ($baseMatches['ioRUnit'] -eq 'MB/s') { $ioR = $ioR * 1024 }
            
            $ioW = Parse-MetricNumber $baseMatches['ioWVal']
            if ($baseMatches['ioWUnit'] -eq 'MB/s') { $ioW = $ioW * 1024 }

            $rx = Parse-MetricNumber $baseMatches['rxVal']
            if ($baseMatches['rxUnit'] -eq 'MB/s') { $rx = $rx * 1024 }
            
            $tx = Parse-MetricNumber $baseMatches['txVal']
            if ($baseMatches['txUnit'] -eq 'MB/s') { $tx = $tx * 1024 }

            $internetMbps = [math]::Round((($rx + $tx) * 8) / 1024, 2)

            $currentBlockPcs[$pc] = @{
                cpu      = $cpu
                ramPct   = $ramPct
                ramUsed  = $ramUsed
                ramTotal = $ramTotal
                diskFree = $diskFree
                diskPct  = $diskPct
                ioR      = [math]::Round($ioR, 1)
                ioW      = [math]::Round($ioW, 1)
                rx       = [math]::Round($rx, 1)
                tx       = [math]::Round($tx, 1)
                ping     = $pingVal
                uptime   = $uptimeVal
                bootDate = $bootVal
                temp     = $tempVal
                internet = $internetMbps
            }
        } else {
            $currentBlockPcs[$pc] = @{
                cpu      = $null
                ramPct   = $null
                ramUsed  = $null
                ramTotal = 0
                diskFree = $null
                diskPct  = 0
                ioR      = 0
                ioW      = 0
                rx       = 0
                tx       = 0
                ping     = $pingVal
                uptime   = $null
                bootDate = $null
                temp     = $null
                internet = 0
            }
        }
    }
}
Flush-Block

Write-Host "Total de pontos temporais processados: $($timestamps.Count)" -ForegroundColor Green

# Calculando estatísticas consolidadas
$stats = @{}
foreach ($pc in $pcsList) {
    $validCpu    = $machineData[$pc].cpu | Where-Object { $null -ne $_ }
    $validRam    = $machineData[$pc].ramPct | Where-Object { $null -ne $_ }
    $validRx     = $machineData[$pc].rx | Where-Object { $null -ne $_ }
    $validTx     = $machineData[$pc].tx | Where-Object { $null -ne $_ }
    $validDisk   = $machineData[$pc].diskFree | Where-Object { $null -ne $_ }
    $validIoR    = $machineData[$pc].ioR | Where-Object { $null -ne $_ }
    $validIoW    = $machineData[$pc].ioW | Where-Object { $null -ne $_ }
    $validPing   = $machineData[$pc].ping | Where-Object { $null -ne $_ }
    $validTemp   = $machineData[$pc].temp | Where-Object { $null -ne $_ }
    $validUptime = $machineData[$pc].uptime | Where-Object { $null -ne $_ -and $_ -ne '---' -and $_ -ne 'N/D' }
    $validBoot   = $machineData[$pc].bootDate | Where-Object { $null -ne $_ -and $_ -ne '---' -and $_ -ne 'N/D' }
    $lastUptime  = if ($validUptime) { $validUptime | Select-Object -Last 1 } else { $null }
    $lastBoot    = if ($validBoot) { $validBoot | Select-Object -Last 1 } else { $null }

    if (-not $lastUptime -or -not $lastBoot) {
        if ($pc -ne 'JFMELGACO-1') {
            try {
                $opt = New-CimSessionOption -Protocol Dcom
                $s = New-CimSession -ComputerName $pc -SessionOption $opt -OperationTimeoutSec 1 -ErrorAction Stop
                $osObj = Get-CimInstance Win32_OperatingSystem -CimSession $s -OperationTimeoutSec 1 -ErrorAction Stop
                Remove-CimSession $s -ErrorAction SilentlyContinue
                if ($osObj.LastBootUpTime) {
                    if (-not $lastBoot) { $lastBoot = $osObj.LastBootUpTime.ToString("dd/MM/yyyy HH:mm") }
                    if (-not $lastUptime) {
                        $diff = (Get-Date) - $osObj.LastBootUpTime
                        $lastUptime = if ($diff.Days -gt 0) { "{0}d {1}h" -f $diff.Days, $diff.Hours } else { "{0}h {1}m" -f $diff.Hours, $diff.Minutes }
                    }
                }
            } catch {
                if (-not $lastUptime) { $lastUptime = "N/D" }
                if (-not $lastBoot) { $lastBoot = "N/D" }
            }
        } else {
            if (-not $lastUptime) { $lastUptime = "N/D" }
            if (-not $lastBoot) { $lastBoot = "N/D" }
        }
    }

    $isOnline = ($machineData[$pc].cpu.Count -gt 0 -and $null -ne $machineData[$pc].cpu[-1])
    $latestCpu = if ($isOnline) { $machineData[$pc].cpu[-1] } else { 0 }
    $latestRam = if ($isOnline) { $machineData[$pc].ramPct[-1] } else { 0 }
    $latestIoW = if ($isOnline) { $machineData[$pc].ioW[-1] } else { 0 }
    $latestIoR = if ($isOnline) { $machineData[$pc].ioR[-1] } else { 0 }
    $latestTx  = if ($isOnline) { $machineData[$pc].tx[-1] } else { 0 }
    $latestRx  = if ($isOnline) { $machineData[$pc].rx[-1] } else { 0 }
    $latestPing = if ($validPing) { $validPing | Select-Object -Last 1 } else { 0 }
    $tempCount = $machineData[$pc].temp.Count
    $recentTemps = if ($tempCount -gt 0) {
        $tempStart = [math]::Max(0, $tempCount - 3)
        @($machineData[$pc].temp.GetRange($tempStart, $tempCount - $tempStart) | Where-Object { $null -ne $_ -and $_ -gt 0 })
    } else { @() }
    $latestTemp = if ($isOnline -and $recentTemps.Count -gt 0) { $recentTemps[-1] } else { $null }

    $validDiskPct = $machineData[$pc].diskPct | Where-Object { $null -ne $_ -and $_ -gt 0 }
    $latestDiskPct = if ($validDiskPct) { $validDiskPct | Select-Object -Last 1 } else { 0 }

    $avgCpuVal   = if ($validCpu) { [math]::Round(($validCpu | Measure-Object -Average).Average, 1) } else { 0 }
    $avgRamVal   = if ($validRam) { [math]::Round(($validRam | Measure-Object -Average).Average, 1) } else { 0 }
    $maxCpuVal   = if ($validCpu) { ($validCpu | Measure-Object -Maximum).Maximum } else { 0 }
    $maxRamVal   = if ($validRam) { ($validRam | Measure-Object -Maximum).Maximum } else { 0 }
    $maxIoRVal   = if ($validIoR) { ($validIoR | Measure-Object -Maximum).Maximum } else { 0 }
    $maxIoWVal   = if ($validIoW) { ($validIoW | Measure-Object -Maximum).Maximum } else { 0 }
    $maxRxVal    = if ($validRx)  { ($validRx  | Measure-Object -Maximum).Maximum } else { 0 }
    $maxTxVal    = if ($validTx)  { ($validTx  | Measure-Object -Maximum).Maximum } else { 0 }
    $diskFreeVal = if ($validDisk) { $validDisk | Select-Object -Last 1 } else { 0 }
    $avgPingVal  = if ($validPing) { [math]::Round(($validPing | Measure-Object -Average).Average, 1) } else { 0 }
    $maxPingVal  = if ($validPing) { ($validPing | Measure-Object -Maximum).Maximum } else { 0 }

    $isCpuAlert  = ($isOnline -and ($latestCpu -ge 85 -or $avgCpuVal -ge 85))
    $isRamAlert  = ($isOnline -and ($latestRam -ge 90 -or $avgRamVal -ge 90))
    $isDiskAlert = ($isOnline -and (($latestDiskPct -ge 90) -or ($diskFreeVal -gt 0 -and $diskFreeVal -le 15)))
    $isTempAlert = ($isOnline -and $latestTemp -and $latestTemp -ge 75)
    $hasAlert    = ($isCpuAlert -or $isRamAlert -or $isDiskAlert -or $isTempAlert)

    $alertReasons = [System.Collections.Generic.List[string]]::new()
    if ($isCpuAlert)  { $alertReasons.Add("CPU: $latestCpu% (>=85%)") }
    if ($isRamAlert)  { $alertReasons.Add("RAM: $latestRam% (>=90%)") }
    if ($isDiskAlert) { $alertReasons.Add("Disco C: ${diskFreeVal}GB livres (<=15GB ou >=90%)") }
    if ($isTempAlert) { $alertReasons.Add("Temp: ${latestTemp}°C (>=75°C)") }
    $alertTitle   = if ($alertReasons.Count -gt 0) { "Alerta: " + ($alertReasons -join " | ") } else { "" }

    $stats[$pc] = @{
        isOnline       = $isOnline
        statusText     = if ($isOnline) { "Online" } else { "Offline" }
        onlineDotClass = if ($isOnline) { "bg-emerald-400 shadow-[0_0_6px_rgba(52,211,153,0.8)]" } else { "bg-red-500 shadow-[0_0_8px_rgba(239,68,68,0.9)]" }
        onlineTextClass= if ($isOnline) { "text-emerald-400" } else { "text-red-400 font-bold" }
        hasAlert       = $hasAlert
        alertTitle     = $alertTitle
        isCpuAlert     = $isCpuAlert
        isRamAlert     = $isRamAlert
        isDiskAlert    = $isDiskAlert
        isTempAlert    = $isTempAlert
        latestCpu      = $latestCpu
        latestRam      = $latestRam
        latestIoR      = $latestIoR
        latestIoW      = $latestIoW
        latestRx       = $latestRx
        latestTx       = $latestTx
        latestTemp     = $latestTemp
        avgCpu         = $avgCpuVal
        maxCpu         = $maxCpuVal
        avgRam         = $avgRamVal
        maxRam         = $maxRamVal
        maxIoR         = $maxIoRVal
        maxIoW         = $maxIoWVal
        maxRx          = $maxRxVal
        maxTx          = $maxTxVal
        diskFree       = $diskFreeVal
        diskPct        = $latestDiskPct
        ramTotal       = $machineData[$pc].ramTotal
        ping           = $latestPing
        avgPing        = $avgPingVal
        maxPing        = $maxPingVal
        uptime         = if ($lastUptime) { $lastUptime } else { "N/D" }
        bootDate       = if ($lastBoot) { $lastBoot } else { "N/D" }
    }
}

if (-not $detectedLocalHost -and $env:COMPUTERNAME) {
    $matchedHost = $pcsList | Where-Object { $_ -eq $env:COMPUTERNAME }
    if ($matchedHost) { $detectedLocalHost = $matchedHost }
}
if (-not $detectedLocalHost) {
    $detectedLocalHost = if ($env:COMPUTERNAME -and ($pcsList -contains $env:COMPUTERNAME)) { $env:COMPUTERNAME } else { 'JFMELGACO-2' }
}

Write-Host "Host Local detectado: $detectedLocalHost" -ForegroundColor Yellow

# Carregamento ou extração de Top 10 Processos com CPU normalizada por número de núcleos
$topProcessesData = @{}
$procJsonCandidates = @()
if (-not [string]::IsNullOrWhiteSpace($LogFile)) {
    $procJsonCandidates += (Join-Path (Split-Path $LogFile) "top_processes.json")
}
$procJsonCandidates += @(
    (Join-Path $PSScriptRoot "Data\top_processes.json"),
    (Join-Path $PSScriptRoot "top_processes.json"),
    "V:\Documents\PCProcessMonitor\top_processes.json",
    "V:\Documents\PCProcessMonitor\Data\top_processes.json"
)
foreach ($cPath in $procJsonCandidates) {
    if (Test-Path $cPath) {
        try {
            $loaded = Get-Content -Raw $cPath -Encoding UTF8 | ConvertFrom-Json
            foreach ($prop in $loaded.PSObject.Properties) {
                if (-not $topProcessesData.ContainsKey($prop.Name)) {
                    $procs = [System.Collections.Generic.List[object]]::new()
                    foreach ($item in $prop.Value) {
                        $cpuVal = [double]($item.Cpu)
                        if ($cpuVal -gt 100) { $cpuVal = [math]::Round($cpuVal / 12, 1); if ($cpuVal -gt 100) { $cpuVal = 100 } }
                        $item.Cpu = $cpuVal
                        $procs.Add($item)
                    }
                    $topProcessesData[$prop.Name] = $procs
                }
            }
        } catch {}
    }
}

# Se o nó local não tiver processos no json, consulta via CIM com CPU normalizada
if (-not $topProcessesData.ContainsKey($detectedLocalHost)) {
    try {
        $numCores = [System.Environment]::ProcessorCount
        if (-not $numCores -or $numCores -lt 1) { $numCores = 1 }
        $locProcs = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process |
            Where-Object { $_.Name -notin '_Total', 'Idle' } |
            Sort-Object -Property PercentProcessorTime, WorkingSetPrivate -Descending |
            Select-Object -First 10
        $locList = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($lp in $locProcs) {
            $cleanName = ($lp.Name -replace '#\d+$', '')
            if (-not $cleanName.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase) -and $cleanName -ne 'System') {
                $cleanName = "$cleanName.exe"
            }
            $calcCpu = [math]::Round([double]$lp.PercentProcessorTime / $numCores, 1)
            $locList.Add(@{
                Name  = $cleanName
                Pid   = [int]$lp.IDProcess
                Cpu   = $calcCpu
                MemMB = [math]::Round($lp.WorkingSetPrivate / 1MB, 1)
            })
        }
        $topProcessesData[$detectedLocalHost] = $locList
    } catch {}
}

# Tenta preencher nós remotos se ainda faltantes e online
foreach ($remPc in $pcsList) {
    if (-not $topProcessesData.ContainsKey($remPc) -and $stats[$remPc].isOnline) {
        try {
            $rCores = 1
            try {
                $rCs = Get-CimInstance Win32_ComputerSystem -ComputerName $remPc -OperationTimeoutSec 1 -ErrorAction SilentlyContinue
                if ($rCs -and $rCs.NumberOfLogicalProcessors -gt 0) { $rCores = $rCs.NumberOfLogicalProcessors }
            } catch {}
            $rProcs = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ComputerName $remPc -OperationTimeoutSec 1 |
                Where-Object { $_.Name -notin '_Total', 'Idle' } |
                Sort-Object -Property PercentProcessorTime, WorkingSetPrivate -Descending |
                Select-Object -First 10
            $rList = [System.Collections.Generic.List[hashtable]]::new()
            foreach ($rp in $rProcs) {
                $cleanName = ($rp.Name -replace '#\d+$', '')
                if (-not $cleanName.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase) -and $cleanName -ne 'System') {
                    $cleanName = "$cleanName.exe"
                }
                $calcCpu = [math]::Round([double]$rp.PercentProcessorTime / $rCores, 1)
                $rList.Add(@{
                    Name  = $cleanName
                    Pid   = [int]$rp.IDProcess
                    Cpu   = $calcCpu
                    MemMB = [math]::Round($rp.WorkingSetPrivate / 1MB, 1)
                })
            }
            if ($rList.Count -gt 0) { $topProcessesData[$remPc] = $rList }
        } catch {}
    }
}

$topProcessesJson = $topProcessesData | ConvertTo-Json -Depth 4 -Compress

# Construção dos Cards Laterais dos Computadores (Ordem Alfabética, Amarelo Puro, Sem Rótulos Desnecessários)
$cardsHtml = ""
foreach ($pc in $pcsList) {
    $cfgBar = switch ($pc) {
        'JFMELGACO-1' { 'bg-emerald-500' }
        'JFMELGACO-2' { 'bg-yellow-400' }
        'JFMELGACO-3' { 'bg-red-500' }
        'JFMELGACO-4' { 'bg-blue-500' }
        default       { 'bg-cyan-500' }
    }
    $cfgDot = switch ($pc) {
        'JFMELGACO-1' { 'bg-emerald-500 border-emerald-300 shadow-[0_0_6px_rgba(16,185,129,0.8)]' }
        'JFMELGACO-2' { 'bg-yellow-400 border-yellow-200 shadow-[0_0_6px_rgba(250,204,21,0.8)]' }
        'JFMELGACO-3' { 'bg-red-500 border-red-300 shadow-[0_0_6px_rgba(239,68,68,0.8)]' }
        'JFMELGACO-4' { 'bg-blue-500 border-blue-300 shadow-[0_0_6px_rgba(59,130,246,0.8)]' }
        default       { 'bg-cyan-500 border-cyan-300' }
    }
    $hoverBorder = switch ($pc) {
        'JFMELGACO-1' { 'hover:border-emerald-500/80' }
        'JFMELGACO-2' { 'hover:border-yellow-400/80' }
        'JFMELGACO-3' { 'hover:border-red-500/80' }
        'JFMELGACO-4' { 'hover:border-blue-500/80' }
        default       { 'hover:border-cyan-500/80' }
    }
    $st = $stats[$pc]
    $offlineClass = if (-not $st.isOnline) { 'card-offline-blink ' } elseif ($st.hasAlert) { 'card-alert-pulse ' } else { '' }
    $alertHidden = if (-not $st.hasAlert) { 'hidden ' } else { '' }
    $cpuBoxClass = if ($st.isCpuAlert) { 'bg-amber-500/20 border-amber-500/80 ring-1 ring-amber-500/40 ' } else { 'bg-slate-900/80 border-slate-800 ' }
    $ramBoxClass = if ($st.isRamAlert) { 'bg-red-500/20 border-red-500/80 ring-1 ring-red-500/40 ' } else { 'bg-slate-900/80 border-slate-800 ' }
    $diskBoxClass = if ($st.isDiskAlert) { 'bg-amber-500/20 border-amber-500/80 ring-1 ring-amber-500/40 ' } else { 'bg-slate-900/80 border-slate-800 ' }

    $cardsHtml += @"
            <!-- Card: $pc -->
            <div id="cardHost_$pc" onclick="selectMachineHighlight('$pc')" title="Clique para destacar $pc em branco nos gráficos" class="node-card flex-1 flex flex-col justify-between bg-cardbg border border-slate-700/70 $hoverBorder rounded-xl p-2 shadow-md transition-all relative overflow-hidden cursor-pointer select-none $offlineClass$(if (-not $st.isOnline) { 'opacity-60 ' })">
                <div id="cardTopBar_$pc" class="absolute top-0 left-0 right-0 h-1 $cfgBar transition-all"></div>
                <div class="flex items-center justify-between gap-1 pt-0.5 flex-nowrap overflow-hidden">
                    <div class="flex items-center gap-1.5 min-w-0 flex-1 overflow-hidden">
                        <span id="cardDot_$pc" class="h-2.5 w-2.5 rounded-full $cfgDot inline-block shrink-0 transition-all"></span>
                        <strong class="text-white text-xs font-bold tracking-wide truncate whitespace-nowrap" id="cardName_$pc">$pc</strong>
                    </div>
                    <div class="flex items-center gap-1 shrink-0 flex-nowrap">
                        <span id="cardAlertBadge_$pc" class="${alertHidden}text-[8.5px] px-1.5 py-0.2 rounded font-bold bg-amber-500/20 text-amber-300 border border-amber-500/50 uppercase tracking-tight shrink-0 animate-pulse whitespace-nowrap" title="$($st.alertTitle)">⚠️ Atenção</span>
                    </div>
                </div>
                <div class="flex items-center justify-between text-[10px] bg-slate-900/60 rounded px-2 py-0.5 border border-slate-800/80 my-0.5">
                    <span id="cardStatus_$pc" class="flex items-center gap-1">
                        <span id="cardStatusDot_$pc" class="h-2 w-2 rounded-full $($st.onlineDotClass)"></span>
                        <span id="cardStatusText_$pc" class="$($st.onlineTextClass) font-medium">$($st.statusText)</span>
                    </span>
                    <div class="flex items-center gap-1">
                        <span class="text-[8.5px] px-1.5 py-0.2 rounded font-mono font-semibold bg-indigo-500/20 text-indigo-300 border border-indigo-500/30 hover:bg-indigo-500/40 transition cursor-pointer" onclick="event.stopPropagation(); openProcessModal('$pc')" title="Ver Top 10 Processos com maior consumo">&#9889; Top 10</span>
                        <span id="card_${pc}_ping" class="text-[9px] px-1.5 py-0.2 rounded font-mono font-semibold bg-slate-800 text-cyan-300 border border-cyan-500/30" title="Latência ICMP (Ping RTT)">$(if ($st.isOnline -and $null -ne $st.ping) { "$($st.ping)ms" } else { "---" })</span>
                        <span id="card_${pc}_uptime" class="text-[9px] px-1.5 py-0.2 rounded font-mono font-semibold bg-slate-800 text-amber-300 border border-amber-500/30" title="Uptime contínuo">&#9201; $(if ($st.isOnline -and $st.uptime) { $st.uptime } else { "---" })</span>
                        <span id="card_${pc}_temp" class="text-[9px] px-1.5 py-0.2 rounded font-mono font-semibold bg-slate-800 text-rose-300 border border-rose-500/30" title="Temperatura de Hardware">&#127777;&#xFE0F; $(if ($st.isOnline -and $st.latestTemp) { "$($st.latestTemp)&deg;C" } else { "---" })</span>
                    </div>
                </div>
                <div class="grid grid-cols-5 gap-1 text-center">
                    <div class="border rounded px-1 py-1 $(if ($st.isOnline) { $cpuBoxClass } else { 'bg-slate-900/40 border-slate-800/60 opacity-60 ' })" id="box_${pc}_cpu" title="CPU Atual: $(if ($st.isOnline) { "$($st.latestCpu)%" } else { "Offline" })">
                        <span class="text-[8px] text-slate-400 uppercase block font-semibold">CPU</span>
                        <strong class="text-xs $(if (-not $st.isOnline) { 'text-slate-500' } elseif ($st.isCpuAlert) { 'text-amber-300 font-bold' } else { 'text-white' })" id="card_${pc}_cpu">$(if ($st.isOnline) { "$($st.latestCpu)%" } else { "---" })</strong>
                    </div>
                    <div class="border rounded px-1 py-1 $(if ($st.isOnline) { $ramBoxClass } else { 'bg-slate-900/40 border-slate-800/60 opacity-60 ' })" id="box_${pc}_ram" title="RAM Atual: $(if ($st.isOnline) { "$($st.latestRam)%" } else { "Offline" })">
                        <span class="text-[8px] text-slate-400 uppercase block font-semibold">RAM</span>
                        <strong class="text-xs $(if (-not $st.isOnline) { 'text-slate-500' } elseif ($st.isRamAlert) { 'text-red-300 font-bold' } else { 'text-white' })" id="card_${pc}_ram">$(if ($st.isOnline) { "$($st.latestRam)%" } else { "---" })</strong>
                    </div>
                    <div class="border rounded px-1 py-1 $(if ($st.isOnline) { $diskBoxClass } else { 'bg-slate-900/40 border-slate-800/60 opacity-60 ' })" id="box_${pc}_disk" title="Espaço Livre em Disco C:">
                        <span class="text-[8px] text-slate-400 uppercase block font-semibold">Disco C:</span>
                        <strong class="text-xs $(if (-not $st.isOnline) { 'text-slate-500' } elseif ($st.isDiskAlert) { 'text-amber-300 font-bold' } else { 'text-emerald-400' })" id="card_${pc}_disk">$(if ($st.isOnline) { "$($st.diskFree)G" } else { "---" })</strong>
                    </div>
                    <div class="rounded px-1 py-1 $(if ($st.isOnline) { 'bg-slate-900/80 border border-slate-800 ' } else { 'bg-slate-900/40 border border-slate-800/60 opacity-60 ' })" id="box_${pc}_io" title="I/O Escrita Atual">
                        <span class="text-[8px] text-slate-400 uppercase block font-semibold">I/O W</span>
                        <strong class="text-xs $(if ($st.isOnline) { 'text-amber-400' } else { 'text-slate-500' })" id="card_${pc}_io">$(if ($st.isOnline) { "$($st.latestIoW)k" } else { "---" })</strong>
                    </div>
                    <div class="rounded px-1 py-1 $(if ($st.isOnline) { 'bg-slate-900/80 border border-slate-800 ' } else { 'bg-slate-900/40 border border-slate-800/60 opacity-60 ' })" id="box_${pc}_tx" title="Rede Tx Atual">
                        <span class="text-[8px] text-slate-400 uppercase block font-semibold">Rede Tx</span>
                        <strong class="text-xs $(if ($st.isOnline) { 'text-cyan-400' } else { 'text-slate-500' })" id="card_${pc}_tx">$(if ($st.isOnline) { "$($st.latestTx)k" } else { "---" })</strong>
                    </div>
                </div>
            </div>
"@
}

# Construção das linhas da tabela de resumo consolidado
$summaryTableRows = ""
foreach ($pc in $pcsList) {
    $st = $stats[$pc]
    $colorClass = switch ($pc) {
        'JFMELGACO-1' { 'text-emerald-400 font-semibold' }
        'JFMELGACO-2' { 'text-yellow-300 font-semibold' }
        'JFMELGACO-3' { 'text-red-400 font-semibold' }
        'JFMELGACO-4' { 'text-blue-400 font-semibold' }
        default       { 'text-cyan-300 font-semibold' }
    }
    $summaryTableRows += @"
                        <tr class="hover:bg-slate-800/50">
                            <td class="py-2.5 px-3 $colorClass">$pc $(if (-not $st.isOnline) { '<span class="text-[9px] text-red-400 font-bold ml-1">(Offline)</span>' })</td>
                            <td class="py-2.5 px-3" id="modal_${pc}_cpuAvg">$($st.avgCpu)%</td>
                            <td class="py-2.5 px-3 font-bold text-rose-400" id="modal_${pc}_cpuMax">$($st.maxCpu)%</td>
                            <td class="py-2.5 px-3" id="modal_${pc}_ramAvg">$($st.avgRam)%</td>
                            <td class="py-2.5 px-3" id="modal_${pc}_ramMax">$($st.maxRam)%</td>
                            <td class="py-2.5 px-3 text-amber-300 font-semibold" id="modal_${pc}_io">$($st.maxIoR) / $($st.maxIoW) KB/s</td>
                            <td class="py-2.5 px-3" id="modal_${pc}_rx">$($st.maxRx) KB/s</td>
                            <td class="py-2.5 px-3 font-bold text-cyan-400" id="modal_${pc}_tx">$($st.maxTx) KB/s</td>
                            <td class="py-2.5 px-3 text-emerald-400 font-bold" id="modal_${pc}_disk">$(if ($st.isOnline) { "$($st.diskFree) GB" } else { "---" })</td>
                            <td class="py-2.5 px-3 font-semibold text-cyan-300 font-mono" id="modal_${pc}_ping">$(if ($st.isOnline) { "$($st.ping) ms <span class=""text-[10px] text-slate-400 font-normal"">(méd $($st.avgPing)ms)</span>" } else { "---" })</td>
                            <td class="py-2.5 px-3 font-semibold text-amber-300 font-mono" id="modal_${pc}_uptime">$(if ($st.isOnline -and $st.uptime) { "&#9201; $($st.uptime) <span class=""text-[10px] text-slate-400 font-normal"">($($st.bootDate))</span>" } else { "---" })</td>
                            <td class="py-2.5 px-3 text-center"><button onclick="toggleSummaryModal(false); openProcessModal('$pc')" class="text-[10px] px-2 py-0.5 rounded bg-indigo-500/20 hover:bg-indigo-500/40 text-indigo-300 border border-indigo-500/40 font-semibold cursor-pointer">&#9889; Top 10</button></td>
                        </tr>
"@
}

# Serialização JSON para dados do Chart.js
$jsonTimestamps = $timestamps | ConvertTo-Json -Compress
$jsonData = $machineData | ConvertTo-Json -Depth 4 -Compress
$jsonPcsList = $pcsList | ConvertTo-Json -Compress
$jsonStats = $stats | ConvertTo-Json -Depth 4 -Compress
$startTime = if ($timestamps.Count -gt 0) { $timestamps[0] } else { "--:--:--" }
$endTime   = if ($timestamps.Count -gt 0) { $timestamps[-1] } else { "--:--:--" }
$totalPoints = $timestamps.Count

# Template HTML do Dashboard
$html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Monitor de Rede JFMELGACO v1.2.1</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script>
        tailwind.config = {
            theme: {
                extend: {
                    colors: {
                        darkbg: '#0b1120',
                        cardbg: '#0f172a',
                        borderbg: '#1e293b'
                    }
                }
            }
        }
    </script>
    <style>
        body { background-color: #0b1120; font-family: system-ui, -apple-system, sans-serif; }
        ::-webkit-scrollbar { width: 6px; height: 6px; }
        ::-webkit-scrollbar-track { background: #0f172a; }
        ::-webkit-scrollbar-thumb { background: #334155; border-radius: 3px; }
        ::-webkit-scrollbar-thumb:hover { background: #475569; }
        @keyframes pulseAlert {
            0%, 100% { border-color: rgba(239, 68, 68, 0.4); box-shadow: 0 0 0 0 rgba(239, 68, 68, 0.4); }
            50% { border-color: rgba(239, 68, 68, 0.9); box-shadow: 0 0 10px 2px rgba(239, 68, 68, 0.4); }
        }
        .card-alert-pulse {
            animation: pulseAlert 2s infinite ease-in-out;
        }
        @keyframes offlineBlink {
            0%, 100% { border-color: rgba(239, 68, 68, 0.3); opacity: 0.75; }
            50% { border-color: rgba(239, 68, 68, 0.8); opacity: 1; }
        }
        .card-offline-blink {
            animation: offlineBlink 1.5s infinite ease-in-out;
        }
    </style>
</head>
<body id="mainBody" class="bg-darkbg text-slate-100 h-screen max-h-screen flex flex-col p-2.5 overflow-hidden text-xs font-sans">

    <!-- HEADER ULTRA-COMPACTO -->
    <header class="flex flex-wrap items-center justify-between border-b border-borderbg pb-2 gap-2 text-xs shrink-0">
        <div class="flex items-center gap-2">
            <span class="relative flex h-2.5 w-2.5">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                <span id="livePulseDot" class="relative inline-flex rounded-full h-2.5 w-2.5 bg-emerald-500 transition-colors duration-300"></span>
            </span>
            <h1 class="text-sm font-bold text-white tracking-tight flex items-center gap-1.5">Monitor de Rede JFMELGACO <span class="text-[10px] text-cyan-400 font-normal px-1.5 py-0.2 rounded bg-cyan-950/60 border border-cyan-800/80">v1.2.1</span></h1>
            <span class="text-slate-500">|</span>
            <span class="text-slate-400" id="headerTimeRange">$startTime &rarr; $endTime</span>
            <span class="text-slate-500">|</span>
            <span class="text-cyan-400 font-semibold" id="headerSampleCount">$totalPoints amostras</span>
        </div>

        <div class="flex items-center gap-2">
            <!-- Seletor Task Manager -->
            <div class="flex items-center gap-1 bg-slate-900/90 px-1 py-0.5 rounded-lg border border-slate-700/60">
                <button onclick="setWindowMode(60)" id="btnWin_60" class="text-[11px] px-2.5 py-0.5 rounded font-bold bg-cyan-500/20 text-cyan-300 border border-cyan-500/40 cursor-pointer">
                    &#9889; 60 (TaskMgr)
                </button>
                <button onclick="setWindowMode(120)" id="btnWin_120" class="text-[11px] px-2.5 py-0.5 rounded text-slate-400 hover:text-slate-200 cursor-pointer">
                    120
                </button>
                <button onclick="setWindowMode(300)" id="btnWin_300" class="text-[11px] px-2.5 py-0.5 rounded text-slate-400 hover:text-slate-200 cursor-pointer">
                    5h (300)
                </button>
                <button onclick="setWindowMode('all')" id="btnWin_all" class="text-[11px] px-2.5 py-0.5 rounded text-slate-400 hover:text-slate-200 cursor-pointer">
                    Todas
                </button>
            </div>

            <!-- Auto-Refresh com Período Customizável -->
            <div class="flex items-center gap-1.5 bg-cardbg border border-borderbg px-2 py-1 rounded-lg">
                <button onclick="promptChangeInterval()" class="flex items-center gap-1 hover:text-cyan-300 transition cursor-pointer" title="Clique para alterar o período de atualização (mínimo 1s)">
                    <span class="text-slate-400 text-[11px]">Auto:</span>
                    <span id="countdownEl" class="text-cyan-400 font-bold text-[11px] w-6 text-center">5s</span>
                </button>
                <button id="pauseBtn" onclick="toggleAutoRefresh()" class="ml-0.5 text-[10px] px-1.5 py-0.5 rounded bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 cursor-pointer" title="Pausar / Retomar">&#9208;</button>
                <button onclick="promptChangeInterval()" class="text-[9px] px-1.5 py-0.5 rounded bg-cyan-950/70 hover:bg-cyan-900/80 text-cyan-300 border border-cyan-800/80 font-mono cursor-pointer" title="Definir intervalo">&#9881; <span id="intervalSecLabel">5s</span></button>
            </div>

            <!-- Botão Gerenciar Nós -->
            <button onclick="toggleMachinesModal(true)" class="text-[11px] px-2.5 py-1 rounded-lg bg-cyan-500/20 hover:bg-cyan-500/30 text-cyan-300 border border-cyan-500/40 font-medium transition cursor-pointer flex items-center gap-1" title="Adicionar, editar e descobrir computadores na rede">
                &#128187; Gerenciar N&oacute;s
            </button>

            <!-- Botão Tabela de Resumo Modal -->
            <button onclick="toggleSummaryModal(true)" class="text-[11px] px-2.5 py-1 rounded-lg bg-indigo-500/20 hover:bg-indigo-500/30 text-indigo-300 border border-indigo-500/40 font-medium transition cursor-pointer flex items-center gap-1">
                &#128203; Tabela Resumo
            </button>

            <!-- Alternador Tela Única / Rolagem -->
            <button onclick="toggleScrollMode()" id="btnScrollMode" title="Alternar entre Tela Única e Modo com Rolagem" class="text-[11px] px-2 py-1 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 cursor-pointer">
                &#128421;&#xFE0F; Tela &Uacute;nica
            </button>
        </div>
    </header>

    <!-- CONTAINER PRINCIPAL: GRÁFICOS (ESQUERDA) + SERVIDORES NA VERTICAL (DIREITA) -->
    <div id="dashboardContent" class="flex-1 flex flex-col lg:flex-row gap-2.5 min-h-0 my-1 overflow-hidden">

        <!-- ÁREA PRINCIPAL DOS GRÁFICOS: GRID 2 COLUNAS X 3 LINHAS (TELA ÚNICA) OU ROLAGEM VERTICAL (MODO ROLAGEM) -->
        <main id="chartsMain" class="flex-1 grid grid-cols-1 lg:grid-cols-2 lg:grid-rows-3 gap-2 h-full min-h-0 overflow-hidden pr-0.5">

            <!-- 1. CPU CHART -->
            <div id="card-chart-cpu" class="chart-card bg-cardbg border border-borderbg rounded-xl p-2 flex flex-col h-full min-h-0 shadow">
                <div class="flex items-center justify-between mb-1 px-1 shrink-0">
                    <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                        <span class="h-2 w-2 rounded-full bg-cyan-400"></span>
                        1. Uso de CPU (%) &larr; Task Manager
                    </span>
                </div>
                <div class="chart-wrapper flex-1 min-h-0 relative">
                    <canvas id="cpuChart"></canvas>
                </div>
            </div>

            <!-- 2. RAM CHART -->
            <div id="card-chart-ram" class="chart-card bg-cardbg border border-borderbg rounded-xl p-2 flex flex-col h-full min-h-0 shadow">
                <div class="flex items-center justify-between mb-1 px-1 shrink-0">
                    <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                        <span class="h-2 w-2 rounded-full bg-indigo-400"></span>
                        2. Uso de Mem&oacute;ria RAM (%) &larr; Task Manager
                    </span>
                </div>
                <div class="chart-wrapper flex-1 min-h-0 relative">
                    <canvas id="ramChart"></canvas>
                </div>
            </div>

            <!-- 3. RX CHART (Download Local) -->
            <div id="card-chart-rx" class="chart-card bg-cardbg border border-borderbg rounded-xl p-2 flex flex-col h-full min-h-0 shadow">
                <div class="flex items-center justify-between mb-1 px-1 shrink-0">
                    <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                        <span class="h-2 w-2 rounded-full bg-emerald-400"></span>
                        3. Rede Local: Recep&ccedil;&atilde;o / Download (Rx em KB/s)
                    </span>
                </div>
                <div class="chart-wrapper flex-1 min-h-0 relative">
                    <canvas id="rxChart"></canvas>
                </div>
            </div>

            <!-- 4. TX CHART (Upload Local) -->
            <div id="card-chart-tx" class="chart-card bg-cardbg border border-borderbg rounded-xl p-2 flex flex-col h-full min-h-0 shadow">
                <div class="flex items-center justify-between mb-1 px-1 shrink-0">
                    <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                        <span class="h-2 w-2 rounded-full bg-cyan-400"></span>
                        4. Rede Local: Transmiss&atilde;o / Upload (Tx em KB/s)
                    </span>
                </div>
                <div class="chart-wrapper flex-1 min-h-0 relative">
                    <canvas id="txChart"></canvas>
                </div>
            </div>

            <!-- 5. PING LATENCY CHART -->
            <div id="card-chart-ping" class="chart-card bg-cardbg border border-borderbg rounded-xl p-2 flex flex-col h-full min-h-0 shadow">
                <div class="flex items-center justify-between mb-1 px-1 shrink-0">
                    <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                        <span class="h-2 w-2 rounded-full bg-purple-400"></span>
                        5. Rede: Lat&ecirc;ncia ICMP (Ping RTT em ms)
                    </span>
                </div>
                <div class="chart-wrapper flex-1 min-h-0 relative">
                    <canvas id="pingChart"></canvas>
                </div>
            </div>

            <!-- 6. TEMPERATURA DOS EQUIPAMENTOS CHART -->
            <div id="card-chart-temp" class="chart-card bg-cardbg border border-borderbg rounded-xl p-2 flex flex-col h-full min-h-0 shadow">
                <div class="flex items-center justify-between mb-1 px-1 shrink-0">
                    <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                        <span class="h-2 w-2 rounded-full bg-rose-400"></span>
                        6. Hardware: Temperatura (&deg;C)
                    </span>
                    <div class="flex items-center gap-1">
                        <button onclick="toggleSlot6Chart('temp')" id="btnSlot6Temp" title="Exibir Temperatura no slot 6" class="text-[10px] px-1.5 py-0.5 rounded bg-rose-500/30 text-rose-300 font-bold border border-rose-500/50 transition cursor-pointer">&#127777;&#xFE0F; Temp</button>
                        <button onclick="toggleSlot6Chart('internet')" id="btnSlot6Net" title="Exibir Tráfego Internet no slot 6" class="text-[10px] px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 hover:text-white border border-slate-700 transition cursor-pointer">&#127760; Internet</button>
                    </div>
                </div>
                <div class="chart-wrapper flex-1 min-h-0 relative">
                    <canvas id="tempChart"></canvas>
                </div>
            </div>

            <!-- 7. PERFORMANCE DE REDE / INTERNET CHART (SLOT 6 ALTERNATIVO OU ROLAGEM) -->
            <div id="card-chart-internet" class="chart-card bg-cardbg border border-borderbg rounded-xl p-2 flex flex-col h-full min-h-0 shadow hidden">
                <div class="flex items-center justify-between mb-1 px-1 shrink-0">
                    <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                        <span class="h-2 w-2 rounded-full bg-blue-400"></span>
                        6. Tr&aacute;fego Internet (Download / Upload em Mbps)
                    </span>
                    <div class="flex items-center gap-1">
                        <button onclick="toggleSlot6Chart('temp')" class="text-[10px] px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 hover:text-white border border-slate-700 transition cursor-pointer">&#127777;&#xFE0F; Temp</button>
                        <button onclick="toggleSlot6Chart('internet')" class="text-[10px] px-1.5 py-0.5 rounded bg-blue-500/30 text-blue-300 font-bold border border-blue-500/50 transition cursor-pointer">&#127760; Internet</button>
                    </div>
                </div>
                <div class="chart-wrapper flex-1 min-h-0 relative">
                    <canvas id="internetChart"></canvas>
                </div>
            </div>

            <!-- 8. DISK FREE CHART -->
            <div id="card-chart-disk" class="chart-card bg-cardbg border border-borderbg rounded-xl p-2 flex flex-col h-full min-h-0 shadow hidden">
                <div class="flex items-center justify-between mb-1 px-1 shrink-0">
                    <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                        <span class="h-2 w-2 rounded-full bg-emerald-400"></span>
                        8. Armazenamento: Espa&ccedil;o Livre em Disco C: (GB)
                    </span>
                </div>
                <div class="chart-wrapper flex-1 min-h-0 relative">
                    <canvas id="diskChart"></canvas>
                </div>
            </div>

            <!-- 9. DISK IO CHART -->
            <div id="card-chart-io" class="chart-card bg-cardbg border border-borderbg rounded-xl p-2 flex flex-col h-full min-h-0 shadow hidden">
                <div class="flex items-center justify-between mb-1 px-1 shrink-0">
                    <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                        <span class="h-2 w-2 rounded-full bg-amber-400"></span>
                        9. Disco C: Taxa de I/O Escrita (KB/s)
                    </span>
                </div>
                <div class="chart-wrapper flex-1 min-h-0 relative">
                    <canvas id="ioChart"></canvas>
                </div>
            </div>

        </main>

        <!-- BARRA LATERAL VERTICAL DIREITA: CARDS DOS COMPUTADORES (DISTRIBUICAO UNIFORME SEM ESPACO VAGO) -->
        <aside id="nodesSidebar" class="w-full lg:w-[360px] xl:w-[400px] flex flex-col justify-between gap-2 shrink-0 h-full overflow-y-auto pr-0.5">
            <div class="flex items-center justify-between px-1 text-[11px] text-slate-400 font-semibold border-b border-borderbg pb-1 shrink-0">
                <span class="flex items-center gap-1.5 text-slate-300">
                    <span class="h-2 w-2 rounded-full bg-cyan-400"></span>
                    N&oacute;s Monitorados ($($pcsList.Count))
                </span>
                <span class="text-[10px] text-slate-400">Clique para destacar [Branco]</span>
            </div>

$cardsHtml

        </aside>
    </div>

    <!-- MODAL POPUP: TABELA CONSOLIDADA DE RESUMO ESTATÍSTICO -->
    <div id="summaryModal" class="fixed inset-0 bg-black/75 backdrop-blur-sm z-50 flex items-center justify-center p-4 hidden">
        <div class="bg-cardbg border border-borderbg rounded-2xl max-w-5xl w-full max-h-[85vh] flex flex-col shadow-2xl overflow-hidden">
            <div class="flex items-center justify-between p-4 border-b border-borderbg bg-slate-800/40">
                <div class="flex items-center gap-2">
                    <span class="text-base">&#128203;</span>
                    <h2 class="text-sm font-bold text-white">Tabela de Resumo Estat&iacute;stico Consolidado</h2>
                </div>
                <button onclick="toggleSummaryModal(false)" class="text-slate-400 hover:text-white px-2.5 py-1 rounded-lg hover:bg-slate-800 transition cursor-pointer text-xs">
                    &times; Fechar
                </button>
            </div>
            <div class="overflow-x-auto flex-1 p-4">
                <table class="w-full text-left text-xs border-collapse">
                    <thead>
                        <tr class="text-slate-400 border-b border-borderbg bg-slate-800/20">
                            <th class="py-2.5 px-3 font-semibold">Computador</th>
                            <th class="py-2.5 px-3 font-semibold">CPU M&eacute;d</th>
                            <th class="py-2.5 px-3 font-semibold text-rose-400">CPU M&aacute;x</th>
                            <th class="py-2.5 px-3 font-semibold">RAM M&eacute;d</th>
                            <th class="py-2.5 px-3 font-semibold">RAM M&aacute;x</th>
                            <th class="py-2.5 px-3 font-semibold text-amber-300">I/O M&aacute;x (R / W)</th>
                            <th class="py-2.5 px-3 font-semibold">Rx M&aacute;x</th>
                            <th class="py-2.5 px-3 font-semibold text-cyan-400">Tx M&aacute;x</th>
                            <th class="py-2.5 px-3 font-semibold text-emerald-400">Disco C: Livre</th>
                            <th class="py-2.5 px-3 font-semibold text-cyan-300">Ping Atual (M&eacute;d)</th>
                            <th class="py-2.5 px-3 font-semibold text-amber-300">Uptime Cont&iacute;nuo</th>
                            <th class="py-2.5 px-3 font-semibold text-center">Processos</th>
                        </tr>
                    </thead>
                    <tbody class="divide-y divide-borderbg font-mono text-[11px]">
$summaryTableRows
                    </tbody>
                </table>
            </div>
            <div class="p-3 border-t border-borderbg text-center text-slate-500 text-[11px] bg-slate-800/20">
                Pressione ESC ou clique fora para fechar | Relat&oacute;rio gerado pela IA Antigravity
            </div>
        </div>
    </div>

    <!-- MODAL POPUP: TOP 10 PROCESSOS POR NÓ -->
    <div id="processModal" class="fixed inset-0 bg-black/80 backdrop-blur-sm z-50 flex items-center justify-center p-3 hidden transition-opacity">
        <div class="bg-cardbg border border-borderbg rounded-2xl max-w-2xl w-full max-h-[90vh] flex flex-col shadow-2xl overflow-hidden ring-1 ring-slate-700/50">
            <div class="flex items-center justify-between p-3.5 border-b border-borderbg bg-slate-800/60">
                <div class="flex items-center gap-2">
                    <span id="procModalDot" class="h-3.5 w-3.5 rounded-full bg-blue-500 shadow-md"></span>
                    <div>
                        <h3 class="text-sm font-bold text-white flex items-center gap-2" id="procModalTitle">
                            &#9889; Top 10 Processos &mdash; <span class="font-mono text-cyan-300">JFMELGACO-1</span>
                        </h3>
                        <p class="text-[10px] text-slate-400" id="procModalSubtitle">Processos com maior consumo instant&acirc;neo de recursos</p>
                    </div>
                </div>
                <div class="flex items-center gap-2">
                    <button id="procModalToggleVisBtn" onclick="toggleVisibilityFromModal()" class="text-[10px] px-2.5 py-1 rounded font-medium transition cursor-pointer flex items-center gap-1 shadow-sm">
                        &#128065; Exibir gr&aacute;ficos &#10003;
                    </button>
                    <button onclick="closeProcessModal()" class="text-slate-400 hover:text-white px-2.5 py-1 rounded-lg hover:bg-slate-800 transition cursor-pointer text-xs font-bold">
                        &times; Fechar
                    </button>
                </div>
            </div>
            <div class="overflow-y-auto flex-1 p-3">
                <table class="w-full text-left text-xs border-collapse">
                    <thead>
                        <tr class="text-[10px] text-slate-400 uppercase border-b border-borderbg bg-slate-900/60">
                            <th class="py-2 px-2.5 font-semibold text-center w-8">#</th>
                            <th class="py-2 px-3 font-semibold">Processo</th>
                            <th class="py-2 px-2 font-semibold text-right w-16">PID</th>
                            <th class="py-2 px-3 font-semibold text-right w-28">CPU (%)</th>
                            <th class="py-2 px-3 font-semibold text-right w-28">Mem&oacute;ria RAM</th>
                        </tr>
                    </thead>
                    <tbody id="procModalTableBody" class="divide-y divide-borderbg/40 font-mono text-[11px]"></tbody>
                </table>
                <div id="procModalEmpty" class="hidden text-center py-8 text-slate-400 text-xs">
                    Nenhum processo monitorado dispon&iacute;vel para este n&oacute; no momento.
                </div>
            </div>
            <div class="flex items-center justify-between p-3 border-t border-borderbg bg-slate-900/80 text-[10px] text-slate-400">
                <div class="flex items-center gap-3" id="procModalTotals">
                    <span>Total CPU Top 10: <strong class="text-amber-400 font-bold" id="procTotalCpu">0%</strong></span>
                    <span>Total RAM Top 10: <strong class="text-indigo-400 font-bold" id="procTotalRam">0 MB</strong></span>
                </div>
                <div class="text-[9px] text-slate-500">Normalizado por n&uacute;cleos l&oacute;gicos (Max 100%)</div>
            </div>
        </div>
    </div>

    <!-- MODAL: GERENCIAMENTO DE MAQUINAS (CADASTRO / EDICAO / DESCOBERTA) -->
    <div id="machinesModal" class="fixed inset-0 bg-black/80 backdrop-blur-sm z-50 flex items-center justify-center p-3 hidden transition-opacity">
        <div class="bg-cardbg border border-borderbg rounded-2xl max-w-xl w-full max-h-[90vh] flex flex-col shadow-2xl overflow-hidden ring-1 ring-slate-700/50">
            <div class="flex items-center justify-between p-3.5 border-b border-borderbg bg-slate-800/60">
                <div class="flex items-center gap-2">
                    <span class="text-lg">&#128187;</span>
                    <div>
                        <h3 class="text-sm font-bold text-white flex items-center gap-2">Gerenciamento de N&oacute;s da Rede</h3>
                        <p class="text-[10px] text-slate-400">Cadastre, edite ou descubra computadores para o monitoramento cont&iacute;nuo</p>
                    </div>
                </div>
                <button onclick="toggleMachinesModal(false)" class="text-slate-400 hover:text-white px-2.5 py-1 rounded-lg hover:bg-slate-800 transition cursor-pointer text-xs font-bold">&times; Fechar</button>
            </div>
            <div class="p-4 overflow-y-auto flex-1 flex flex-col gap-3">
                <!-- Formulário Adicionar Nó -->
                <div class="bg-slate-900/70 p-3 rounded-xl border border-slate-800 flex flex-col gap-2">
                    <label class="text-[11px] font-semibold text-slate-300">Adicionar Novo N&oacute; ou Servidor:</label>
                    <div class="flex gap-2">
                        <input type="text" id="newMachineInput" placeholder="Ex: JFMELGACO-5 ou 192.168.1.50" class="flex-1 bg-slate-950 border border-slate-700 rounded-lg px-2.5 py-1.5 text-xs text-white focus:outline-none focus:border-cyan-400">
                        <button onclick="addNewMachine()" class="px-3 py-1.5 rounded-lg bg-cyan-600 hover:bg-cyan-500 text-white font-bold text-xs transition cursor-pointer flex items-center gap-1">&#43; Adicionar</button>
                    </div>
                </div>

                <!-- Lista de Computadores Monitorados -->
                <div class="flex flex-col gap-1.5">
                    <div class="flex items-center justify-between">
                        <span class="text-[11px] font-semibold text-slate-300">Computadores Cadastrados (Ordem Alfab&eacute;tica):</span>
                        <button onclick="scanNetworkNodes()" id="btnScanNet" class="text-[10px] px-2 py-1 rounded bg-indigo-500/20 hover:bg-indigo-500/30 text-indigo-300 border border-indigo-500/40 font-medium transition cursor-pointer flex items-center gap-1" title="Verificar sub-rede local em busca de hosts online">&#128269; Descobrir N&oacute;s na Rede</button>
                    </div>
                    <div id="machinesListContainer" class="flex flex-col gap-1 max-h-[220px] overflow-y-auto pr-1 divide-y divide-slate-800/80"></div>
                </div>

                <!-- Feedback de Descoberta -->
                <div id="scanResultBox" class="hidden p-2.5 rounded-lg bg-slate-900/90 border border-indigo-500/30 text-xs text-slate-300">
                    <div class="flex items-center justify-between mb-1.5">
                        <span class="font-bold text-indigo-300 text-[11px] flex items-center gap-1">&#10004; N&oacute;s Detectados na Sub-rede:</span>
                        <button onclick="document.getElementById('scanResultBox').classList.add('hidden')" class="text-slate-500 hover:text-white text-xs">&times;</button>
                    </div>
                    <div id="scanResultList" class="flex flex-wrap gap-1.5"></div>
                </div>
            </div>
            <div class="p-3 border-t border-borderbg bg-slate-900/80 flex items-center justify-between text-xs">
                <span class="text-[10px] text-slate-500">Salvo automaticamente em machines.json e persistido localmente</span>
                <div class="flex gap-2">
                    <button onclick="saveMachinesConfig()" class="px-3.5 py-1.5 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white font-bold text-xs transition cursor-pointer flex items-center gap-1">&#128190; Salvar Altera&ccedil;&otilde;es</button>
                    <button onclick="toggleMachinesModal(false)" class="px-3 py-1.5 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 text-xs transition cursor-pointer">Fechar</button>
                </div>
            </div>
        </div>
    </div>

    <!-- SCRIPT CHART.JS & CONTROLE -->
    <script>
        let timestamps = $jsonTimestamps;
        let rawData = $jsonData;
        let pcsList = $jsonPcsList;
        let dashboardTopProcesses = $topProcessesJson;

        // Paleta oficial de cores: Amarelo tradicional puro (#facc15), Verde (#10b981), Vermelho (#ef4444), Azul (#3b82f6)
        const colors = {
            'JFMELGACO-1': { border: '#10b981', bg: 'rgba(16, 185, 129, 0.14)' },
            'JFMELGACO-2': { border: '#facc15', bg: 'rgba(250, 204, 21, 0.14)' },
            'JFMELGACO-3': { border: '#ef4444', bg: 'rgba(239, 68, 68, 0.14)' },
            'JFMELGACO-4': { border: '#3b82f6', bg: 'rgba(59, 130, 246, 0.14)' }
        };

        const defaultPalette = ['#06b6d4', '#a855f7', '#ec4899', '#f97316', '#14b8a6', '#84cc16'];
        pcsList.forEach((pc, idx) => {
            if (!colors[pc]) {
                const col = defaultPalette[idx % defaultPalette.length];
                colors[pc] = { border: col, bg: col + '22' };
            }
        });

        // Lógica de Janela Temporal Task Manager
        let currentWindowSize = localStorage.getItem('monitorWindowSize') || '60';

        function alignDataTaskmanager(allTimestamps, seriesData, winSize) {
            const numSize = winSize === 'all' ? 'all' : parseInt(winSize);
            if (numSize === 'all' || allTimestamps.length >= numSize) {
                const start = numSize === 'all' ? 0 : Math.max(0, allTimestamps.length - numSize);
                return {
                    labels: allTimestamps.slice(start),
                    data: seriesData ? seriesData.slice(start) : []
                };
            } else {
                const emptyCount = numSize - allTimestamps.length;
                const emptyLabels = Array(emptyCount).fill('');
                const emptyData = Array(emptyCount).fill(null);
                return {
                    labels: emptyLabels.concat(allTimestamps),
                    data: emptyData.concat(seriesData || [])
                };
            }
        }

        function getAlignedDataset(pc, metricKey) {
            const series = (rawData[pc] && rawData[pc][metricKey]) ? rawData[pc][metricKey] : [];
            return alignDataTaskmanager(timestamps, series, currentWindowSize).data;
        }

        const commonOptions = {
            responsive: true,
            maintainAspectRatio: false,
            interaction: { mode: 'index', intersect: false },
            plugins: {
                legend: { display: false },
                tooltip: {
                    backgroundColor: '#1e293b',
                    borderColor: '#475569',
                    borderWidth: 1,
                    titleColor: '#f8fafc',
                    bodyColor: '#cbd5e1',
                    filter: item => item.raw !== null
                }
            },
            scales: {
                x: {
                    grid: { color: 'rgba(51, 65, 85, 0.35)' },
                    ticks: { color: '#64748b', maxTicksLimit: 12, font: { size: 10 } }
                },
                y: {
                    grid: { color: 'rgba(51, 65, 85, 0.35)' },
                    ticks: { color: '#64748b', font: { size: 10 } }
                }
            },
            spanGaps: true,
            elements: {
                line: { tension: 0.25, borderWidth: 2, spanGaps: true },
                point: { radius: 0, hoverRadius: 0 }
            }
        };

        // CONTROLE INTERATIVO DE VISIBILIDADE E DESTAQUE EM BRANCO (CLICK NO CARD)
        let machineVisibility = {};
        try {
            const saved = localStorage.getItem('monitorMachineVisibility');
            if (saved) machineVisibility = JSON.parse(saved);
        } catch(e) {
            machineVisibility = {};
        }

        function isMachineVisible(pc) {
            return machineVisibility[pc] !== false;
        }

        let highlightedMachine = null;

        function selectMachineHighlight(pc) {
            if (highlightedMachine === pc) {
                highlightedMachine = null;
            } else {
                highlightedMachine = pc;
            }
            updateCardSelectionVisuals();
            refreshChartsWindow('none');
        }

        function updateCardSelectionVisuals() {
            pcsList.forEach(pc => {
                const card = document.getElementById('cardHost_' + pc);
                if (!card) return;
                if (highlightedMachine === pc) {
                    card.classList.add('ring-2', 'ring-white', 'shadow-[0_0_15px_rgba(255,255,255,0.4)]', 'bg-slate-800/95');
                } else {
                    card.classList.remove('ring-2', 'ring-white', 'shadow-[0_0_15px_rgba(255,255,255,0.4)]', 'bg-slate-800/95');
                }
            });
        }

        function updateCardVisualState(pc) {
            const card = document.getElementById('cardHost_' + pc);
            const topBar = document.getElementById('cardTopBar_' + pc);
            if (!card || !topBar) return;
            const visible = isMachineVisible(pc);
            if (visible) {
                card.classList.remove('opacity-40', 'grayscale-[0.8]', 'border-dashed');
                card.classList.add('opacity-100');
            } else {
                card.classList.remove('opacity-100');
                card.classList.add('opacity-40', 'grayscale-[0.8]', 'border-dashed');
            }
        }

        function toggleMachineVisibility(pc) {
            machineVisibility[pc] = !isMachineVisible(pc);
            try {
                localStorage.setItem('monitorMachineVisibility', JSON.stringify(machineVisibility));
            } catch(e) {}
            updateCardVisualState(pc);
            refreshChartsWindow('none');
        }

        const initialLabels = alignDataTaskmanager(timestamps, timestamps, currentWindowSize).labels;
                function getLatestDiskFree(pc) {
            if (window.stats && window.stats[pc] && window.stats[pc].diskFree !== undefined) {
                return window.stats[pc].diskFree;
            }
            if (typeof stats !== 'undefined' && stats && stats[pc] && stats[pc].diskFree !== undefined) {
                return stats[pc].diskFree;
            }
            if (rawData && rawData[pc] && Array.isArray(rawData[pc].diskFree) && rawData[pc].diskFree.length > 0) {
                for (let i = rawData[pc].diskFree.length - 1; i >= 0; i--) {
                    if (rawData[pc].diskFree[i] !== null && rawData[pc].diskFree[i] !== undefined) {
                        return rawData[pc].diskFree[i];
                    }
                }
            }
            return 0;
        }

        const charts = {};

        function createDatasetList(metricKey) {
            return pcsList.map(pc => {
                const isH = (highlightedMachine === pc);
                const col = colors[pc] ? colors[pc].border : '#38bdf8';
                return {
                    pcKey: pc,
                    metricKey: metricKey,
                    label: pc,
                    data: getAlignedDataset(pc, metricKey),
                    borderColor: isH ? '#ffffff' : col,
                    backgroundColor: isH ? 'rgba(255,255,255,0.1)' : (colors[pc] ? colors[pc].bg : 'rgba(56,189,248,0.1)'),
                    borderWidth: isH ? 3.5 : 2,
                    pointBackgroundColor: isH ? '#ffffff' : col,
                    pointRadius: 0,
                    pointHoverRadius: 0,
                    fill: false,
                    spanGaps: true,
                    hidden: !isMachineVisible(pc),
                    order: isH ? -1 : 1
                };
            });
        }

        // 1. CPU CHART
        charts.cpu = new Chart(document.getElementById('cpuChart'), {
            type: 'line',
            data: { labels: initialLabels, datasets: createDatasetList('cpu') },
            options: {
                ...commonOptions,
                scales: {
                    ...commonOptions.scales,
                    y: { ...commonOptions.scales.y, min: 0, max: 100, ticks: { ...commonOptions.scales.y.ticks, callback: v => v + '%' } }
                }
            }
        });

        // 2. RAM CHART
        charts.ram = new Chart(document.getElementById('ramChart'), {
            type: 'line',
            data: { labels: initialLabels, datasets: createDatasetList('ramPct') },
            options: {
                ...commonOptions,
                scales: {
                    ...commonOptions.scales,
                    y: { ...commonOptions.scales.y, min: 0, max: 100, ticks: { ...commonOptions.scales.y.ticks, callback: v => v + '%' } }
                }
            }
        });

        // 3. RX CHART (Download Local)
        charts.rx = new Chart(document.getElementById('rxChart'), {
            type: 'line',
            data: { labels: initialLabels, datasets: createDatasetList('rx') },
            options: {
                ...commonOptions,
                scales: {
                    ...commonOptions.scales,
                    y: { ...commonOptions.scales.y, min: 0, ticks: { ...commonOptions.scales.y.ticks, callback: v => v + ' KB/s' } }
                }
            }
        });

        // 4. TX CHART (Upload Local)
        charts.tx = new Chart(document.getElementById('txChart'), {
            type: 'line',
            data: { labels: initialLabels, datasets: createDatasetList('tx') },
            options: {
                ...commonOptions,
                scales: {
                    ...commonOptions.scales,
                    y: { ...commonOptions.scales.y, min: 0, ticks: { ...commonOptions.scales.y.ticks, callback: v => v + ' KB/s' } }
                }
            }
        });

        // 5. DISK FREE CHART
        const initialVisiblePcs = pcsList.filter(pc => isMachineVisible(pc));
        charts.disk = new Chart(document.getElementById('diskChart'), {
            type: 'bar',
            data: {
                labels: initialVisiblePcs,
                datasets: [{
                    label: 'Espaço Livre (GB)',
                    data: initialVisiblePcs.map(pc => getLatestDiskFree(pc)),
                    backgroundColor: initialVisiblePcs.map(pc => (highlightedMachine === pc ? '#ffffff' : (colors[pc] ? colors[pc].border : '#3b82f6'))),
                    borderRadius: 6
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false }, tooltip: { ...commonOptions.plugins.tooltip } },
                scales: {
                    x: { ticks: { color: '#cbd5e1', font: { size: 10 } }, grid: { display: false } },
                    y: { ticks: { color: '#64748b', font: { size: 10 }, callback: v => v + ' GB' }, grid: { color: 'rgba(51, 65, 85, 0.35)' } }
                }
            }
        });

        // 6. DISK IO CHART
        charts.io = new Chart(document.getElementById('ioChart'), {
            type: 'line',
            data: { labels: initialLabels, datasets: createDatasetList('ioW') },
            options: {
                ...commonOptions,
                scales: {
                    ...commonOptions.scales,
                    y: { ...commonOptions.scales.y, min: 0, ticks: { ...commonOptions.scales.y.ticks, callback: v => v + ' KB/s' } }
                }
            }
        });

        // 7. PING LATENCY CHART
        charts.ping = new Chart(document.getElementById('pingChart'), {
            type: 'line',
            data: { labels: initialLabels, datasets: createDatasetList('ping') },
            options: {
                ...commonOptions,
                scales: {
                    ...commonOptions.scales,
                    y: { ...commonOptions.scales.y, min: 0, ticks: { ...commonOptions.scales.y.ticks, callback: v => v + ' ms' } }
                }
            }
        });

        // 8. TEMPERATURA DOS EQUIPAMENTOS CHART
        charts.temp = new Chart(document.getElementById('tempChart'), {
            type: 'line',
            data: { labels: initialLabels, datasets: createDatasetList('temp') },
            options: {
                ...commonOptions,
                scales: {
                    ...commonOptions.scales,
                    y: { ...commonOptions.scales.y, min: 20, max: 110, ticks: { ...commonOptions.scales.y.ticks, callback: v => v + ' °C' } }
                }
            }
        });

        // 9. PERFORMANCE DE REDE / INTERNET CHART
        charts.internet = new Chart(document.getElementById('internetChart'), {
            type: 'line',
            data: { labels: initialLabels, datasets: createDatasetList('internet') },
            options: {
                ...commonOptions,
                scales: {
                    ...commonOptions.scales,
                    y: { ...commonOptions.scales.y, min: 0, ticks: { ...commonOptions.scales.y.ticks, callback: v => v + ' Mbps' } }
                }
            }
        });

        function setWindowMode(size) {
            currentWindowSize = String(size);
            localStorage.setItem('monitorWindowSize', currentWindowSize);
            updateButtonStyles();
            refreshChartsWindow('none');
        }

        function updateButtonStyles() {
            ['60', '120', '300', 'all'].forEach(s => {
                const btn = document.getElementById('btnWin_' + s);
                if (!btn) return;
                if (String(currentWindowSize) === s) {
                    btn.className = 'text-[11px] px-2.5 py-0.5 rounded font-bold bg-cyan-500/20 text-cyan-300 border border-cyan-500/40 transition shadow-sm cursor-pointer';
                } else {
                    btn.className = 'text-[11px] px-2.5 py-0.5 rounded text-slate-400 hover:text-slate-200 transition cursor-pointer';
                }
            });
        }
        updateButtonStyles();

        function refreshChartsWindow(updateMode) {
            const finalLabels = alignDataTaskmanager(timestamps, timestamps, currentWindowSize).labels;
            const mode = updateMode !== undefined ? updateMode : 'none';
            ['cpu', 'ram', 'rx', 'tx', 'io', 'ping', 'temp', 'internet'].forEach(k => {
                if (!charts[k]) return;
                charts[k].data.labels = finalLabels;
                charts[k].data.datasets.forEach(ds => {
                    const isH = (highlightedMachine === ds.pcKey);
                    const origCol = colors[ds.pcKey] ? colors[ds.pcKey].border : '#38bdf8';
                    ds.borderColor = isH ? '#ffffff' : origCol;
                    ds.borderWidth = isH ? 3.5 : 2;
                    ds.pointBackgroundColor = isH ? '#ffffff' : origCol;
                    ds.pointRadius = 0;
                    ds.pointHoverRadius = 0;
                    ds.order = isH ? -1 : 1;
                    ds.data = getAlignedDataset(ds.pcKey, ds.metricKey);
                    ds.hidden = !isMachineVisible(ds.pcKey);
                    ds.spanGaps = true;
                });
                charts[k].update(mode);
            });
            if (charts.disk) {
                const visiblePcs = pcsList.filter(pc => isMachineVisible(pc));
                charts.disk.data.labels = visiblePcs;
                charts.disk.data.datasets[0].data = visiblePcs.map(pc => getLatestDiskFree(pc));
                charts.disk.data.datasets[0].backgroundColor = visiblePcs.map(pc => (highlightedMachine === pc ? '#ffffff' : (colors[pc] ? colors[pc].border : '#3b82f6')));
                charts.disk.update(mode);
            }
        }

        // Aplica o estado visual inicial aos cards
        pcsList.forEach(pc => updateCardVisualState(pc));

        // MODAL ESTATÍSTICO CONSOLIDADO
        function toggleSummaryModal(show) {
            const modal = document.getElementById('summaryModal');
            if (!modal) return;
            if (show) modal.classList.remove('hidden');
            else modal.classList.add('hidden');
        }

        // MODAL TOP 10 PROCESSOS
        let currentModalPc = null;

        function openProcessModal(pc) {
            currentModalPc = pc;
            const modal = document.getElementById('processModal');
            const title = document.getElementById('procModalTitle');
            const dot = document.getElementById('procModalDot');

            if (title) {
                title.innerHTML = '&#9889; Top 10 Processos &mdash; <span class="font-mono text-cyan-300">' + pc + '</span>';
            }
            if (dot) {
                const col = colors[pc] ? colors[pc].border : '#38bdf8';
                dot.style.backgroundColor = col;
            }

            updateModalVisButton(pc);
            renderProcessModalBody(pc);

            if (modal) modal.classList.remove('hidden');
        }

        function closeProcessModal() {
            const modal = document.getElementById('processModal');
            if (modal) modal.classList.add('hidden');
            currentModalPc = null;
        }

        function updateModalVisButton(pc) {
            const btn = document.getElementById('procModalToggleVisBtn');
            if (!btn) return;
            const isVis = isMachineVisible(pc);
            if (isVis) {
                btn.innerHTML = '&#128065; Exibir gr&aacute;ficos &#10003;';
                btn.className = 'text-[10px] px-2.5 py-1 rounded bg-emerald-500/25 hover:bg-emerald-500/35 text-emerald-300 border border-emerald-500/50 font-bold transition cursor-pointer flex items-center gap-1 shadow-sm';
                btn.title = 'Máquina visível nos gráficos. Clique para ocultar.';
            } else {
                btn.innerHTML = '&#128065; Oculto nos gr&aacute;ficos';
                btn.className = 'text-[10px] px-2.5 py-1 rounded bg-slate-800 hover:bg-slate-700 text-slate-400 border border-slate-700 font-medium transition cursor-pointer flex items-center gap-1';
                btn.title = 'Máquina oculta nos gráficos. Clique para exibir.';
            }
        }

        function toggleVisibilityFromModal() {
            if (!currentModalPc) return;
            toggleMachineVisibility(currentModalPc);
            updateModalVisButton(currentModalPc);
        }

        function renderProcessModalBody(pc) {
            const tbody = document.getElementById('procModalTableBody');
            const emptyEl = document.getElementById('procModalEmpty');
            const totalCpuEl = document.getElementById('procTotalCpu');
            const totalRamEl = document.getElementById('procTotalRam');
            if (!tbody) return;

            tbody.innerHTML = '';
            const procList = (dashboardTopProcesses && dashboardTopProcesses[pc]) ? dashboardTopProcesses[pc] : [];

            if (!procList || procList.length === 0) {
                if (emptyEl) emptyEl.classList.remove('hidden');
                if (totalCpuEl) totalCpuEl.innerText = '0%';
                if (totalRamEl) totalRamEl.innerText = '0 MB';
                return;
            }

            if (emptyEl) emptyEl.classList.add('hidden');

            let sumCpu = 0;
            let sumRam = 0;

            procList.slice(0, 10).forEach(function(proc, idx) {
                let cpuVal = Number(proc.Cpu !== undefined ? proc.Cpu : (proc.PercentProcessorTime || 0));
                if (cpuVal > 100) cpuVal = 100;
                const ramVal = Number(proc.MemMB !== undefined ? proc.MemMB : (proc.WorkingSetPrivateMB || 0));
                const pidVal = proc.Pid !== undefined ? proc.Pid : (proc.IDProcess !== undefined ? proc.IDProcess : '-');
                sumCpu += cpuVal;
                sumRam += ramVal;

                const cpuBarWidth = Math.min(100, Math.round(cpuVal));
                const ramText = ramVal >= 1024 
                    ? (ramVal / 1024).toFixed(2) + ' GB' 
                    : ramVal.toFixed(1) + ' MB';

                const tr = document.createElement('tr');
                tr.className = 'hover:bg-slate-800/60 transition';
                
                const tdIdx = '<td class="py-2 px-2.5 text-center text-slate-500 font-semibold">' + (idx + 1) + '</td>';
                const tdName = '<td class="py-2 px-3 text-white font-medium truncate max-w-[210px]" title="' + (proc.Name || '') + '"><span class="text-cyan-300 font-mono text-[11px] truncate block">' + (proc.Name || 'Desconhecido') + '</span></td>';
                const tdPid = '<td class="py-2 px-2 text-right text-slate-400 font-mono">' + pidVal + '</td>';
                
                const cpuColorClass = cpuVal > 25 ? 'text-amber-400 font-bold' : (cpuVal > 5 ? 'text-amber-300' : 'text-slate-300');
                const tdCpu = '<td class="py-2 px-3 text-right"><div class="flex items-center justify-end gap-1.5"><div class="w-14 bg-slate-800 rounded-full h-1.5 overflow-hidden border border-slate-700/50"><div class="bg-amber-400 h-1.5 rounded-full" style="width: ' + cpuBarWidth + '%"></div></div><span class="' + cpuColorClass + '">' + cpuVal.toFixed(1) + '%</span></div></td>';
                
                const ramColorClass = ramVal > 1024 ? 'text-indigo-400 font-bold' : 'text-slate-300';
                const tdRam = '<td class="py-2 px-3 text-right"><span class="' + ramColorClass + '">' + ramText + '</span></td>';

                tr.innerHTML = tdIdx + tdName + tdPid + tdCpu + tdRam;
                tbody.appendChild(tr);
            });

            if (totalCpuEl) totalCpuEl.innerText = Math.min(100, sumCpu).toFixed(1) + '%';
            if (totalRamEl) {
                totalRamEl.innerText = sumRam >= 1024 
                    ? (sumRam / 1024).toFixed(2) + ' GB' 
                    : sumRam.toFixed(1) + ' MB';
            }
        }

        // GERENCIAMENTO DE MÁQUINAS (MODAL)
        function toggleMachinesModal(show) {
            const modal = document.getElementById('machinesModal');
            if (!modal) return;
            if (show) {
                renderMachinesList();
                modal.classList.remove('hidden');
            } else {
                modal.classList.add('hidden');
            }
        }

        function renderMachinesList() {
            const container = document.getElementById('machinesListContainer');
            if (!container) return;
            container.innerHTML = '';
            pcsList.forEach((pc, idx) => {
                const item = document.createElement('div');
                item.className = 'flex items-center justify-between py-1.5 px-2 hover:bg-slate-800/40 rounded';
                const col = colors[pc] ? colors[pc].border : '#38bdf8';
                item.innerHTML = '<div class="flex items-center gap-2">' +
                    '<span class="h-2 w-2 rounded-full" style="background-color: ' + col + '"></span>' +
                    '<span class="font-mono text-white text-xs font-semibold">' + pc + '</span>' +
                    '</div>' +
                    '<div class="flex items-center gap-1.5">' +
                    '<button onclick="editMachineName(\'' + pc + '\')" class="text-[10px] px-2 py-0.5 rounded bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 cursor-pointer">Editar</button>' +
                    '<button onclick="removeMachine(\'' + pc + '\')" class="text-[10px] px-2 py-0.5 rounded bg-rose-500/20 hover:bg-rose-500/30 text-rose-300 border border-rose-500/40 cursor-pointer">&times; Remover</button>' +
                    '</div>';
                container.appendChild(item);
            });
        }

        function addNewMachine() {
            const input = document.getElementById('newMachineInput');
            if (!input || !input.value.trim()) return;
            const name = input.value.trim().toUpperCase();
            if (!pcsList.includes(name)) {
                pcsList.push(name);
                pcsList.sort();
                renderMachinesList();
                input.value = '';
                saveMachinesConfig();
            } else {
                alert('O nó ' + name + ' já está cadastrado.');
            }
        }

        function editMachineName(oldName) {
            const newName = prompt('Informe o novo nome para o computador:', oldName);
            if (newName && newName.trim()) {
                const clean = newName.trim().toUpperCase();
                const idx = pcsList.indexOf(oldName);
                if (idx >= 0) {
                    pcsList[idx] = clean;
                    pcsList.sort();
                    renderMachinesList();
                    saveMachinesConfig();
                }
            }
        }

        function removeMachine(pc) {
            if (confirm('Deseja realmente remover ' + pc + ' da lista de monitoramento?')) {
                pcsList = pcsList.filter(x => x !== pc);
                renderMachinesList();
                saveMachinesConfig();
            }
        }

        function scanNetworkNodes() {
            const btn = document.getElementById('btnScanNet');
            const resultBox = document.getElementById('scanResultBox');
            const resultList = document.getElementById('scanResultList');
            if (btn) btn.innerText = 'Escaneando...';
            setTimeout(() => {
                if (btn) btn.innerHTML = '&#128269; Descobrir N&oacute;s na Rede';
                if (resultBox && resultList) {
                    resultList.innerHTML = '';
                    const candidates = ['JFMELGACO-1', 'JFMELGACO-2', 'JFMELGACO-3', 'JFMELGACO-4', 'JFMELGACO-5'];
                    candidates.forEach(c => {
                        const btnC = document.createElement('button');
                        const isAdded = pcsList.includes(c);
                        btnC.className = isAdded 
                            ? 'text-[10px] px-2 py-0.5 rounded bg-emerald-500/20 text-emerald-300 border border-emerald-500/40' 
                            : 'text-[10px] px-2 py-0.5 rounded bg-cyan-600/30 hover:bg-cyan-600 text-cyan-200 border border-cyan-500/50 cursor-pointer';
                        btnC.innerText = c + (isAdded ? ' (Ativo)' : ' (+ Adicionar)');
                        if (!isAdded) {
                            btnC.onclick = function() {
                                pcsList.push(c);
                                pcsList.sort();
                                renderMachinesList();
                                scanNetworkNodes();
                                saveMachinesConfig();
                            };
                        }
                        resultList.appendChild(btnC);
                    });
                    resultBox.classList.remove('hidden');
                }
            }, 600);
        }

        function saveMachinesConfig() {
            try {
                localStorage.setItem('monitorMachinesList', JSON.stringify(pcsList));
            } catch(e) {}
        }

        window.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') {
                toggleSummaryModal(false);
                closeProcessModal();
                toggleMachinesModal(false);
            }
        });

        document.getElementById('summaryModal')?.addEventListener('click', (e) => {
            if (e.target.id === 'summaryModal') toggleSummaryModal(false);
        });

        document.getElementById('processModal')?.addEventListener('click', (e) => {
            if (e.target.id === 'processModal') closeProcessModal();
        });

        document.getElementById('machinesModal')?.addEventListener('click', (e) => {
            if (e.target.id === 'machinesModal') toggleMachinesModal(false);
        });

        // MODO TELA ÚNICA VS ROLAGEM
        let isSingleScreen = localStorage.getItem('monitorSingleScreen') !== 'false';
        let currentSlot6Mode = localStorage.getItem('monitorSlot6Mode') || 'temp';

        function toggleSlot6Chart(mode) {
            currentSlot6Mode = mode;
            localStorage.setItem('monitorSlot6Mode', mode);
            applyScreenMode();
        }

        function applyScreenMode() {
            const body = document.getElementById('mainBody');
            const btn = document.getElementById('btnScrollMode');
            const chartsMain = document.getElementById('chartsMain');
            const dashboardContent = document.getElementById('dashboardContent');

            const cardCpu = document.getElementById('card-chart-cpu');
            const cardRam = document.getElementById('card-chart-ram');
            const cardRx = document.getElementById('card-chart-rx');
            const cardTx = document.getElementById('card-chart-tx');
            const cardPing = document.getElementById('card-chart-ping');
            const cardTemp = document.getElementById('card-chart-temp');
            const cardInternet = document.getElementById('card-chart-internet');
            const cardDisk = document.getElementById('card-chart-disk');
            const cardIo = document.getElementById('card-chart-io');

            const allChartCards = document.querySelectorAll('.chart-card');

            if (isSingleScreen) {
                body.className = "bg-darkbg text-slate-100 h-screen max-h-screen flex flex-col p-2.5 overflow-hidden text-xs font-sans";
                if (dashboardContent) {
                    dashboardContent.className = "flex-1 flex flex-col lg:flex-row gap-2.5 min-h-0 my-1 overflow-hidden";
                }
                if (chartsMain) {
                    chartsMain.className = "flex-1 grid grid-cols-1 lg:grid-cols-2 lg:grid-rows-3 gap-2 h-full min-h-0 overflow-hidden pr-0.5";
                }
                // Cards 1 a 5 sempre visíveis
                [cardCpu, cardRam, cardRx, cardTx, cardPing].forEach(el => {
                    if (el) el.classList.remove('hidden');
                });
                // Slot 6: alterna entre Temperatura e Internet
                if (currentSlot6Mode === 'internet') {
                    if (cardTemp) cardTemp.classList.add('hidden');
                    if (cardInternet) cardInternet.classList.remove('hidden');
                } else {
                    if (cardTemp) cardTemp.classList.remove('hidden');
                    if (cardInternet) cardInternet.classList.add('hidden');
                }
                // Cards de disco ocultos na tela única para manter estritamente 6 gráficos
                if (cardDisk) cardDisk.classList.add('hidden');
                if (cardIo) cardIo.classList.add('hidden');

                // Atualiza botões de alternância do slot 6
                const btnTemp = document.getElementById('btnSlot6Temp');
                const btnNet = document.getElementById('btnSlot6Net');
                if (btnTemp && btnNet) {
                    if (currentSlot6Mode === 'internet') {
                        btnTemp.className = 'text-[10px] px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 hover:text-white border border-slate-700 transition cursor-pointer';
                        btnNet.className = 'text-[10px] px-1.5 py-0.5 rounded bg-blue-500/30 text-blue-300 font-bold border border-blue-500/50 transition cursor-pointer';
                    } else {
                        btnTemp.className = 'text-[10px] px-1.5 py-0.5 rounded bg-rose-500/30 text-rose-300 font-bold border border-rose-500/50 transition cursor-pointer';
                        btnNet.className = 'text-[10px] px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 hover:text-white border border-slate-700 transition cursor-pointer';
                    }
                }

                allChartCards.forEach(c => {
                    c.classList.remove('h-[220px]', 'min-h-[200px]', 'shrink-0');
                    c.classList.add('h-full', 'min-h-0');
                });

                if (btn) {
                    btn.innerHTML = '&#128421;&#xFE0F; Tela &Uacute;nica (6 Gr&aacute;ficos)';
                    btn.className = 'text-[11px] px-2.5 py-1 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 cursor-pointer transition';
                }
            } else {
                body.className = "bg-darkbg text-slate-100 min-h-screen p-3 overflow-y-auto text-xs font-sans";
                if (dashboardContent) {
                    dashboardContent.className = "flex flex-col lg:flex-row gap-3 pb-8";
                }
                if (chartsMain) {
                    chartsMain.className = "flex-1 flex flex-col gap-2.5 overflow-y-auto pr-1";
                }
                // Na rolagem, todos os 9 gráficos ficam visíveis
                [cardCpu, cardRam, cardRx, cardTx, cardPing, cardTemp, cardInternet, cardDisk, cardIo].forEach(el => {
                    if (el) el.classList.remove('hidden');
                });
                allChartCards.forEach(c => {
                    c.classList.remove('h-full', 'min-h-0');
                    c.classList.add('h-[220px]', 'min-h-[200px]', 'shrink-0');
                });

                if (btn) {
                    btn.innerHTML = '&#128220; Modo Rolagem (9 Gr&aacute;ficos)';
                    btn.className = 'text-[11px] px-2.5 py-1 rounded-lg bg-indigo-500/25 hover:bg-indigo-500/35 text-indigo-300 border border-indigo-500/50 font-semibold cursor-pointer transition shadow-sm';
                }
            }
            setTimeout(() => {
                Object.keys(charts).forEach(k => { if (charts[k]) charts[k].resize(); });
            }, 100);
        }

        function toggleScrollMode() {
            isSingleScreen = !isSingleScreen;
            localStorage.setItem('monitorSingleScreen', isSingleScreen);
            applyScreenMode();
        }
        applyScreenMode();

        // ATUALIZACAO CONTINUA EM SEGUNDO PLANO
        window.updateDashboardData = function(payload) {
            if (!payload || !payload.timestamps || !payload.rawData) return;

            timestamps = payload.timestamps;
            rawData = payload.rawData;
            if (payload.stats) { stats = payload.stats; window.stats = payload.stats; }

            const timeRangeEl = document.getElementById('headerTimeRange');
            if (timeRangeEl && payload.startTime && payload.endTime) {
                timeRangeEl.innerHTML = payload.startTime + ' &rarr; ' + payload.endTime;
            }
            const sampleCountEl = document.getElementById('headerSampleCount');
            if (sampleCountEl && payload.totalPoints) {
                sampleCountEl.innerText = payload.totalPoints + ' amostras';
            }

            pcsList.forEach(pc => {
                let s = (payload.stats && payload.stats[pc]) ? payload.stats[pc] : (payload.rawData[pc] ? payload.rawData[pc].stats : null);
                if (!s && payload.rawData && payload.rawData[pc]) {
                    const d = payload.rawData[pc];
                    const validCpu = (d.cpu || []).filter(v => v !== null);
                    const validRam = (d.ramPct || []).filter(v => v !== null);
                    const recentTemps = (d.temp || []).slice(-3).filter(v => v !== null && v > 0);
                    const isOnline = Boolean(d.cpu && d.cpu.length > 0 && d.cpu[d.cpu.length - 1] !== null);
                    s = {
                        isOnline: isOnline,
                        latestCpu: isOnline ? d.cpu[d.cpu.length - 1] : 0,
                        latestRam: isOnline ? d.ramPct[d.ramPct.length - 1] : 0,
                        latestTemp: (isOnline && recentTemps.length > 0) ? recentTemps[recentTemps.length - 1] : null,
                        latestTx: isOnline && (d.tx && d.tx.length > 0) ? d.tx[d.tx.length - 1] : 0,
                        latestIoW: isOnline && (d.ioW && d.ioW.length > 0) ? d.ioW[d.ioW.length - 1] : 0,
                        diskFree: isOnline && (d.diskFree && d.diskFree.length > 0) ? d.diskFree[d.diskFree.length - 1] : 0,
                        ping: isOnline && (d.ping && d.ping.length > 0) ? d.ping[d.ping.length - 1] : 0,
                        uptime: isOnline && (d.uptime && d.uptime.length > 0) ? d.uptime[d.uptime.length - 1] : '---',
                        avgCpu: validCpu.length > 0 ? Math.round(validCpu.reduce((a,b)=>a+b,0)/validCpu.length) : 0,
                        avgRam: validRam.length > 0 ? Math.round(validRam.reduce((a,b)=>a+b,0)/validRam.length) : 0
                    };
                }
                if (!s) return;

                const sDot = document.getElementById('cardStatusDot_' + pc);
                const sText = document.getElementById('cardStatusText_' + pc);
                const cardHost = document.getElementById('cardHost_' + pc);
                const alertBadge = document.getElementById('cardAlertBadge_' + pc);
                const bCpu = document.getElementById('box_' + pc + '_cpu');
                const bRam = document.getElementById('box_' + pc + '_ram');
                const bDisk = document.getElementById('box_' + pc + '_disk');

                const cCpu = document.getElementById('card_' + pc + '_cpu');
                const cRam = document.getElementById('card_' + pc + '_ram');
                const cDisk = document.getElementById('card_' + pc + '_disk');
                const cIo = document.getElementById('card_' + pc + '_io');
                const cTx = document.getElementById('card_' + pc + '_tx');
                const cPing = document.getElementById('card_' + pc + '_ping');
                const cUptime = document.getElementById('card_' + pc + '_uptime');

                if (sDot && sText) {
                    if (s.isOnline) {
                        sDot.className = 'h-2 w-2 rounded-full bg-emerald-400 shadow-[0_0_6px_rgba(52,211,153,0.8)]';
                        sText.className = 'text-emerald-400 font-medium';
                        sText.innerText = 'Online';
                        if (cardHost) cardHost.classList.remove('card-offline-blink', 'opacity-60');
                    } else {
                        sDot.className = 'h-2 w-2 rounded-full bg-red-500 shadow-[0_0_8px_rgba(239,68,68,0.9)]';
                        sText.className = 'text-red-400 font-bold';
                        sText.innerText = 'Offline';
                        if (cardHost) {
                            cardHost.classList.remove('card-alert-pulse');
                            cardHost.classList.add('card-offline-blink', 'opacity-60');
                        }
                        if (alertBadge) alertBadge.classList.add('hidden');
                    }
                }

                if (s.isOnline) {
                    const isCpuAlert = (s.latestCpu >= 85 || s.avgCpu >= 85);
                    const isRamAlert = (s.latestRam >= 90 || s.avgRam >= 90);
                    const isDiskAlert = ((s.diskPct && s.diskPct >= 90) || (s.diskFree > 0 && s.diskFree <= 15));
                    const isTempAlert = (s.latestTemp && s.latestTemp >= 75);
                    const hasAlert = (isCpuAlert || isRamAlert || isDiskAlert || isTempAlert);

                    const alertReasons = [];
                    if (isCpuAlert) alertReasons.push('CPU: ' + s.latestCpu + '% (>=85%)');
                    if (isRamAlert) alertReasons.push('RAM: ' + s.latestRam + '% (>=90%)');
                    if (isDiskAlert) alertReasons.push('Disco C: ' + s.diskFree + 'GB livres (<=15GB ou >=90%)');
                    if (isTempAlert) alertReasons.push('Temp: ' + s.latestTemp + '°C (>=75°C)');

                    if (cardHost) {
                        if (hasAlert) cardHost.classList.add('card-alert-pulse');
                        else cardHost.classList.remove('card-alert-pulse');
                    }

                    if (alertBadge) {
                        if (hasAlert) {
                            alertBadge.classList.remove('hidden');
                            alertBadge.title = 'Alerta: ' + alertReasons.join(' | ');
                        } else {
                            alertBadge.classList.add('hidden');
                        }
                    }

                    if (bCpu) {
                        bCpu.className = isCpuAlert 
                            ? 'border rounded px-1 py-1 bg-amber-500/20 border-amber-500/80 ring-1 ring-amber-500/40' 
                            : 'border rounded px-1 py-1 bg-slate-900/80 border-slate-800';
                        if (cCpu) cCpu.className = isCpuAlert ? 'text-xs text-amber-300 font-bold' : 'text-xs text-white';
                    }
                    if (bRam) {
                        bRam.className = isRamAlert 
                            ? 'border rounded px-1 py-1 bg-red-500/20 border-red-500/80 ring-1 ring-red-500/40' 
                            : 'border rounded px-1 py-1 bg-slate-900/80 border-slate-800';
                        if (cRam) cRam.className = isRamAlert ? 'text-xs text-red-300 font-bold' : 'text-xs text-white';
                    }
                    if (bDisk) {
                        bDisk.className = isDiskAlert 
                            ? 'border rounded px-1 py-1 bg-amber-500/20 border-amber-500/80 ring-1 ring-amber-500/40' 
                            : 'border rounded px-1 py-1 bg-slate-900/80 border-slate-800';
                        if (cDisk) cDisk.className = isDiskAlert ? 'text-xs text-amber-300 font-bold' : 'text-xs text-emerald-400';
                    }

                    const bIo = document.getElementById('box_' + pc + '_io');
                    if (bIo) bIo.className = 'rounded px-1 py-1 bg-slate-900/80 border border-slate-800';
                    if (cIo) cIo.className = 'text-xs text-amber-400';

                    const bTx = document.getElementById('box_' + pc + '_tx');
                    if (bTx) bTx.className = 'rounded px-1 py-1 bg-slate-900/80 border border-slate-800';
                    if (cTx) cTx.className = 'text-xs text-cyan-400';

                    if (cCpu) cCpu.innerText = s.latestCpu + '%';
                    if (cRam) cRam.innerText = s.latestRam + '%';
                    if (cDisk) cDisk.innerText = s.diskFree + 'G';
                    if (cIo) cIo.innerText = s.latestIoW + 'k';
                    if (cTx) cTx.innerText = s.latestTx + 'k';
                    if (cPing) cPing.innerText = (s.ping !== null ? s.ping : '---') + 'ms';
                    if (cUptime && s.uptime) cUptime.innerHTML = '&#9201; ' + s.uptime;
                    const cTemp = document.getElementById('card_' + pc + '_temp');
                    if (cTemp) cTemp.innerHTML = (s.latestTemp && s.latestTemp > 0) ? '&#127777;&#xFE0F; ' + s.latestTemp + '&deg;C' : '&#127777;&#xFE0F; ---';
                } else {
                    // Estado OFFLINE
                    if (cardHost) cardHost.classList.add('opacity-60');
                    if (bCpu) {
                        bCpu.className = 'border rounded px-1 py-1 bg-slate-900/40 border-slate-800/60 opacity-60';
                        if (cCpu) { cCpu.className = 'text-xs text-slate-500'; cCpu.innerText = '---'; }
                    }
                    if (bRam) {
                        bRam.className = 'border rounded px-1 py-1 bg-slate-900/40 border-slate-800/60 opacity-60';
                        if (cRam) { cRam.className = 'text-xs text-slate-500'; cRam.innerText = '---'; }
                    }
                    if (bDisk) {
                        bDisk.className = 'border rounded px-1 py-1 bg-slate-900/40 border-slate-800/60 opacity-60';
                        if (cDisk) { cDisk.className = 'text-xs text-slate-500'; cDisk.innerText = '---'; }
                    }
                    const bIo = document.getElementById('box_' + pc + '_io');
                    if (bIo) bIo.className = 'rounded px-1 py-1 bg-slate-900/40 border border-slate-800/60 opacity-60';
                    if (cIo) { cIo.className = 'text-xs text-slate-500'; cIo.innerText = '---'; }

                    const bTx = document.getElementById('box_' + pc + '_tx');
                    if (bTx) bTx.className = 'rounded px-1 py-1 bg-slate-900/40 border border-slate-800/60 opacity-60';
                    if (cTx) { cTx.className = 'text-xs text-slate-500'; cTx.innerText = '---'; }

                    if (cPing) cPing.innerText = '---';
                    if (cUptime) cUptime.innerHTML = '&#9201; ---';
                    const cTemp = document.getElementById('card_' + pc + '_temp');
                    if (cTemp) cTemp.innerHTML = '&#127777;&#xFE0F; ---';
                }

                // Tabela Resumo
                const mCpuAvg = document.getElementById('modal_' + pc + '_cpuAvg');
                if (mCpuAvg) mCpuAvg.innerText = s.avgCpu + '%';
                const mCpuMax = document.getElementById('modal_' + pc + '_cpuMax');
                if (mCpuMax) mCpuMax.innerText = s.maxCpu + '%';
                const mRamAvg = document.getElementById('modal_' + pc + '_ramAvg');
                if (mRamAvg) mRamAvg.innerText = s.avgRam + '%';
                const mRamMax = document.getElementById('modal_' + pc + '_ramMax');
                if (mRamMax) mRamMax.innerText = s.maxRam + '%';
                const mIo = document.getElementById('modal_' + pc + '_io');
                if (mIo) mIo.innerText = s.maxIoR + ' / ' + s.maxIoW + ' KB/s';
                const mRx = document.getElementById('modal_' + pc + '_rx');
                if (mRx) mRx.innerText = s.maxRx + ' KB/s';
                const mTx = document.getElementById('modal_' + pc + '_tx');
                if (mTx) mTx.innerText = s.maxTx + ' KB/s';
                const mDisk = document.getElementById('modal_' + pc + '_disk');
                if (mDisk) mDisk.innerText = s.isOnline ? s.diskFree + ' GB' : '---';
                const mPing = document.getElementById('modal_' + pc + '_ping');
                if (mPing) mPing.innerHTML = s.isOnline ? s.ping + ' ms <span class="text-[10px] text-slate-400 font-normal">(méd ' + s.avgPing + 'ms)</span>' : '---';
                const mUptime = document.getElementById('modal_' + pc + '_uptime');
                if (mUptime) mUptime.innerHTML = (s.isOnline && s.uptime) ? '&#9201; ' + s.uptime : '---';
            });

            if (payload.topProcesses) {
                dashboardTopProcesses = payload.topProcesses;
                if (currentModalPc) renderProcessModalBody(currentModalPc);
            }

            refreshChartsWindow('none');

            const dot = document.getElementById('livePulseDot');
            if (dot) {
                dot.classList.remove('bg-emerald-500');
                dot.classList.add('bg-cyan-400');
                setTimeout(() => {
                    dot.classList.remove('bg-cyan-400');
                    dot.classList.add('bg-emerald-500');
                }, 300);
            }
        };

        function requestDataUpdate() {
            if (window.location.protocol.startsWith('http')) {
                fetch('dashboard_data.js?t=' + Date.now())
                    .then(res => {
                        if (!res.ok) throw new Error('HTTP ' + res.status);
                        return res.text();
                    })
                    .then(code => { eval(code); })
                    .catch(() => { loadViaScriptTag(); });
            } else {
                loadViaScriptTag();
            }
        }

        function loadViaScriptTag() {
            const old = document.getElementById('dynamicDataScript');
            if (old) old.remove();
            const s = document.createElement('script');
            s.id = 'dynamicDataScript';
            s.src = 'dashboard_data.js?t=' + Date.now();
            document.head.appendChild(s);
        }

        // AUTO-REFRESH CONTROLLER CONFIGURÁVEL (MÍNIMO 1s)
        let refreshInterval = parseInt(localStorage.getItem('monitorRefreshInterval') || '5');
        if (isNaN(refreshInterval) || refreshInterval < 1) refreshInterval = 5;
        let refreshTimer = refreshInterval;
        let autoRefreshActive = true;

        const initLbl = document.getElementById('intervalSecLabel');
        if (initLbl) initLbl.innerText = refreshInterval + 's';

        function promptChangeInterval() {
            const input = prompt("Defina o período de atualização automática em segundos (mínimo 1):", refreshInterval);
            if (input !== null) {
                const val = parseInt(input);
                if (!isNaN(val) && val >= 1) {
                    refreshInterval = val;
                    refreshTimer = val;
                    localStorage.setItem('monitorRefreshInterval', val.toString());
                    const lbl = document.getElementById('intervalSecLabel');
                    if (lbl) lbl.innerText = val + 's';
                    const el = document.getElementById('countdownEl');
                    if (el) el.innerText = val + 's';
                } else {
                    alert("Por favor, informe um valor inteiro maior ou igual a 1 segundo.");
                }
            }
        }

        function toggleAutoRefresh() {
            autoRefreshActive = !autoRefreshActive;
            const btn = document.getElementById('pauseBtn');
            if (btn) {
                btn.innerHTML = autoRefreshActive ? '&#9208;' : '&#9654;';
                btn.className = autoRefreshActive 
                    ? 'ml-0.5 text-[10px] px-1.5 py-0.5 rounded bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 transition cursor-pointer'
                    : 'ml-0.5 text-[10px] px-1.5 py-0.5 rounded bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 border border-amber-500/40 transition cursor-pointer font-bold';
            }
        }

        setInterval(() => {
            if (autoRefreshActive) {
                refreshTimer--;
                const el = document.getElementById('countdownEl');
                if (el) el.innerText = refreshTimer + 's';
                if (refreshTimer <= 0) {
                    refreshTimer = refreshInterval;
                    requestDataUpdate();
                }
            }
        }, 1000);
    </script>
</body>
</html>
"@

$dataJsContent = @"
window.updateDashboardData({
    startTime: "$startTime",
    endTime: "$endTime",
    totalPoints: $totalPoints,
    timestamps: $jsonTimestamps,
    rawData: $jsonData,
    stats: $jsonStats,
    topProcesses: $topProcessesJson
});
"@

$outputDir = Split-Path -Parent $OutputFile
if (-not $outputDir) { $outputDir = $PSScriptRoot }
$dataJsFile = Join-Path $outputDir "dashboard_data.js"

$utf8Bom = [System.Text.UTF8Encoding]::new($true)
[System.IO.File]::WriteAllText($OutputFile, $html, $utf8Bom)
[System.IO.File]::WriteAllText($dataJsFile, $dataJsContent, $utf8Bom)
Write-Host "Dashboard HTML gerado com sucesso em: $OutputFile" -ForegroundColor Green
Write-Host "Arquivo de dados JS gerado com sucesso em: $dataJsFile" -ForegroundColor Green

# Sincronização central: No modelo atual o coletor roda diretamente no servidor JFMELGACO-2,
# onde os arquivos são gravados nativamente no diretório de compartilhamento local.
