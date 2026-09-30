# ============================================================
# GERADOR DE DASHBOARD HTML - JFMELGACO (v1.1.0)
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

$pattern = '^(?:ONLINE|OFFLINE|SEM ACESSO)\s+(?<pc>JFMELGACO[^\s\(]+)(?:\s+\(Local\))?(?:\s+\[[^\]]+\]\s+(?<cpu>\d+)%\s+\[[^\]]+\]\s+(?<ramUsed>[\d\.,]+)\s*\/\s*(?<ramTotal>[\d\.,]+)\s*GB\s*\((?<ramPct>\d+)%\)\s+(?<diskFree>[\d\.,]+)\s*GB\s*liv\s*\(\s*(?<diskPct>\d+)%\s*us\)\s+(?:R:\s*(?<ioRVal>[\d\.,]+|N\/D)(?:\s*(?<ioRUnit>KB\/s|MB\/s))?\s*\|\s*W:\s*(?<ioWVal>[\d\.,]+|N\/D)(?:\s*(?<ioWUnit>KB\/s|MB\/s))?\s+)?Rx:\s*(?<rxVal>[\d\.,]+|N\/D)(?:\s*(?<rxUnit>KB\/s|MB\/s))?\s*\|\s*Tx:\s*(?<txVal>[\d\.,]+|N\/D)(?:\s*(?<txUnit>KB\/s|MB\/s))?)?.*?(?:Ping:\s*(?<ping>\d+|---|N\/D)\s*ms)?$'

$timestamps = [System.Collections.Generic.List[string]]::new()
$pcsList = @('JFMELGACO-4', 'JFMELGACO-1', 'JFMELGACO-2', 'JFMELGACO-3')

$machineData = @{}
foreach ($pc in $pcsList) {
    $machineData[$pc] = @{
        cpu      = [System.Collections.Generic.List[object]]::new()
        ramPct   = [System.Collections.Generic.List[object]]::new()
        ramUsed  = [System.Collections.Generic.List[object]]::new()
        diskFree = [System.Collections.Generic.List[object]]::new()
        ioR      = [System.Collections.Generic.List[object]]::new()
        ioW      = [System.Collections.Generic.List[object]]::new()
        rx       = [System.Collections.Generic.List[object]]::new()
        tx       = [System.Collections.Generic.List[object]]::new()
        ping     = [System.Collections.Generic.List[object]]::new()
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
                $machineData[$p].ioR.Add($obj.ioR)
                $machineData[$p].ioW.Add($obj.ioW)
                $machineData[$p].rx.Add($obj.rx)
                $machineData[$p].tx.Add($obj.tx)
                $machineData[$p].ping.Add($obj.ping)
                if ($obj.ramTotal -gt 0) { $machineData[$p].ramTotal = $obj.ramTotal }
            } else {
                $machineData[$p].cpu.Add($null)
                $machineData[$p].ramPct.Add($null)
                $machineData[$p].ramUsed.Add($null)
                $machineData[$p].diskFree.Add($null)
                $machineData[$p].ioR.Add(0)
                $machineData[$p].ioW.Add(0)
                $machineData[$p].rx.Add(0)
                $machineData[$p].tx.Add(0)
                $machineData[$p].ping.Add($null)
            }
        }
    }
}

foreach ($line in $lines) {
    if ($line -match '^\[(\d\d:\d\d:\d\d)\]') {
        Flush-Block
        $currentTs = $matches[1]
        $currentBlockPcs = @{}
    } elseif ($line -match $pattern -and $null -ne $currentTs) {
        $pc = $matches['pc']
        if ($pc -eq 'JFMELGACO3') { $pc = 'JFMELGACO-4' }
        $isOnline = $line.StartsWith('ONLINE')
        $pingVal = if ($matches['ping'] -and $matches['ping'] -ne '---' -and $matches['ping'] -ne 'N/D') { [int]$matches['ping'] } else { $null }
        
        if ($isOnline -and $matches['cpu']) {
            $cpu = [int]$matches['cpu']
            $ramPct = [int]$matches['ramPct']
            $ramUsed = Parse-MetricNumber $matches['ramUsed']
            $ramTotal = Parse-MetricNumber $matches['ramTotal']
            $diskFree = Parse-MetricNumber $matches['diskFree']
            
            $ioR = Parse-MetricNumber $matches['ioRVal']
            if ($matches['ioRUnit'] -eq 'MB/s') { $ioR = $ioR * 1024 }
            
            $ioW = Parse-MetricNumber $matches['ioWVal']
            if ($matches['ioWUnit'] -eq 'MB/s') { $ioW = $ioW * 1024 }

            $rx = Parse-MetricNumber $matches['rxVal']
            if ($matches['rxUnit'] -eq 'MB/s') { $rx = $rx * 1024 }
            
            $tx = Parse-MetricNumber $matches['txVal']
            if ($matches['txUnit'] -eq 'MB/s') { $tx = $tx * 1024 }

            $currentBlockPcs[$pc] = @{
                cpu      = $cpu
                ramPct   = $ramPct
                ramUsed  = $ramUsed
                ramTotal = $ramTotal
                diskFree = $diskFree
                ioR      = [math]::Round($ioR, 1)
                ioW      = [math]::Round($ioW, 1)
                rx       = [math]::Round($rx, 1)
                tx       = [math]::Round($tx, 1)
                ping     = $pingVal
            }
        } else {
            $currentBlockPcs[$pc] = @{
                cpu      = $null
                ramPct   = $null
                ramUsed  = $null
                ramTotal = 0
                diskFree = $null
                ioR      = 0
                ioW      = 0
                rx       = 0
                tx       = 0
                ping     = $pingVal
            }
        }
    }
}
Flush-Block

Write-Host "Total de pontos temporais processados: $($timestamps.Count)" -ForegroundColor Green

# Calculando estatisticas consolidadas
$stats = @{}
foreach ($pc in $pcsList) {
    $validCpu = $machineData[$pc].cpu | Where-Object { $null -ne $_ }
    $validRam = $machineData[$pc].ramPct | Where-Object { $null -ne $_ }
    $validRx  = $machineData[$pc].rx | Where-Object { $null -ne $_ }
    $validTx  = $machineData[$pc].tx | Where-Object { $null -ne $_ }
    $validDisk= $machineData[$pc].diskFree | Where-Object { $null -ne $_ }
    $validIoR = $machineData[$pc].ioR | Where-Object { $null -ne $_ }
    $validIoW = $machineData[$pc].ioW | Where-Object { $null -ne $_ }
    $validPing= $machineData[$pc].ping | Where-Object { $null -ne $_ }
    
    $stats[$pc] = @{
        avgCpu  = if ($validCpu) { [math]::Round(($validCpu | Measure-Object -Average).Average, 1) } else { 0 }
        maxCpu  = if ($validCpu) { ($validCpu | Measure-Object -Maximum).Maximum } else { 0 }
        avgRam  = if ($validRam) { [math]::Round(($validRam | Measure-Object -Average).Average, 1) } else { 0 }
        maxRam  = if ($validRam) { ($validRam | Measure-Object -Maximum).Maximum } else { 0 }
        ramTotal= $machineData[$pc].ramTotal
        maxRx   = if ($validRx) { ($validRx | Measure-Object -Maximum).Maximum } else { 0 }
        maxTx   = if ($validTx) { ($validTx | Measure-Object -Maximum).Maximum } else { 0 }
        diskFree= if ($validDisk) { ($validDisk | Select-Object -Last 1) } else { 0 }
        maxIoR  = if ($validIoR) { ($validIoR | Measure-Object -Maximum).Maximum } else { 0 }
        maxIoW  = if ($validIoW) { ($validIoW | Measure-Object -Maximum).Maximum } else { 0 }
        ping    = if ($validPing) { ($validPing | Select-Object -Last 1) } else { 0 }
        avgPing = if ($validPing) { [math]::Round(($validPing | Measure-Object -Average).Average, 1) } else { 0 }
        maxPing = if ($validPing) { ($validPing | Measure-Object -Maximum).Maximum } else { 0 }
    }
}

# Gerar JSON para os graficos
$jsonTimestamps = ($timestamps | ConvertTo-Json -Compress)

$jsonPcs = [ordered]@{}
foreach ($pc in $pcsList) {
    $jsonPcs[$pc] = @{
        cpu     = $machineData[$pc].cpu
        ramPct  = $machineData[$pc].ramPct
        ramUsed = $machineData[$pc].ramUsed
        rx      = $machineData[$pc].rx
        tx      = $machineData[$pc].tx
        ioR     = $machineData[$pc].ioR
        ioW     = $machineData[$pc].ioW
        ping    = $machineData[$pc].ping
        stats   = $stats[$pc]
    }
}
$jsonData = ($jsonPcs | ConvertTo-Json -Depth 5 -Compress)

$startTime = $timestamps[0]
$endTime = $timestamps[-1]
$totalPoints = $timestamps.Count

# Identificar dinamicamente qual maquina e o host Local (a partir dos logs gravados ou do computador atual)
$detectedLocalHost = $null
foreach ($line in $lines) {
    if ($line -match '^(?:ONLINE|OFFLINE|SEM ACESSO)\s+(?<pc>JFMELGACO[^\s\(]+)\s+\(Local\)') {
        $detectedLocalHost = $matches['pc']
        break
    }
}
if (-not $detectedLocalHost -and $env:COMPUTERNAME) {
    $matchedHost = $pcsList | Where-Object { $_ -eq $env:COMPUTERNAME }
    if ($matchedHost) { $detectedLocalHost = $matchedHost }
}
if (-not $detectedLocalHost) {
    $detectedLocalHost = 'JFMELGACO-4'
}

$pcRole = @{}
$pcDisplay = @{}
foreach ($pc in $pcsList) {
    if ($pc.ToUpper() -eq $detectedLocalHost.ToUpper()) {
        $pcRole[$pc] = "LOCAL"
        $pcDisplay[$pc] = "$pc (Local)"
    } else {
        switch ($pc) {
            'JFMELGACO-1' { $pcRole[$pc] = "SRV 1";  $pcDisplay[$pc] = $pc }
            'JFMELGACO-2' { $pcRole[$pc] = "NOTE 2"; $pcDisplay[$pc] = $pc }
            'JFMELGACO-3' { $pcRole[$pc] = "NOTE 3"; $pcDisplay[$pc] = $pc }
            'JFMELGACO-4' { $pcRole[$pc] = "NOTE 4"; $pcDisplay[$pc] = $pc }
            'JFMELGACO3'   { $pcRole[$pc] = "NOTE 4"; $pcDisplay[$pc] = $pc }
            default        { $pcRole[$pc] = "REMOTO"; $pcDisplay[$pc] = $pc }
        }
    }
}
Write-Host "Host Local detectado: $detectedLocalHost (Role: $($pcRole[$detectedLocalHost]))" -ForegroundColor Yellow

# Template HTML do Dashboard
$html = @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Painel de Desempenho da Rede - JFMELGACO</title>
    <!-- Tailwind CSS CDN -->
    <script src="https://cdn.tailwindcss.com"></script>
    <!-- Chart.js CDN -->
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script>
        tailwind.config = {
            darkMode: 'class',
            theme: {
                extend: {
                    colors: {
                        darkbg: '#0f172a',
                        cardbg: '#1e293b',
                        borderbg: '#334155'
                    }
                }
            }
        }
    </script>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');
        body { font-family: 'Inter', sans-serif; }
        .chart-container { position: relative; height: 210px; width: 100%; }
        ::-webkit-scrollbar { width: 8px; height: 8px; }
        ::-webkit-scrollbar-track { background: #0f172a; }
        ::-webkit-scrollbar-thumb { background: #334155; border-radius: 4px; }
        ::-webkit-scrollbar-thumb:hover { background: #475569; }
    </style>
</head>
<body id="mainBody" class="bg-darkbg text-slate-100 h-screen max-h-screen flex flex-col p-2.5 overflow-hidden text-xs">

    <!-- HEADER ULTRA-COMPACTO (ALTURA FIXA ~38px) -->
    <header class="flex flex-wrap items-center justify-between border-b border-borderbg pb-2 gap-2 text-xs shrink-0">
        <div class="flex items-center gap-2">
            <span class="relative flex h-2.5 w-2.5">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                <span id="livePulseDot" class="relative inline-flex rounded-full h-2.5 w-2.5 bg-emerald-500 transition-colors duration-300"></span>
            </span>
            <h1 class="text-sm font-bold text-white tracking-tight flex items-center gap-1.5">Monitor de Rede JFMELGACO <span class="text-[10px] text-cyan-400 font-normal px-1.5 py-0.2 rounded bg-cyan-950/60 border border-cyan-800/80">v1.1.0</span></h1>
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

            <!-- Auto-Refresh -->
            <div class="flex items-center gap-1.5 bg-cardbg border border-borderbg px-2.5 py-1 rounded-lg">
                <span class="text-slate-400 text-[11px]">Auto:</span>
                <span id="countdownEl" class="text-emerald-400 font-bold text-[11px]">5s</span>
                <button id="pauseBtn" onclick="toggleAutoRefresh()" class="ml-1 text-[10px] px-1.5 py-0.5 rounded bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 cursor-pointer">
                    &#9208;
                </button>
            </div>

            <!-- Botão Tabela de Resumo Modal -->
            <button onclick="toggleSummaryModal(true)" class="text-[11px] px-2.5 py-1 rounded-lg bg-indigo-500/20 hover:bg-indigo-500/30 text-indigo-300 border border-indigo-500/40 font-medium transition cursor-pointer flex items-center gap-1">
                &#128203; Tabela Resumo
            </button>

            <!-- Alternador Tela Única / Rolagem -->
            <button onclick="toggleScrollMode()" id="btnScrollMode" title="Alternar entre Tela &Uacute;nica e Modo com Rolagem" class="text-[11px] px-2 py-1 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 cursor-pointer">
                &#128421;&#xFE0F; Tela &Uacute;nica
            </button>
        </div>
    </header>

    <!-- CARDS DOS COMPUTADORES (AMPLIADOS, ENRIQUECIDOS E COM LEGENDA MESTRE) -->
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-2.5 my-2 shrink-0">
        <!-- Card 1: JFMELGACO-4 (AZUL) -->
        <div id="cardHost_JFMELGACO-4" onclick="toggleMachineVisibility('JFMELGACO-4')" title="Clique para alternar visibilidade nos gr&aacute;ficos" class="bg-cardbg border border-slate-700/70 hover:border-blue-500/80 rounded-xl p-2.5 flex flex-col justify-between shadow-lg transition-all relative overflow-hidden cursor-pointer select-none hover:scale-[1.01]">
            <div id="cardTopBar_JFMELGACO-4" class="absolute top-0 left-0 right-0 h-1 bg-blue-500 transition-all"></div>
            <div class="flex items-center justify-between pb-1.5 mb-1.5 border-b border-slate-800/80">
                <div class="flex items-center gap-2">
                    <span id="cardDot_JFMELGACO-4" class="h-3.5 w-3.5 rounded-full bg-blue-500 border border-blue-300 shadow-[0_0_8px_rgba(59,130,246,0.8)] inline-block transition-all"></span>
                    <strong class="text-white text-xs tracking-wide transition-all" id="cardName_JFMELGACO-4">JFMELGACO-4</strong>
                    <span class="text-[9px] px-1.5 py-0.2 rounded font-semibold bg-blue-500/20 text-blue-300 border border-blue-500/30 uppercase">$($pcRole['JFMELGACO-4'])</span>
                </div>
                <div class="flex items-center gap-2">
                    <span id="visBadge_JFMELGACO-4" class="text-[9px] px-1.5 py-0.2 rounded font-semibold bg-blue-500/20 text-blue-300 border border-blue-500/40 transition-all">Linha Azul &#10003;</span>
                    <span class="flex items-center gap-1 text-[10px] text-slate-400">
                        <span class="h-2 w-2 rounded-full bg-emerald-400"></span>
                        <span class="text-emerald-400 font-medium">Online</span>
                        <span id="card_JFMELGACO-4_ping" class="ml-1 text-[9px] px-1.5 py-0.2 rounded font-mono font-semibold bg-slate-800 text-cyan-300 border border-cyan-500/30" title="Lat&ecirc;ncia ICMP (Ping RTT)">$($stats['JFMELGACO-4'].ping)ms</span>
                    </span>
                </div>
            </div>
            <div class="grid grid-cols-5 gap-1 text-center">
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">CPU</span>
                    <strong class="text-xs text-white" id="card_JFMELGACO-4_cpu">$($stats['JFMELGACO-4'].avgCpu)%</strong>
                </div>
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">RAM</span>
                    <strong class="text-xs text-white" id="card_JFMELGACO-4_ram">$($stats['JFMELGACO-4'].avgRam)%</strong>
                </div>
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">Disco C:</span>
                    <strong class="text-xs text-emerald-400" id="card_JFMELGACO-4_disk">$($stats['JFMELGACO-4'].diskFree)G</strong>
                </div>
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">I/O W</span>
                    <strong class="text-xs text-amber-400" id="card_JFMELGACO-4_io">$($stats['JFMELGACO-4'].maxIoW)k</strong>
                </div>
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">Rede Tx</span>
                    <strong class="text-xs text-cyan-400" id="card_JFMELGACO-4_tx">$($stats['JFMELGACO-4'].maxTx)k</strong>
                </div>
            </div>
        </div>

        <!-- Card 2: JFMELGACO-1 (VERDE) -->
        <div id="cardHost_JFMELGACO-1" onclick="toggleMachineVisibility('JFMELGACO-1')" title="Clique para alternar visibilidade nos gr&aacute;ficos" class="bg-cardbg border border-slate-700/70 hover:border-emerald-500/80 rounded-xl p-2.5 flex flex-col justify-between shadow-lg transition-all relative overflow-hidden cursor-pointer select-none hover:scale-[1.01]">
            <div id="cardTopBar_JFMELGACO-1" class="absolute top-0 left-0 right-0 h-1 bg-emerald-500 transition-all"></div>
            <div class="flex items-center justify-between pb-1.5 mb-1.5 border-b border-slate-800/80">
                <div class="flex items-center gap-2">
                    <span id="cardDot_JFMELGACO-1" class="h-3.5 w-3.5 rounded-full bg-emerald-500 border border-emerald-300 shadow-[0_0_8px_rgba(16,185,129,0.8)] inline-block transition-all"></span>
                    <strong class="text-white text-xs tracking-wide transition-all" id="cardName_JFMELGACO-1">JFMELGACO-1</strong>
                    <span class="text-[9px] px-1.5 py-0.2 rounded font-semibold bg-emerald-500/20 text-emerald-300 border border-emerald-500/30 uppercase">$($pcRole['JFMELGACO-1'])</span>
                </div>
                <div class="flex items-center gap-2">
                    <span id="visBadge_JFMELGACO-1" class="text-[9px] px-1.5 py-0.2 rounded font-semibold bg-emerald-500/20 text-emerald-300 border border-emerald-500/40 transition-all">Linha Verde &#10003;</span>
                    <span class="flex items-center gap-1 text-[10px] text-slate-400">
                        <span class="h-2 w-2 rounded-full bg-emerald-400"></span>
                        <span class="text-emerald-400 font-medium">Online</span>
                        <span id="card_JFMELGACO-1_ping" class="ml-1 text-[9px] px-1.5 py-0.2 rounded font-mono font-semibold bg-slate-800 text-cyan-300 border border-cyan-500/30" title="Lat&ecirc;ncia ICMP (Ping RTT)">$($stats['JFMELGACO-1'].ping)ms</span>
                    </span>
                </div>
            </div>
            <div class="grid grid-cols-5 gap-1 text-center">
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">CPU</span>
                    <strong class="text-xs text-white" id="card_JFMELGACO-1_cpu">$($stats['JFMELGACO-1'].avgCpu)%</strong>
                </div>
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">RAM</span>
                    <strong class="text-xs text-white" id="card_JFMELGACO-1_ram">$($stats['JFMELGACO-1'].avgRam)%</strong>
                </div>
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">Disco C:</span>
                    <strong class="text-xs text-emerald-400" id="card_JFMELGACO-1_disk">$($stats['JFMELGACO-1'].diskFree)G</strong>
                </div>
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">I/O W</span>
                    <strong class="text-xs text-amber-400" id="card_JFMELGACO-1_io">$($stats['JFMELGACO-1'].maxIoW)k</strong>
                </div>
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">Rede Rx</span>
                    <strong class="text-xs text-cyan-400" id="card_JFMELGACO-1_rx">$($stats['JFMELGACO-1'].maxRx)k</strong>
                </div>
            </div>
        </div>

        <!-- Card 3: JFMELGACO-2 (AMARELO) -->
        <div id="cardHost_JFMELGACO-2" onclick="toggleMachineVisibility('JFMELGACO-2')" title="Clique para alternar visibilidade nos gr&aacute;ficos" class="bg-cardbg border border-slate-700/70 hover:border-amber-500/80 rounded-xl p-2.5 flex flex-col justify-between shadow-lg transition-all relative overflow-hidden cursor-pointer select-none hover:scale-[1.01]">
            <div id="cardTopBar_JFMELGACO-2" class="absolute top-0 left-0 right-0 h-1 bg-amber-500 transition-all"></div>
            <div class="flex items-center justify-between pb-1.5 mb-1.5 border-b border-slate-800/80">
                <div class="flex items-center gap-2">
                    <span id="cardDot_JFMELGACO-2" class="h-3.5 w-3.5 rounded-full bg-amber-500 border border-amber-300 shadow-[0_0_8px_rgba(245,158,11,0.8)] inline-block transition-all"></span>
                    <strong class="text-white text-xs tracking-wide transition-all" id="cardName_JFMELGACO-2">JFMELGACO-2</strong>
                    <span class="text-[9px] px-1.5 py-0.2 rounded font-semibold bg-amber-500/20 text-amber-300 border border-amber-500/30 uppercase">$($pcRole['JFMELGACO-2'])</span>
                </div>
                <div class="flex items-center gap-2">
                    <span id="visBadge_JFMELGACO-2" class="text-[9px] px-1.5 py-0.2 rounded font-semibold bg-amber-500/20 text-amber-300 border border-amber-500/40 transition-all">Linha Amarela &#10003;</span>
                    <span class="flex items-center gap-1 text-[10px] text-slate-400">
                        <span class="h-2 w-2 rounded-full bg-emerald-400"></span>
                        <span class="text-emerald-400 font-medium">Online</span>
                        <span id="card_JFMELGACO-2_ping" class="ml-1 text-[9px] px-1.5 py-0.2 rounded font-mono font-semibold bg-slate-800 text-cyan-300 border border-cyan-500/30" title="Lat&ecirc;ncia ICMP (Ping RTT)">$($stats['JFMELGACO-2'].ping)ms</span>
                    </span>
                </div>
            </div>
            <div class="grid grid-cols-5 gap-1 text-center">
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">CPU</span>
                    <strong class="text-xs text-white" id="card_JFMELGACO-2_cpu">$($stats['JFMELGACO-2'].avgCpu)%</strong>
                </div>
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">RAM</span>
                    <strong class="text-xs text-white" id="card_JFMELGACO-2_ram">$($stats['JFMELGACO-2'].avgRam)%</strong>
                </div>
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">Disco C:</span>
                    <strong class="text-xs text-emerald-400" id="card_JFMELGACO-2_disk">$($stats['JFMELGACO-2'].diskFree)G</strong>
                </div>
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">I/O W</span>
                    <strong class="text-xs text-amber-400" id="card_JFMELGACO-2_io">$($stats['JFMELGACO-2'].maxIoW)k</strong>
                </div>
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">Rede Rx</span>
                    <strong class="text-xs text-cyan-400" id="card_JFMELGACO-2_rx">$($stats['JFMELGACO-2'].maxRx)k</strong>
                </div>
            </div>
        </div>

        <!-- Card 4: JFMELGACO-3 (VERMELHO) -->
        <div id="cardHost_JFMELGACO-3" onclick="toggleMachineVisibility('JFMELGACO-3')" title="Clique para alternar visibilidade nos gr&aacute;ficos" class="bg-cardbg border border-slate-700/70 hover:border-red-500/80 rounded-xl p-2.5 flex flex-col justify-between shadow-lg transition-all relative overflow-hidden cursor-pointer select-none hover:scale-[1.01]">
            <div id="cardTopBar_JFMELGACO-3" class="absolute top-0 left-0 right-0 h-1 bg-red-500 transition-all"></div>
            <div class="flex items-center justify-between pb-1.5 mb-1.5 border-b border-slate-800/80">
                <div class="flex items-center gap-2">
                    <span id="cardDot_JFMELGACO-3" class="h-3.5 w-3.5 rounded-full bg-red-500 border border-red-300 shadow-[0_0_8px_rgba(239,68,68,0.8)] inline-block transition-all"></span>
                    <strong class="text-white text-xs tracking-wide transition-all" id="cardName_JFMELGACO-3">JFMELGACO-3</strong>
                    <span class="text-[9px] px-1.5 py-0.2 rounded font-semibold bg-red-500/20 text-red-300 border border-red-500/30 uppercase">$($pcRole['JFMELGACO-3'])</span>
                </div>
                <div class="flex items-center gap-2">
                    <span id="visBadge_JFMELGACO-3" class="text-[9px] px-1.5 py-0.2 rounded font-semibold bg-red-500/20 text-red-300 border border-red-500/40 transition-all">Linha Vermelha &#10003;</span>
                    <span class="flex items-center gap-1 text-[10px] text-slate-400">
                        <span class="h-2 w-2 rounded-full bg-emerald-400"></span>
                        <span class="text-emerald-400 font-medium">Online</span>
                        <span id="card_JFMELGACO-3_ping" class="ml-1 text-[9px] px-1.5 py-0.2 rounded font-mono font-semibold bg-slate-800 text-cyan-300 border border-cyan-500/30" title="Lat&ecirc;ncia ICMP (Ping RTT)">$($stats['JFMELGACO-3'].ping)ms</span>
                    </span>
                </div>
            </div>
            <div class="grid grid-cols-5 gap-1 text-center">
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">CPU</span>
                    <strong class="text-xs text-white" id="card_JFMELGACO-3_cpu">$($stats['JFMELGACO-3'].avgCpu)%</strong>
                </div>
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">RAM</span>
                    <strong class="text-xs text-white" id="card_JFMELGACO-3_ram">$($stats['JFMELGACO-3'].avgRam)%</strong>
                </div>
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">Disco C:</span>
                    <strong class="text-xs text-emerald-400" id="card_JFMELGACO-3_disk">$($stats['JFMELGACO-3'].diskFree)G</strong>
                </div>
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">I/O W</span>
                    <strong class="text-xs text-amber-400" id="card_JFMELGACO-3_io">$($stats['JFMELGACO-3'].maxIoW)k</strong>
                </div>
                <div class="bg-slate-900/80 border border-slate-800 rounded px-1 py-1">
                    <span class="text-[8.5px] text-slate-400 uppercase block font-semibold">Rede Rx</span>
                    <strong class="text-xs text-cyan-400" id="card_JFMELGACO-3_rx">$($stats['JFMELGACO-3'].maxRx)k</strong>
                </div>
            </div>
        </div>
    </div>

    <!-- ÁREA PRINCIPAL DOS GRÁFICOS (GRID 2x2 - COMPACTO E EQUILIBRADO) -->
    <main id="chartsMain" class="flex-1 grid grid-cols-1 lg:grid-cols-2 gap-2 min-h-0">

        <!-- 1. CPU CHART -->
        <div class="chart-card bg-cardbg border border-borderbg rounded-xl p-2 flex flex-col min-h-0 shadow">
            <div class="flex items-center justify-between mb-1 px-1">
                <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                    <span class="h-2 w-2 rounded-full bg-cyan-400"></span>
                    Uso de CPU (%) &larr; Task Manager
                </span>
                <span class="text-[10px] text-slate-400">4 m&aacute;quinas</span>
            </div>
            <div class="chart-wrapper flex-1 min-h-0 relative h-[185px] lg:h-[205px]">
                <canvas id="cpuChart"></canvas>
            </div>
        </div>

        <!-- 2. RAM CHART -->
        <div class="chart-card bg-cardbg border border-borderbg rounded-xl p-2 flex flex-col min-h-0 shadow">
            <div class="flex items-center justify-between mb-1 px-1">
                <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                    <span class="h-2 w-2 rounded-full bg-indigo-400"></span>
                    Uso de Mem&oacute;ria RAM (%) &larr; Task Manager
                </span>
                <span class="text-[10px] text-slate-400">4 m&aacute;quinas</span>
            </div>
            <div class="chart-wrapper flex-1 min-h-0 relative h-[185px] lg:h-[205px]">
                <canvas id="ramChart"></canvas>
            </div>
        </div>

        <!-- 3. RX CHART (Download) -->
        <div class="chart-card bg-cardbg border border-borderbg rounded-xl p-2 flex flex-col min-h-0 shadow">
            <div class="flex items-center justify-between mb-1 px-1">
                <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                    <span class="h-2 w-2 rounded-full bg-emerald-400"></span>
                    Rede: Recep&ccedil;&atilde;o / Download (Rx em KB/s)
                </span>
                <span class="text-[10px] text-slate-400">Tempo Real</span>
            </div>
            <div class="chart-wrapper flex-1 min-h-0 relative h-[185px] lg:h-[205px]">
                <canvas id="rxChart"></canvas>
            </div>
        </div>

        <!-- 4. TX CHART & DISCO C: COM ABAS RÁPIDAS -->
        <div class="chart-card bg-cardbg border border-borderbg rounded-xl p-2 flex flex-col min-h-0 shadow">
            <div class="flex items-center justify-between mb-1 px-1">
                <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                    <span class="h-2 w-2 rounded-full bg-amber-400"></span>
                    <span id="titleBottomRight">Rede: Transmiss&atilde;o / Upload (Tx)</span>
                </span>
                <div class="flex items-center gap-1 bg-slate-900/80 px-1 py-0.5 rounded border border-slate-700/60">
                    <button onclick="switchBottomRightView('tx')" id="btnTabTx" class="text-[10px] px-2 py-0.5 rounded font-bold bg-amber-500/20 text-amber-300 border border-amber-500/40 cursor-pointer">
                        Tx (Upload)
                    </button>
                    <button onclick="switchBottomRightView('disk')" id="btnTabDisk" class="text-[10px] px-2 py-0.5 rounded text-slate-400 hover:text-slate-200 cursor-pointer">
                        Disco C: (GB)
                    </button>
                    <button onclick="switchBottomRightView('io')" id="btnTabIo" class="text-[10px] px-2 py-0.5 rounded text-slate-400 hover:text-slate-200 cursor-pointer">
                        I/O Disco
                    </button>
                    <button onclick="switchBottomRightView('ping')" id="btnTabPing" class="text-[10px] px-2 py-0.5 rounded text-slate-400 hover:text-slate-200 cursor-pointer">
                        Lat&ecirc;ncia Ping (ms)
                    </button>
                </div>
            </div>
            <div class="chart-wrapper flex-1 min-h-0 relative h-[185px] lg:h-[205px]">
                <div id="wrapperTxChart" class="h-full w-full">
                    <canvas id="txChart"></canvas>
                </div>
                <div id="wrapperDiskChart" class="h-full w-full hidden">
                    <canvas id="diskChart"></canvas>
                </div>
                <div id="wrapperIoChart" class="h-full w-full hidden">
                    <canvas id="ioChart"></canvas>
                </div>
                <div id="wrapperPingChart" class="h-full w-full hidden">
                    <canvas id="pingChart"></canvas>
                </div>
            </div>
        </div>

    </main>

    <!-- MODAL POPUP: TABELA CONSOLIDADA DE RESUMO ESTATÍSTICO -->
    <div id="summaryModal" class="fixed inset-0 bg-black/75 backdrop-blur-sm z-50 flex items-center justify-center p-4 hidden">
        <div class="bg-cardbg border border-borderbg rounded-2xl max-w-4xl w-full max-h-[85vh] flex flex-col shadow-2xl overflow-hidden">
            <div class="flex items-center justify-between p-4 border-b border-borderbg bg-slate-800/40">
                <div class="flex items-center gap-2">
                    <span class="text-base">&#128203;</span>
                    <h2 class="text-sm font-bold text-white">Tabela de Resumo Estat&iacute;stico Consolidado</h2>
                </div>
                <button onclick="toggleSummaryModal(false)" class="text-slate-400 hover:text-white px-2.5 py-1 rounded-lg hover:bg-slate-800 transition cursor-pointer text-xs">
                    &times; Fechar
                </button>
            </div>
            <div class="p-4 overflow-x-auto flex-1">
                <table class="w-full text-left text-xs text-slate-300">
                    <thead class="text-[11px] uppercase bg-slate-800 text-slate-400 border-b border-borderbg">
                        <tr>
                            <th class="py-2.5 px-3">Computador</th>
                            <th class="py-2.5 px-3">CPU M&eacute;dia</th>
                            <th class="py-2.5 px-3">CPU Pico</th>
                            <th class="py-2.5 px-3">RAM M&eacute;dia</th>
                            <th class="py-2.5 px-3">RAM M&aacute;x</th>
                            <th class="py-2.5 px-3">Pico I/O Disco (R / W)</th>
                            <th class="py-2.5 px-3">Pico Rx</th>
                            <th class="py-2.5 px-3">Pico Tx</th>
                            <th class="py-2.5 px-3">Disco C: Livre</th>
                            <th class="py-2.5 px-3">Ping (RTT)</th>
                        </tr>
                    </thead>
                    <tbody class="divide-y divide-borderbg text-xs">
                        <tr class="hover:bg-slate-800/50">
                            <td class="py-2.5 px-3 font-semibold text-blue-400">$($pcDisplay['JFMELGACO-4'])</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-4_cpuAvg">$($stats['JFMELGACO-4'].avgCpu)%</td>
                            <td class="py-2.5 px-3 font-bold text-amber-400" id="modal_JFMELGACO-4_cpuMax">$($stats['JFMELGACO-4'].maxCpu)%</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-4_ramAvg">$($stats['JFMELGACO-4'].avgRam)%</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-4_ramMax">$($stats['JFMELGACO-4'].maxRam)%</td>
                            <td class="py-2.5 px-3 text-amber-300 font-semibold" id="modal_JFMELGACO-4_io">$($stats['JFMELGACO-4'].maxIoR) / $($stats['JFMELGACO-4'].maxIoW) KB/s</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-4_rx">$($stats['JFMELGACO-4'].maxRx) KB/s</td>
                            <td class="py-2.5 px-3 font-bold text-cyan-400" id="modal_JFMELGACO-4_tx">$($stats['JFMELGACO-4'].maxTx) KB/s</td>
                            <td class="py-2.5 px-3 text-emerald-400 font-bold" id="modal_JFMELGACO-4_disk">$($stats['JFMELGACO-4'].diskFree) GB</td>
                            <td class="py-2.5 px-3 font-semibold text-cyan-300 font-mono" id="modal_JFMELGACO-4_ping">$($stats['JFMELGACO-4'].ping) ms <span class="text-[10px] text-slate-400 font-normal">(m&eacute;d $($stats['JFMELGACO-4'].avgPing)ms)</span></td>
                        </tr>
                        <tr class="hover:bg-slate-800/50">
                            <td class="py-2.5 px-3 font-semibold text-emerald-400">$($pcDisplay['JFMELGACO-1'])</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-1_cpuAvg">$($stats['JFMELGACO-1'].avgCpu)%</td>
                            <td class="py-2.5 px-3 font-bold text-amber-400" id="modal_JFMELGACO-1_cpuMax">$($stats['JFMELGACO-1'].maxCpu)%</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-1_ramAvg">$($stats['JFMELGACO-1'].avgRam)%</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-1_ramMax">$($stats['JFMELGACO-1'].maxRam)%</td>
                            <td class="py-2.5 px-3 text-amber-300 font-semibold" id="modal_JFMELGACO-1_io">$($stats['JFMELGACO-1'].maxIoR) / $($stats['JFMELGACO-1'].maxIoW) KB/s</td>
                            <td class="py-2.5 px-3 font-bold text-cyan-400" id="modal_JFMELGACO-1_rx">$($stats['JFMELGACO-1'].maxRx) KB/s</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-1_tx">$($stats['JFMELGACO-1'].maxTx) KB/s</td>
                            <td class="py-2.5 px-3 text-emerald-400 font-bold" id="modal_JFMELGACO-1_disk">$($stats['JFMELGACO-1'].diskFree) GB</td>
                            <td class="py-2.5 px-3 font-semibold text-cyan-300 font-mono" id="modal_JFMELGACO-1_ping">$($stats['JFMELGACO-1'].ping) ms <span class="text-[10px] text-slate-400 font-normal">(m&eacute;d $($stats['JFMELGACO-1'].avgPing)ms)</span></td>
                        </tr>
                        <tr class="hover:bg-slate-800/50">
                            <td class="py-2.5 px-3 font-semibold text-amber-400">$($pcDisplay['JFMELGACO-2'])</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-2_cpuAvg">$($stats['JFMELGACO-2'].avgCpu)%</td>
                            <td class="py-2.5 px-3 font-bold text-amber-400" id="modal_JFMELGACO-2_cpuMax">$($stats['JFMELGACO-2'].maxCpu)%</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-2_ramAvg">$($stats['JFMELGACO-2'].avgRam)%</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-2_ramMax">$($stats['JFMELGACO-2'].maxRam)%</td>
                            <td class="py-2.5 px-3 text-amber-300 font-semibold" id="modal_JFMELGACO-2_io">$($stats['JFMELGACO-2'].maxIoR) / $($stats['JFMELGACO-2'].maxIoW) KB/s</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-2_rx">$($stats['JFMELGACO-2'].maxRx) KB/s</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-2_tx">$($stats['JFMELGACO-2'].maxTx) KB/s</td>
                            <td class="py-2.5 px-3 text-emerald-400 font-bold" id="modal_JFMELGACO-2_disk">$($stats['JFMELGACO-2'].diskFree) GB</td>
                            <td class="py-2.5 px-3 font-semibold text-cyan-300 font-mono" id="modal_JFMELGACO-2_ping">$($stats['JFMELGACO-2'].ping) ms <span class="text-[10px] text-slate-400 font-normal">(m&eacute;d $($stats['JFMELGACO-2'].avgPing)ms)</span></td>
                        </tr>
                        <tr class="hover:bg-slate-800/50">
                            <td class="py-2.5 px-3 font-semibold text-red-400">$($pcDisplay['JFMELGACO-3'])</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-3_cpuAvg">$($stats['JFMELGACO-3'].avgCpu)%</td>
                            <td class="py-2.5 px-3 font-bold text-rose-400" id="modal_JFMELGACO-3_cpuMax">$($stats['JFMELGACO-3'].maxCpu)%</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-3_ramAvg">$($stats['JFMELGACO-3'].avgRam)%</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-3_ramMax">$($stats['JFMELGACO-3'].maxRam)%</td>
                            <td class="py-2.5 px-3 text-amber-300 font-semibold" id="modal_JFMELGACO-3_io">$($stats['JFMELGACO-3'].maxIoR) / $($stats['JFMELGACO-3'].maxIoW) KB/s</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-3_rx">$($stats['JFMELGACO-3'].maxRx) KB/s</td>
                            <td class="py-2.5 px-3" id="modal_JFMELGACO-3_tx">$($stats['JFMELGACO-3'].maxTx) KB/s</td>
                            <td class="py-2.5 px-3 text-emerald-400 font-bold" id="modal_JFMELGACO-3_disk">$($stats['JFMELGACO-3'].diskFree) GB</td>
                            <td class="py-2.5 px-3 font-semibold text-cyan-300 font-mono" id="modal_JFMELGACO-3_ping">$($stats['JFMELGACO-3'].ping) ms <span class="text-[10px] text-slate-400 font-normal">(m&eacute;d $($stats['JFMELGACO-3'].avgPing)ms)</span></td>
                        </tr>
                    </tbody>
                </table>
            </div>
            <div class="p-3 border-t border-borderbg text-center text-slate-500 text-[11px] bg-slate-800/20">
                Pressione ESC ou clique fora para fechar | Relat&oacute;rio gerado pela IA Antigravity
            </div>
        </div>
    </div>

    <!-- SCRIPT CHART.JS -->
    <script>
        let timestamps = $jsonTimestamps;
        let rawData = $jsonData;

        const colors = {
            'JFMELGACO-4': { border: '#3b82f6', bg: 'rgba(59, 130, 246, 0.14)' },  // Azul
            'JFMELGACO-1': { border: '#10b981', bg: 'rgba(16, 185, 129, 0.14)' },  // Verde
            'JFMELGACO-2': { border: '#eab308', bg: 'rgba(234, 179, 8, 0.14)' },   // Amarelo
            'JFMELGACO-3': { border: '#ef4444', bg: 'rgba(239, 68, 68, 0.14)' }    // Vermelho
        };

        // LÓGICA TASK MANAGER: Os dados entram na DIREITA e fluem para a ESQUERDA
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
                // Alimenta da direita para a esquerda: preenche a esquerda com vazios
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
            const series = rawData[pc] ? rawData[pc][metricKey] : [];
            return alignDataTaskmanager(timestamps, series, currentWindowSize).data;
        }

        const commonOptions = {
            responsive: true,
            maintainAspectRatio: false,
            interaction: { mode: 'index', intersect: false },
            plugins: {
                legend: {
                    display: false
                },
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
            elements: {
                line: { tension: 0.25, borderWidth: 2 },
                point: { radius: 1.5, hoverRadius: 5 }
            }
        };

        // ----------------------------------------------------
        // CONTROLE INTERATIVO DE VISIBILIDADE DAS MÁQUINAS (CLICK NOS CARDS)
        // ----------------------------------------------------
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

        const pcCardConfig = {
            'JFMELGACO-4': {
                colorName: 'Linha Azul',
                colorBar: 'bg-blue-500',
                dotClass: 'bg-blue-500 border-blue-300 shadow-[0_0_8px_rgba(59,130,246,0.8)]',
                badgeActive: 'bg-blue-500/20 text-blue-300 border-blue-500/40'
            },
            'JFMELGACO-1': {
                colorName: 'Linha Verde',
                colorBar: 'bg-emerald-500',
                dotClass: 'bg-emerald-500 border-emerald-300 shadow-[0_0_8px_rgba(16,185,129,0.8)]',
                badgeActive: 'bg-emerald-500/20 text-emerald-300 border-emerald-500/40'
            },
            'JFMELGACO-2': {
                colorName: 'Linha Amarela',
                colorBar: 'bg-amber-500',
                dotClass: 'bg-amber-500 border-amber-300 shadow-[0_0_8px_rgba(245,158,11,0.8)]',
                badgeActive: 'bg-amber-500/20 text-amber-300 border-amber-500/40'
            },
            'JFMELGACO-3': {
                colorName: 'Linha Vermelha',
                colorBar: 'bg-red-500',
                dotClass: 'bg-red-500 border-red-300 shadow-[0_0_8px_rgba(239,68,68,0.8)]',
                badgeActive: 'bg-red-500/20 text-red-300 border-red-500/40'
            }
        };

        function updateCardVisualState(pc) {
            const card = document.getElementById('cardHost_' + pc);
            const topBar = document.getElementById('cardTopBar_' + pc);
            const badge = document.getElementById('visBadge_' + pc);
            const dot = document.getElementById('cardDot_' + pc);
            const name = document.getElementById('cardName_' + pc);
            if (!card || !topBar || !badge) return;

            const visible = isMachineVisible(pc);
            const cfg = pcCardConfig[pc];

            if (visible) {
                card.classList.remove('opacity-40', 'grayscale-[0.8]', 'border-dashed');
                card.classList.add('opacity-100');
                card.title = 'Clique para ocultar ' + pc + ' nos gráficos';
                if (name) name.classList.remove('line-through', 'text-slate-400');
                if (cfg) {
                    topBar.className = 'absolute top-0 left-0 right-0 h-1 ' + cfg.colorBar + ' transition-all';
                    if (dot) dot.className = 'h-3.5 w-3.5 rounded-full inline-block transition-all border ' + cfg.dotClass;
                    badge.className = 'text-[9px] px-1.5 py-0.2 rounded font-semibold transition-all border ' + cfg.badgeActive;
                    badge.innerHTML = cfg.colorName + ' &#10003;';
                }
            } else {
                card.classList.remove('opacity-100');
                card.classList.add('opacity-40', 'grayscale-[0.8]', 'border-dashed');
                card.title = 'Clique para exibir ' + pc + ' nos gráficos';
                if (name) name.classList.add('line-through', 'text-slate-400');
                topBar.className = 'absolute top-0 left-0 right-0 h-1 bg-slate-600 transition-all';
                if (dot) dot.className = 'h-3.5 w-3.5 rounded-full inline-block transition-all border bg-slate-600 border-slate-500';
                badge.className = 'text-[9px] px-1.5 py-0.2 rounded font-semibold transition-all border bg-slate-800/80 text-rose-300/80 border-rose-500/40 line-through';
                badge.innerHTML = '&#10005; Oculto';
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
        const charts = {};

        // 1. CPU CHART
        charts.cpu = new Chart(document.getElementById('cpuChart'), {
            type: 'line',
            data: {
                labels: initialLabels,
                datasets: Object.keys(rawData).map(pc => ({
                    pcKey: pc,
                    metricKey: 'cpu',
                    label: pc,
                    data: getAlignedDataset(pc, 'cpu'),
                    borderColor: colors[pc].border,
                    backgroundColor: colors[pc].bg,
                    fill: false,
                    hidden: !isMachineVisible(pc)
                }))
            },
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
            data: {
                labels: initialLabels,
                datasets: Object.keys(rawData).map(pc => ({
                    pcKey: pc,
                    metricKey: 'ramPct',
                    label: pc + ' (' + rawData[pc].stats.ramTotal + ' GB)',
                    data: getAlignedDataset(pc, 'ramPct'),
                    borderColor: colors[pc].border,
                    backgroundColor: colors[pc].bg,
                    fill: false,
                    hidden: !isMachineVisible(pc)
                }))
            },
            options: {
                ...commonOptions,
                scales: {
                    ...commonOptions.scales,
                    y: { ...commonOptions.scales.y, min: 0, max: 100, ticks: { ...commonOptions.scales.y.ticks, callback: v => v + '%' } }
                }
            }
        });

        // 3. RX CHART (Download / Recebido)
        charts.rx = new Chart(document.getElementById('rxChart'), {
            type: 'line',
            data: {
                labels: initialLabels,
                datasets: Object.keys(rawData).map(pc => ({
                    pcKey: pc,
                    metricKey: 'rx',
                    label: pc,
                    data: getAlignedDataset(pc, 'rx'),
                    borderColor: colors[pc].border,
                    backgroundColor: colors[pc].bg,
                    fill: true,
                    hidden: !isMachineVisible(pc)
                }))
            },
            options: {
                ...commonOptions,
                scales: {
                    ...commonOptions.scales,
                    y: { ...commonOptions.scales.y, min: 0, ticks: { ...commonOptions.scales.y.ticks, callback: v => v + ' KB/s' } }
                }
            }
        });

        // 4. TX CHART (Upload / Transmitido)
        charts.tx = new Chart(document.getElementById('txChart'), {
            type: 'line',
            data: {
                labels: initialLabels,
                datasets: Object.keys(rawData).map(pc => ({
                    pcKey: pc,
                    metricKey: 'tx',
                    label: pc,
                    data: getAlignedDataset(pc, 'tx'),
                    borderColor: colors[pc].border,
                    backgroundColor: colors[pc].bg,
                    fill: true,
                    hidden: !isMachineVisible(pc)
                }))
            },
            options: {
                ...commonOptions,
                scales: {
                    ...commonOptions.scales,
                    y: { ...commonOptions.scales.y, min: 0, ticks: { ...commonOptions.scales.y.ticks, callback: v => v + ' KB/s' } }
                }
            }
        });

        function setWindowMode(size) {
            currentWindowSize = String(size);
            localStorage.setItem('monitorWindowSize', currentWindowSize);
            updateButtonStyles();
            refreshChartsWindow();
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

        function refreshChartsWindow(updateMode) {
            const finalLabels = alignDataTaskmanager(timestamps, timestamps, currentWindowSize).labels;
            const mode = updateMode !== undefined ? updateMode : 'none';
            ['cpu', 'ram', 'rx', 'tx', 'io', 'ping'].forEach(k => {
                if (!charts[k]) return;
                charts[k].data.labels = finalLabels;
                charts[k].data.datasets.forEach(ds => {
                    ds.data = getAlignedDataset(ds.pcKey, ds.metricKey);
                    ds.hidden = !isMachineVisible(ds.pcKey);
                });
                charts[k].update(mode);
            });
            if (charts.disk) {
                const visiblePcs = Object.keys(rawData).filter(pc => isMachineVisible(pc));
                charts.disk.data.labels = visiblePcs;
                charts.disk.data.datasets[0].data = visiblePcs.map(pc => rawData[pc].stats ? rawData[pc].stats.diskFree : 0);
                charts.disk.data.datasets[0].backgroundColor = visiblePcs.map(pc => colors[pc] ? colors[pc].border : '#3b82f6');
                charts.disk.update(mode);
            }
        }

        // Aplica o estilo do botão ativo
        updateButtonStyles();

        // 5. DISK IO LINE CHART
        charts.io = new Chart(document.getElementById('ioChart'), {
            type: 'line',
            data: {
                labels: initialLabels,
                datasets: Object.keys(rawData).map(pc => ({
                    pcKey: pc,
                    metricKey: 'ioW',
                    label: pc + ' (Write)',
                    data: getAlignedDataset(pc, 'ioW'),
                    borderColor: colors[pc].border,
                    backgroundColor: colors[pc].bg,
                    fill: false,
                    hidden: !isMachineVisible(pc)
                }))
            },
            options: {
                ...commonOptions,
                scales: {
                    ...commonOptions.scales,
                    y: { ...commonOptions.scales.y, min: 0, ticks: { ...commonOptions.scales.y.ticks, callback: v => v + ' KB/s' } }
                }
            }
        });

        // 6. DISK BAR CHART
        const initialVisiblePcs = Object.keys(rawData).filter(pc => isMachineVisible(pc));
        charts.disk = new Chart(document.getElementById('diskChart'), {
            type: 'bar',
            data: {
                labels: initialVisiblePcs,
                datasets: [
                    {
                        label: 'Espaço Livre (GB)',
                        data: initialVisiblePcs.map(pc => rawData[pc].stats ? rawData[pc].stats.diskFree : 0),
                        backgroundColor: initialVisiblePcs.map(pc => colors[pc] ? colors[pc].border : '#3b82f6'),
                        borderRadius: 6
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: { display: false },
                    tooltip: { ...commonOptions.plugins.tooltip }
                },
                scales: {
                    x: { ticks: { color: '#cbd5e1', font: { size: 10 } }, grid: { display: false } },
                    y: { ticks: { color: '#64748b', font: { size: 10 }, callback: v => v + ' GB' }, grid: { color: 'rgba(51, 65, 85, 0.35)' } }
                }
            }
        });

        // 7. PING LATENCY LINE CHART
        charts.ping = new Chart(document.getElementById('pingChart'), {
            type: 'line',
            data: {
                labels: initialLabels,
                datasets: Object.keys(rawData).map(pc => ({
                    pcKey: pc,
                    metricKey: 'ping',
                    label: pc,
                    data: getAlignedDataset(pc, 'ping'),
                    borderColor: colors[pc].border,
                    backgroundColor: colors[pc].bg,
                    fill: false,
                    hidden: !isMachineVisible(pc)
                }))
            },
            options: {
                ...commonOptions,
                scales: {
                    ...commonOptions.scales,
                    y: { ...commonOptions.scales.y, min: 0, ticks: { ...commonOptions.scales.y.ticks, callback: v => v + ' ms' } }
                }
            }
        });

        // Aplica o estado visual inicial aos cards superiores dos computadores
        Object.keys(rawData).forEach(pc => updateCardVisualState(pc));

        // 7. CONTROLES DO MODAL E DO MODO DE TELA
        function toggleSummaryModal(show) {
            const modal = document.getElementById('summaryModal');
            if (!modal) return;
            if (show) {
                modal.classList.remove('hidden');
            } else {
                modal.classList.add('hidden');
            }
        }

        window.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') toggleSummaryModal(false);
        });

        document.getElementById('summaryModal')?.addEventListener('click', (e) => {
            if (e.target.id === 'summaryModal') toggleSummaryModal(false);
        });

        function switchBottomRightView(view) {
            const wrapTx = document.getElementById('wrapperTxChart');
            const wrapDisk = document.getElementById('wrapperDiskChart');
            const wrapIo = document.getElementById('wrapperIoChart');
            const wrapPing = document.getElementById('wrapperPingChart');
            const btnTx = document.getElementById('btnTabTx');
            const btnDisk = document.getElementById('btnTabDisk');
            const btnIo = document.getElementById('btnTabIo');
            const btnPing = document.getElementById('btnTabPing');
            const title = document.getElementById('titleBottomRight');

            wrapTx.classList.add('hidden');
            wrapDisk.classList.add('hidden');
            wrapIo.classList.add('hidden');
            wrapPing.classList.add('hidden');

            const inactiveBtn = 'text-[10px] px-2 py-0.5 rounded text-slate-400 hover:text-slate-200 cursor-pointer';
            const activeBtn = 'text-[10px] px-2 py-0.5 rounded font-bold bg-amber-500/20 text-amber-300 border border-amber-500/40 cursor-pointer';

            btnTx.className = inactiveBtn;
            btnDisk.className = inactiveBtn;
            btnIo.className = inactiveBtn;
            btnPing.className = inactiveBtn;

            if (view === 'disk') {
                wrapDisk.classList.remove('hidden');
                btnDisk.className = activeBtn;
                if (title) title.innerHTML = 'Armazenamento: Espa&ccedil;o Livre em Disco C: (GB)';
                if (charts.disk) charts.disk.resize();
            } else if (view === 'io') {
                wrapIo.classList.remove('hidden');
                btnIo.className = activeBtn;
                if (title) title.innerHTML = 'Disco C: Taxa de I/O Escrita (KB/s)';
                if (charts.io) charts.io.resize();
            } else if (view === 'ping') {
                wrapPing.classList.remove('hidden');
                btnPing.className = activeBtn;
                if (title) title.innerHTML = 'Rede: Lat&ecirc;ncia ICMP (Ping RTT em ms)';
                if (charts.ping) charts.ping.resize();
            } else {
                wrapTx.classList.remove('hidden');
                btnTx.className = activeBtn;
                if (title) title.innerHTML = 'Rede: Transmiss&atilde;o / Upload (Tx em KB/s)';
                if (charts.tx) charts.tx.resize();
            }
        }

        let isSingleScreen = localStorage.getItem('monitorSingleScreen') !== 'false';

        function applyScreenMode() {
            const body = document.getElementById('mainBody');
            const btn = document.getElementById('btnScrollMode');
            const chartsMain = document.getElementById('chartsMain');
            const wrappers = document.querySelectorAll('.chart-wrapper');

            if (isSingleScreen) {
                body.className = "bg-darkbg text-slate-100 h-screen max-h-screen flex flex-col p-2.5 overflow-hidden text-xs font-sans";
                if (chartsMain) {
                    chartsMain.className = "flex-1 grid grid-cols-1 lg:grid-cols-2 gap-2 min-h-0";
                }
                wrappers.forEach(w => {
                    w.style.height = "";
                    w.classList.remove('min-h-[300px]');
                });
                if (btn) {
                    btn.innerHTML = '&#128421;&#xFE0F; Tela &Uacute;nica';
                    btn.className = 'text-[11px] px-2.5 py-1 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 cursor-pointer transition';
                }
            } else {
                body.className = "bg-darkbg text-slate-100 min-h-screen p-3 overflow-y-auto text-xs font-sans";
                if (chartsMain) {
                    chartsMain.className = "grid grid-cols-1 lg:grid-cols-2 gap-3 pb-8";
                }
                wrappers.forEach(w => {
                    w.style.height = "310px";
                    w.classList.add('min-h-[300px]');
                });
                if (btn) {
                    btn.innerHTML = '&#128220; Modo Rolagem (Ativo)';
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

        // 7. ATUALIZAÇÃO CONTÍNUA EM SEGUNDO PLANO (SEM F5 / SEM REFRESH DA PÁGINA)
        window.updateDashboardData = function(payload) {
            if (!payload || !payload.timestamps || !payload.rawData) return;

            timestamps = payload.timestamps;
            rawData = payload.rawData;

            // 1. Atualiza cabeçalho (período e contagem de amostras)
            const timeRangeEl = document.getElementById('headerTimeRange');
            if (timeRangeEl && payload.startTime && payload.endTime) {
                timeRangeEl.innerHTML = payload.startTime + ' &rarr; ' + payload.endTime;
            }
            const sampleCountEl = document.getElementById('headerSampleCount');
            if (sampleCountEl && payload.totalPoints) {
                sampleCountEl.innerText = payload.totalPoints + ' amostras';
            }

            // 2. Atualiza Mini-Cards dos computadores e Modal estatístico
            const pcs = ['JFMELGACO-4', 'JFMELGACO-1', 'JFMELGACO-2', 'JFMELGACO-3'];
            pcs.forEach(pc => {
                const s = payload.rawData[pc] ? payload.rawData[pc].stats : null;
                if (!s) return;

                // Cards do topo
                const cCpu = document.getElementById('card_' + pc + '_cpu');
                if (cCpu) cCpu.innerText = s.avgCpu + '%';
                const cRam = document.getElementById('card_' + pc + '_ram');
                if (cRam) cRam.innerText = s.avgRam + '%';
                const cDisk = document.getElementById('card_' + pc + '_disk');
                if (cDisk) cDisk.innerText = s.diskFree + 'G';
                const cIo = document.getElementById('card_' + pc + '_io');
                if (cIo) cIo.innerText = s.maxIoW + 'k';
                const cTx = document.getElementById('card_' + pc + '_tx');
                if (cTx) cTx.innerText = s.maxTx + 'k';
                const cRx = document.getElementById('card_' + pc + '_rx');
                if (cRx) cRx.innerText = s.maxRx + 'k';
                const cPing = document.getElementById('card_' + pc + '_ping');
                if (cPing) cPing.innerText = s.ping + 'ms';

                // Tabela do Modal de Resumo
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
                if (mDisk) mDisk.innerText = s.diskFree + ' GB';
                const mPing = document.getElementById('modal_' + pc + '_ping');
                if (mPing) mPing.innerHTML = s.ping + ' ms <span class="text-[10px] text-slate-400 font-normal">(m&eacute;d ' + s.avgPing + 'ms)</span>';
            });

            // 3. Atualiza os gráficos do Chart.js instantaneamente (modo 'none' = sem animação ou piscadeira)
            refreshChartsWindow('none');

            // 4. Feedback visual suave: o ponto de status pisca em ciano para sinalizar nova telemetria
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
                    .then(code => {
                        eval(code);
                    })
                    .catch(() => {
                        loadViaScriptTag();
                    });
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

        // 8. AUTO-REFRESH CONTROLLER (Atualiza dados suavemente a cada 5s sem F5)
        let refreshTimer = 5;
        let autoRefreshActive = true;

        function toggleAutoRefresh() {
            autoRefreshActive = !autoRefreshActive;
            const btn = document.getElementById('pauseBtn');
            if (btn) {
                btn.innerHTML = autoRefreshActive ? '&#9208;' : '&#9654;';
                btn.className = autoRefreshActive 
                    ? 'ml-1 text-[10px] px-1.5 py-0.5 rounded bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 transition cursor-pointer font-medium'
                    : 'ml-1 text-[10px] px-1.5 py-0.5 rounded bg-amber-500/20 hover:bg-amber-500/30 text-amber-300 border border-amber-500/40 transition cursor-pointer font-semibold';
            }
        }

        setInterval(() => {
            if (autoRefreshActive) {
                refreshTimer--;
                const el = document.getElementById('countdownEl');
                if (el) el.innerText = refreshTimer + 's';
                if (refreshTimer <= 0) {
                    refreshTimer = 5;
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
    rawData: $jsonData
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

# Sincroniza com o compartilhamento na rede se acessível
$netShareDir = "\\JFMELGACO-1\Technoflora-1\Documents\PCProcessMonitor"
$netShareHtml = "$netShareDir\dashboard_desempenho.html"
$netShareDataJs = "$netShareDir\dashboard_data.js"
if ($OutputFile -ne $netShareHtml -and (Test-Path $netShareDir)) {
    try {
        Copy-Item $OutputFile $netShareHtml -Force -ErrorAction SilentlyContinue
        Copy-Item $dataJsFile $netShareDataJs -Force -ErrorAction SilentlyContinue
    } catch {}
}
