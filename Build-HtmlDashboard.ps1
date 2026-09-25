param(
    [string]$LogFile = $null,
    [string]$OutputFile = "$PSScriptRoot\dashboard_desempenho.html"
)

if ([string]::IsNullOrWhiteSpace($LogFile) -or -not (Test-Path $LogFile)) {
    $latest = Get-ChildItem -Path $PSScriptRoot -Filter "*Processmonitor*.txt" -Recurse -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1
    if ($latest) {
        $LogFile = $latest.FullName
    } else {
        Write-Error "Nenhum arquivo de log encontrado em $PSScriptRoot"
        return
    }
}

Write-Host "Lendo arquivo de log: $LogFile ..." -ForegroundColor Cyan
$lines = [System.IO.File]::ReadAllLines($LogFile, [System.Text.Encoding]::UTF8)

$pattern = '^(?:ONLINE|OFFLINE)\s+(?<pc>JFMELGACO[^\s\(]+)(?:\s+\(Local\))?\s+(?:\[[^\]]+\]\s+(?<cpu>\d+)%\s+\[[^\]]+\]\s+(?<ramUsed>[\d\,]+)\s*\/\s*(?<ramTotal>[\d\,]+)\s*GB\s*\((?<ramPct>\d+)%\)\s+(?<diskFree>[\d\,]+)\s*GB\s*liv\s*\(\s*(?<diskPct>\d+)%\s*us\)\s+Rx:\s*(?<rxVal>[\d\,]+|N\/D)(?:\s*(?<rxUnit>KB\/s|MB\/s))?\s*\|\s*Tx:\s*(?<txVal>[\d\,]+|N\/D)(?:\s*(?<txUnit>KB\/s|MB\/s))?)?'

$timestamps = [System.Collections.Generic.List[string]]::new()
$pcsList = @('JFMELGACO3', 'JFMELGACO-1', 'JFMELGACO-2', 'JFMELGACO-3')

$machineData = @{}
foreach ($pc in $pcsList) {
    $machineData[$pc] = @{
        cpu      = [System.Collections.Generic.List[object]]::new()
        ramPct   = [System.Collections.Generic.List[object]]::new()
        ramUsed  = [System.Collections.Generic.List[object]]::new()
        diskFree = [System.Collections.Generic.List[object]]::new()
        rx       = [System.Collections.Generic.List[object]]::new()
        tx       = [System.Collections.Generic.List[object]]::new()
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
                $machineData[$p].rx.Add($obj.rx)
                $machineData[$p].tx.Add($obj.tx)
                if ($obj.ramTotal -gt 0) { $machineData[$p].ramTotal = $obj.ramTotal }
            } else {
                $machineData[$p].cpu.Add($null)
                $machineData[$p].ramPct.Add($null)
                $machineData[$p].ramUsed.Add($null)
                $machineData[$p].diskFree.Add($null)
                $machineData[$p].rx.Add(0)
                $machineData[$p].tx.Add(0)
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
        $isOnline = $line.StartsWith('ONLINE')
        
        if ($isOnline) {
            $cpu = [int]$matches['cpu']
            $ramPct = [int]$matches['ramPct']
            $ramUsed = [double]($matches['ramUsed'] -replace ',', '.')
            $ramTotal = [double]($matches['ramTotal'] -replace ',', '.')
            $diskFree = [double]($matches['diskFree'] -replace ',', '.')
            
            $rx = 0.0
            if ($matches['rxVal'] -and $matches['rxVal'] -ne 'N/D') {
                $rx = [double]($matches['rxVal'] -replace ',', '.')
                if ($matches['rxUnit'] -eq 'MB/s') { $rx = $rx * 1024 }
            }
            
            $tx = 0.0
            if ($matches['txVal'] -and $matches['txVal'] -ne 'N/D') {
                $tx = [double]($matches['txVal'] -replace ',', '.')
                if ($matches['txUnit'] -eq 'MB/s') { $tx = $tx * 1024 }
            }

            $currentBlockPcs[$pc] = @{
                cpu      = $cpu
                ramPct   = $ramPct
                ramUsed  = $ramUsed
                ramTotal = $ramTotal
                diskFree = $diskFree
                rx       = [math]::Round($rx, 1)
                tx       = [math]::Round($tx, 1)
            }
        } else {
            $currentBlockPcs[$pc] = @{
                cpu      = $null
                ramPct   = $null
                ramUsed  = $null
                ramTotal = 0
                diskFree = $null
                rx       = 0
                tx       = 0
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
    
    $stats[$pc] = @{
        avgCpu  = if ($validCpu) { [math]::Round(($validCpu | Measure-Object -Average).Average, 1) } else { 0 }
        maxCpu  = if ($validCpu) { ($validCpu | Measure-Object -Maximum).Maximum } else { 0 }
        avgRam  = if ($validRam) { [math]::Round(($validRam | Measure-Object -Average).Average, 1) } else { 0 }
        maxRam  = if ($validRam) { ($validRam | Measure-Object -Maximum).Maximum } else { 0 }
        ramTotal= $machineData[$pc].ramTotal
        maxRx   = if ($validRx) { ($validRx | Measure-Object -Maximum).Maximum } else { 0 }
        maxTx   = if ($validTx) { ($validTx | Measure-Object -Maximum).Maximum } else { 0 }
        diskFree= if ($validDisk) { ($validDisk | Select-Object -Last 1) } else { 0 }
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
        stats   = $stats[$pc]
    }
}
$jsonData = ($jsonPcs | ConvertTo-Json -Depth 5 -Compress)

$startTime = $timestamps[0]
$endTime = $timestamps[-1]
$totalPoints = $timestamps.Count

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
        .chart-container { position: relative; height: 320px; width: 100%; }
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
                <span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-emerald-500"></span>
            </span>
            <h1 class="text-sm font-bold text-white tracking-tight">Monitor de Rede JFMELGACO</h1>
            <span class="text-slate-500">|</span>
            <span class="text-slate-400">$startTime &rarr; $endTime</span>
            <span class="text-slate-500">|</span>
            <span class="text-cyan-400 font-semibold">$totalPoints amostras</span>
        </div>

        <div class="flex items-center gap-2">
            <!-- Seletor Task Manager -->
            <div class="flex items-center gap-1 bg-slate-900/90 px-1 py-0.5 rounded-lg border border-slate-700/60">
                <button onclick="setWindowMode(60)" id="btnWin_60" class="text-[11px] px-2.5 py-0.5 rounded font-bold bg-cyan-500/20 text-cyan-300 border border-cyan-500/40 cursor-pointer">
                    ⚡ 60 (TaskMgr)
                </button>
                <button onclick="setWindowMode(120)" id="btnWin_120" class="text-[11px] px-2.5 py-0.5 rounded text-slate-400 hover:text-slate-200 cursor-pointer">
                    120
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
                    ⏸
                </button>
            </div>

            <!-- Botão Tabela de Resumo Modal -->
            <button onclick="toggleSummaryModal(true)" class="text-[11px] px-2.5 py-1 rounded-lg bg-indigo-500/20 hover:bg-indigo-500/30 text-indigo-300 border border-indigo-500/40 font-medium transition cursor-pointer flex items-center gap-1">
                📋 Tabela Resumo
            </button>

            <!-- Alternador Tela Única / Rolagem -->
            <button onclick="toggleScrollMode()" id="btnScrollMode" title="Alternar entre Tela Única e Modo com Rolagem" class="text-[11px] px-2 py-1 rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 cursor-pointer">
                🖥️ Tela Única
            </button>
        </div>
    </header>

    <!-- CARDS DOS COMPUTADORES (MINI-BARRA COMPACTA ~46px) -->
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-2 my-1.5 shrink-0">
        <!-- Card 1: JFMELGACO3 -->
        <div class="bg-cardbg border border-blue-500/30 rounded-xl px-3 py-1.5 flex items-center justify-between text-[11px] shadow">
            <div class="flex items-center gap-1.5">
                <span class="h-2 w-2 rounded-full bg-emerald-400"></span>
                <strong class="text-white text-xs">JFMELGACO3</strong>
                <span class="text-[9px] px-1 rounded bg-blue-500/20 text-blue-400 font-semibold uppercase">Local</span>
            </div>
            <div class="flex items-center gap-2 text-slate-300">
                <span>CPU: <strong class="text-white">$($stats['JFMELGACO3'].avgCpu)%</strong></span>
                <span>RAM: <strong class="text-white">$($stats['JFMELGACO3'].avgRam)%</strong></span>
                <span>C: <strong class="text-emerald-400">$($stats['JFMELGACO3'].diskFree)G</strong></span>
                <span>Tx: <strong class="text-cyan-400">$($stats['JFMELGACO3'].maxTx)k</strong></span>
            </div>
        </div>

        <!-- Card 2: JFMELGACO-1 -->
        <div class="bg-cardbg border border-emerald-500/30 rounded-xl px-3 py-1.5 flex items-center justify-between text-[11px] shadow">
            <div class="flex items-center gap-1.5">
                <span class="h-2 w-2 rounded-full bg-emerald-400"></span>
                <strong class="text-white text-xs">JFMELGACO-1</strong>
                <span class="text-[9px] px-1 rounded bg-emerald-500/20 text-emerald-400 font-semibold uppercase">SRV 1</span>
            </div>
            <div class="flex items-center gap-2 text-slate-300">
                <span>CPU: <strong class="text-white">$($stats['JFMELGACO-1'].avgCpu)%</strong></span>
                <span>RAM: <strong class="text-white">$($stats['JFMELGACO-1'].avgRam)%</strong></span>
                <span>C: <strong class="text-emerald-400">$($stats['JFMELGACO-1'].diskFree)G</strong></span>
                <span>Rx: <strong class="text-cyan-400">$($stats['JFMELGACO-1'].maxRx)k</strong></span>
            </div>
        </div>

        <!-- Card 3: JFMELGACO-2 -->
        <div class="bg-cardbg border border-amber-500/30 rounded-xl px-3 py-1.5 flex items-center justify-between text-[11px] shadow">
            <div class="flex items-center gap-1.5">
                <span class="h-2 w-2 rounded-full bg-emerald-400"></span>
                <strong class="text-white text-xs">JFMELGACO-2</strong>
                <span class="text-[9px] px-1 rounded bg-amber-500/20 text-amber-400 font-semibold uppercase">NOTE 2</span>
            </div>
            <div class="flex items-center gap-2 text-slate-300">
                <span>CPU: <strong class="text-white">$($stats['JFMELGACO-2'].avgCpu)%</strong></span>
                <span>RAM: <strong class="text-white">$($stats['JFMELGACO-2'].avgRam)%</strong></span>
                <span>C: <strong class="text-emerald-400">$($stats['JFMELGACO-2'].diskFree)G</strong></span>
                <span>Rx: <strong class="text-cyan-400">$($stats['JFMELGACO-2'].maxRx)k</strong></span>
            </div>
        </div>

        <!-- Card 4: JFMELGACO-3 -->
        <div class="bg-cardbg border border-purple-500/30 rounded-xl px-3 py-1.5 flex items-center justify-between text-[11px] shadow">
            <div class="flex items-center gap-1.5">
                <span class="h-2 w-2 rounded-full bg-emerald-400"></span>
                <strong class="text-white text-xs">JFMELGACO-3</strong>
                <span class="text-[9px] px-1 rounded bg-purple-500/20 text-purple-400 font-semibold uppercase">NOTE 3</span>
            </div>
            <div class="flex items-center gap-2 text-slate-300">
                <span>CPU: <strong class="text-white">$($stats['JFMELGACO-3'].avgCpu)%</strong></span>
                <span>RAM: <strong class="text-white">$($stats['JFMELGACO-3'].avgRam)%</strong></span>
                <span>C: <strong class="text-emerald-400">$($stats['JFMELGACO-3'].diskFree)G</strong></span>
                <span>Rx: <strong class="text-cyan-400">$($stats['JFMELGACO-3'].maxRx)k</strong></span>
            </div>
        </div>
    </div>

    <!-- ÁREA PRINCIPAL DOS GRÁFICOS (GRID 2x2 - PREENCHE 100% DA ALTURA RESTANTE) -->
    <main id="chartsMain" class="flex-1 grid grid-cols-1 lg:grid-cols-2 gap-2 min-h-0">

        <!-- 1. CPU CHART -->
        <div class="bg-cardbg border border-borderbg rounded-xl p-2.5 flex flex-col min-h-0 shadow">
            <div class="flex items-center justify-between mb-1">
                <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                    <span class="h-2 w-2 rounded-full bg-cyan-400"></span>
                    Uso de CPU (%) &larr; Task Manager
                </span>
                <span class="text-[10px] text-slate-400">4 máquinas</span>
            </div>
            <div class="flex-1 min-h-0 relative">
                <canvas id="cpuChart"></canvas>
            </div>
        </div>

        <!-- 2. RAM CHART -->
        <div class="bg-cardbg border border-borderbg rounded-xl p-2.5 flex flex-col min-h-0 shadow">
            <div class="flex items-center justify-between mb-1">
                <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                    <span class="h-2 w-2 rounded-full bg-indigo-400"></span>
                    Uso de Memória RAM (%) &larr; Task Manager
                </span>
                <span class="text-[10px] text-slate-400">4 máquinas</span>
            </div>
            <div class="flex-1 min-h-0 relative">
                <canvas id="ramChart"></canvas>
            </div>
        </div>

        <!-- 3. RX CHART (Download) -->
        <div class="bg-cardbg border border-borderbg rounded-xl p-2.5 flex flex-col min-h-0 shadow">
            <div class="flex items-center justify-between mb-1">
                <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                    <span class="h-2 w-2 rounded-full bg-emerald-400"></span>
                    Rede: Recepção / Download (Rx em KB/s)
                </span>
                <span class="text-[10px] text-slate-400">Tempo Real</span>
            </div>
            <div class="flex-1 min-h-0 relative">
                <canvas id="rxChart"></canvas>
            </div>
        </div>

        <!-- 4. TX CHART & DISCO C: COM ABAS RÁPIDAS -->
        <div class="bg-cardbg border border-borderbg rounded-xl p-2.5 flex flex-col min-h-0 shadow">
            <div class="flex items-center justify-between mb-1">
                <span class="font-bold text-white flex items-center gap-1.5 text-xs">
                    <span class="h-2 w-2 rounded-full bg-amber-400"></span>
                    <span id="titleBottomRight">Rede: Transmissão / Upload (Tx)</span>
                </span>
                <div class="flex items-center gap-1 bg-slate-900/80 px-1 py-0.5 rounded border border-slate-700/60">
                    <button onclick="switchBottomRightView('tx')" id="btnTabTx" class="text-[10px] px-2 py-0.5 rounded font-bold bg-amber-500/20 text-amber-300 border border-amber-500/40 cursor-pointer">
                        Tx (Upload)
                    </button>
                    <button onclick="switchBottomRightView('disk')" id="btnTabDisk" class="text-[10px] px-2 py-0.5 rounded text-slate-400 hover:text-slate-200 cursor-pointer">
                        Disco C: (GB)
                    </button>
                </div>
            </div>
            <div class="flex-1 min-h-0 relative">
                <div id="wrapperTxChart" class="h-full w-full">
                    <canvas id="txChart"></canvas>
                </div>
                <div id="wrapperDiskChart" class="h-full w-full hidden">
                    <canvas id="diskChart"></canvas>
                </div>
            </div>
        </div>

    </main>

    <!-- MODAL POPUP: TABELA CONSOLIDADA DE RESUMO ESTATÍSTICO -->
    <div id="summaryModal" class="fixed inset-0 bg-black/75 backdrop-blur-sm z-50 flex items-center justify-center p-4 hidden">
        <div class="bg-cardbg border border-borderbg rounded-2xl max-w-4xl w-full max-h-[85vh] flex flex-col shadow-2xl overflow-hidden">
            <div class="flex items-center justify-between p-4 border-b border-borderbg bg-slate-800/40">
                <div class="flex items-center gap-2">
                    <span class="text-base">📋</span>
                    <h2 class="text-sm font-bold text-white">Tabela de Resumo Estatístico Consolidado</h2>
                </div>
                <button onclick="toggleSummaryModal(false)" class="text-slate-400 hover:text-white px-2.5 py-1 rounded-lg hover:bg-slate-800 transition cursor-pointer text-xs">
                    ✕ Fechar
                </button>
            </div>
            <div class="p-4 overflow-x-auto flex-1">
                <table class="w-full text-left text-xs text-slate-300">
                    <thead class="text-[11px] uppercase bg-slate-800 text-slate-400 border-b border-borderbg">
                        <tr>
                            <th class="py-2.5 px-3">Computador</th>
                            <th class="py-2.5 px-3">CPU Média</th>
                            <th class="py-2.5 px-3">CPU Pico</th>
                            <th class="py-2.5 px-3">RAM Média</th>
                            <th class="py-2.5 px-3">RAM Máx</th>
                            <th class="py-2.5 px-3">Pico Rx</th>
                            <th class="py-2.5 px-3">Pico Tx</th>
                            <th class="py-2.5 px-3">Disco C: Livre</th>
                        </tr>
                    </thead>
                    <tbody class="divide-y divide-borderbg text-xs">
                        <tr class="hover:bg-slate-800/50">
                            <td class="py-2.5 px-3 font-semibold text-blue-400">JFMELGACO3 (Local)</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO3'].avgCpu)%</td>
                            <td class="py-2.5 px-3 font-bold text-amber-400">$($stats['JFMELGACO3'].maxCpu)%</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO3'].avgRam)%</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO3'].maxRam)%</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO3'].maxRx) KB/s</td>
                            <td class="py-2.5 px-3 font-bold text-cyan-400">$($stats['JFMELGACO3'].maxTx) KB/s</td>
                            <td class="py-2.5 px-3 text-emerald-400 font-bold">$($stats['JFMELGACO3'].diskFree) GB</td>
                        </tr>
                        <tr class="hover:bg-slate-800/50">
                            <td class="py-2.5 px-3 font-semibold text-emerald-400">JFMELGACO-1</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO-1'].avgCpu)%</td>
                            <td class="py-2.5 px-3 font-bold text-amber-400">$($stats['JFMELGACO-1'].maxCpu)%</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO-1'].avgRam)%</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO-1'].maxRam)%</td>
                            <td class="py-2.5 px-3 font-bold text-cyan-400">$($stats['JFMELGACO-1'].maxRx) KB/s</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO-1'].maxTx) KB/s</td>
                            <td class="py-2.5 px-3 text-emerald-400 font-bold">$($stats['JFMELGACO-1'].diskFree) GB</td>
                        </tr>
                        <tr class="hover:bg-slate-800/50">
                            <td class="py-2.5 px-3 font-semibold text-amber-400">JFMELGACO-2</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO-2'].avgCpu)%</td>
                            <td class="py-2.5 px-3 font-bold text-amber-400">$($stats['JFMELGACO-2'].maxCpu)%</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO-2'].avgRam)%</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO-2'].maxRam)%</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO-2'].maxRx) KB/s</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO-2'].maxTx) KB/s</td>
                            <td class="py-2.5 px-3 text-emerald-400 font-bold">$($stats['JFMELGACO-2'].diskFree) GB</td>
                        </tr>
                        <tr class="hover:bg-slate-800/50">
                            <td class="py-2.5 px-3 font-semibold text-purple-400">JFMELGACO-3</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO-3'].avgCpu)%</td>
                            <td class="py-2.5 px-3 font-bold text-rose-400">$($stats['JFMELGACO-3'].maxCpu)%</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO-3'].avgRam)%</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO-3'].maxRam)%</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO-3'].maxRx) KB/s</td>
                            <td class="py-2.5 px-3">$($stats['JFMELGACO-3'].maxTx) KB/s</td>
                            <td class="py-2.5 px-3 text-emerald-400 font-bold">$($stats['JFMELGACO-3'].diskFree) GB</td>
                        </tr>
                    </tbody>
                </table>
            </div>
            <div class="p-3 border-t border-borderbg text-center text-slate-500 text-[11px] bg-slate-800/20">
                Pressione ESC ou clique fora para fechar | Relatório gerado pela IA Antigravity
            </div>
        </div>
    </div>

    <!-- SCRIPT CHART.JS -->
    <script>
        const timestamps = $jsonTimestamps;
        const rawData = $jsonData;

        const colors = {
            'JFMELGACO3':  { border: '#38bdf8', bg: 'rgba(56, 189, 248, 0.12)' },
            'JFMELGACO-1': { border: '#10b981', bg: 'rgba(16, 185, 129, 0.12)' },
            'JFMELGACO-2': { border: '#f59e0b', bg: 'rgba(245, 158, 11, 0.12)' },
            'JFMELGACO-3': { border: '#c084fc', bg: 'rgba(192, 132, 252, 0.12)' }
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
                    position: 'top',
                    labels: { color: '#94a3b8', font: { size: 12, family: 'Inter' }, usePointStyle: true, pointStyle: 'circle' }
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
                    fill: false
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
                    fill: false
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
                    fill: true
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
                    fill: true
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
            ['60', '120', 'all'].forEach(s => {
                const btn = document.getElementById('btnWin_' + s);
                if (!btn) return;
                if (String(currentWindowSize) === s) {
                    btn.className = 'text-[11px] px-2.5 py-0.5 rounded font-bold bg-cyan-500/20 text-cyan-300 border border-cyan-500/40 transition shadow-sm cursor-pointer';
                } else {
                    btn.className = 'text-[11px] px-2.5 py-0.5 rounded text-slate-400 hover:text-slate-200 transition cursor-pointer';
                }
            });
        }

        function refreshChartsWindow() {
            const finalLabels = alignDataTaskmanager(timestamps, timestamps, currentWindowSize).labels;
            ['cpu', 'ram', 'rx', 'tx'].forEach(k => {
                if (!charts[k]) return;
                charts[k].data.labels = finalLabels;
                charts[k].data.datasets.forEach(ds => {
                    ds.data = getAlignedDataset(ds.pcKey, ds.metricKey);
                });
                charts[k].update();
            });
        }

        // Aplica o estilo do botão ativo
        updateButtonStyles();

        // 5. DISK BAR CHART
        charts.disk = new Chart(document.getElementById('diskChart'), {
            type: 'bar',
            data: {
                labels: Object.keys(rawData),
                datasets: [
                    {
                        label: 'Espaço Livre (GB)',
                        data: Object.keys(rawData).map(pc => rawData[pc].stats.diskFree),
                        backgroundColor: ['#38bdf8', '#10b981', '#f59e0b', '#c084fc'],
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

        // 6. CONTROLES DO MODAL E DO MODO DE TELA
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
            const btnTx = document.getElementById('btnTabTx');
            const btnDisk = document.getElementById('btnTabDisk');
            const title = document.getElementById('titleBottomRight');

            if (view === 'disk') {
                wrapTx.classList.add('hidden');
                wrapDisk.classList.remove('hidden');
                btnDisk.className = 'text-[10px] px-2 py-0.5 rounded font-bold bg-amber-500/20 text-amber-300 border border-amber-500/40 cursor-pointer';
                btnTx.className = 'text-[10px] px-2 py-0.5 rounded text-slate-400 hover:text-slate-200 cursor-pointer';
                if (title) title.innerText = 'Armazenamento: Espaço Livre em Disco C: (GB)';
                if (charts.disk) charts.disk.resize();
            } else {
                wrapDisk.classList.add('hidden');
                wrapTx.classList.remove('hidden');
                btnTx.className = 'text-[10px] px-2 py-0.5 rounded font-bold bg-amber-500/20 text-amber-300 border border-amber-500/40 cursor-pointer';
                btnDisk.className = 'text-[10px] px-2 py-0.5 rounded text-slate-400 hover:text-slate-200 cursor-pointer';
                if (title) title.innerText = 'Rede: Transmissão / Upload (Tx em KB/s)';
                if (charts.tx) charts.tx.resize();
            }
        }

        let isSingleScreen = localStorage.getItem('monitorSingleScreen') !== 'false';

        function applyScreenMode() {
            const body = document.getElementById('mainBody');
            const btn = document.getElementById('btnScrollMode');
            if (isSingleScreen) {
                body.className = "bg-darkbg text-slate-100 h-screen max-h-screen flex flex-col p-2.5 overflow-hidden text-xs font-sans";
                if (btn) btn.innerHTML = '🖥️ Tela Única';
            } else {
                body.className = "bg-darkbg text-slate-100 min-h-screen p-3 overflow-y-auto text-xs font-sans";
                if (btn) btn.innerHTML = '📜 Modo Rolagem';
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

        // 7. AUTO-REFRESH CONTROLLER (Atualiza a cada 5s)
        let refreshTimer = 5;
        let autoRefreshActive = true;

        function toggleAutoRefresh() {
            autoRefreshActive = !autoRefreshActive;
            const btn = document.getElementById('pauseBtn');
            if (btn) {
                btn.innerText = autoRefreshActive ? '⏸' : '▶';
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
                    window.location.reload();
                }
            }
        }, 1000);
    </script>
</body>
</html>
"@

[System.IO.File]::WriteAllText($OutputFile, $html, [System.Text.Encoding]::UTF8)
Write-Host "Dashboard HTML gerado com sucesso em: $OutputFile" -ForegroundColor Green
