<#
.SYNOPSIS
    Agente de Telemetria Ultraleve para Windows (PCProcessMonitor)
    Exporta métricas de CPU, RAM, Disco, Rede, Temperatura e Top Processos em JSON via HTTP na porta 9123.
#>

param(
    [int]$Port = 9123,
    [int]$IntervalSeconds = 1
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Garantia de instância única
$myPid = $PID
Get-CimInstance Win32_Process -Filter "Name LIKE '%powershell%'" | 
    Where-Object { $_.ProcessId -ne $myPid -and $_.CommandLine -like "*pc_telemetry.ps1*" } | 
    ForEach-Object {
        try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }

$cachedMetrics = @{
    Cpu            = 0
    TotalRam       = 0.0
    UsedRam        = 0.0
    PctRam         = 0
    DiskTotal      = 0.0
    DiskFree       = 0.0
    DiskPct        = 0
    DiskReadBytes  = 0.0
    DiskWriteBytes = 0.0
    RxBytes        = 0.0
    TxBytes        = 0.0
    Temp           = $null
    Uptime         = "0h 0m"
    BootDate       = "N/D"
    TopProcesses   = @()
}

$metricsLock = [System.Object]::new()

function Get-LhmTemperature {
    try {
        $webResp = Invoke-RestMethod -Uri "http://127.0.0.1:8085/data.json" -TimeoutSec 1 -ErrorAction Stop
        if ($webResp) {
            $stack = [System.Collections.Generic.Stack[psobject]]::new()
            $stack.Push($webResp)
            $httpTemps = [System.Collections.Generic.List[psobject]]::new()
            while ($stack.Count -gt 0) {
                $node = $stack.Pop()
                if ($node.Value -and $node.Text) {
                    if ($node.Value -match '([0-9]+[.,]?[0-9]*)\s*°?C') {
                        $val = [double]($Matches[1] -replace ',', '.')
                        if ($val -gt 0 -and $node.Text -notlike "*Distance*" -and $node.Text -notlike "*TjMax*" -and $node.Text -notlike "*Margin*") {
                            $httpTemps.Add([PSCustomObject]@{ Name = $node.Text; Value = $val })
                        }
                    }
                }
                if ($node.Children) {
                    foreach ($child in $node.Children) { $stack.Push($child) }
                }
            }
            if ($httpTemps.Count -gt 0) {
                $cpuPkg = $httpTemps | Where-Object { $_.Name -like "*Package*" -or $_.Name -like "*Tctl/Tdie*" } | Select-Object -First 1
                if ($cpuPkg) { return [math]::Round($cpuPkg.Value, 0) }
                $cpuCores = @($httpTemps | Where-Object { $_.Name -like "*CPU*" -or $_.Name -like "*Core*" })
                if ($cpuCores.Count -gt 0) {
                    return [math]::Round(($cpuCores | Measure-Object -Property Value -Maximum).Maximum, 0)
                }
                return [math]::Round(($httpTemps | Measure-Object -Property Value -Maximum).Maximum, 0)
            }
        }
    } catch {}

    # Provedor WMI LibreHardwareMonitor
    try {
        $sensors = @(Get-CimInstance -Namespace "root/LibreHardwareMonitor" -ClassName "Sensor" -Filter "SensorType='Temperature'" -ErrorAction SilentlyContinue)
        if ($sensors.Count -gt 0) {
            $cpuPkg = $sensors | Where-Object { $_.Name -like "*Package*" -or $_.Name -like "*Tctl/Tdie*" } | Select-Object -First 1
            if ($cpuPkg) { return [math]::Round($cpuPkg.Value, 0) }
            $maxCore = ($sensors | Where-Object { $_.Name -like "*CPU*" -or $_.Name -like "*Core*" } | Measure-Object -Property Value -Maximum).Maximum
            if ($maxCore -gt 0) { return [math]::Round($maxCore, 0) }
        }
    } catch {}

    # Provedor WMI OpenHardwareMonitor
    try {
        $sensors = @(Get-CimInstance -Namespace "root/OpenHardwareMonitor" -ClassName "Sensor" -Filter "SensorType='Temperature'" -ErrorAction SilentlyContinue)
        if ($sensors.Count -gt 0) {
            $cpuPkg = $sensors | Where-Object { $_.Name -like "*Package*" } | Select-Object -First 1
            if ($cpuPkg) { return [math]::Round($cpuPkg.Value, 0) }
            $maxCore = ($sensors | Where-Object { $_.Name -like "*CPU*" } | Measure-Object -Property Value -Maximum).Maximum
            if ($maxCore -gt 0) { return [math]::Round($maxCore, 0) }
        }
    } catch {}

    # Provedor ACPI nativo fallback
    try {
        $tzList = @(Get-CimInstance -Namespace "root/wmi" -ClassName "MSAcpi_ThermalZoneTemperature" -ErrorAction SilentlyContinue)
        $validTz = $tzList | Where-Object { $_.CurrentTemperature -gt 2732 -and $_.CurrentTemperature -ne 2982 } | Select-Object -First 1
        if ($validTz) {
            return [math]::Round(($validTz.CurrentTemperature - 2732) / 10, 0)
        }
    } catch {}

    # Provedor Win32_TemperatureProbe fallback
    try {
        $tp = @(Get-CimInstance -ClassName Win32_TemperatureProbe -ErrorAction SilentlyContinue | Where-Object { $_.CurrentReading -gt 0 }) | Select-Object -First 1
        if ($tp) { return [math]::Round($tp.CurrentReading, 0) }
    } catch {}

    return $null
}

function Update-LocalMetrics {
    try {
        # 1. CPU
        $cpuVal = 0
        try {
            $perfCpu = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue
            if ($perfCpu -and $null -ne $perfCpu.PercentProcessorTime) {
                $cpuVal = [math]::Min(100, [math]::Max(0, [math]::Round([double]$perfCpu.PercentProcessorTime, 0)))
            }
        } catch {}

        # 2. RAM & Uptime
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $totalRam = 0.0
        $usedRam = 0.0
        $pctRam = 0
        $uptimeStr = "N/D"
        $bootDateStr = "N/D"

        if ($os) {
            $totalRam = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
            $availGB = 0.0
            try {
                $perfMem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue
                if ($perfMem -and $null -ne $perfMem.AvailableMBytes) {
                    $availGB = [math]::Round($perfMem.AvailableMBytes / 1024, 1)
                    $usedRam = [math]::Max(0.0, [math]::Round($totalRam - $availGB, 1))
                }
            } catch {}

            if ($usedRam -le 0) {
                $freeRam = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
                $usedRam = [math]::Round($totalRam - $freeRam, 1)
            }
            if ($totalRam -gt 0) {
                $pctRam = [math]::Min(100, [math]::Max(0, [math]::Round(($usedRam / $totalRam) * 100, 0)))
            }

            $lastBoot = $os.LastBootUpTime
            if ($lastBoot) {
                $bootDateStr = $lastBoot.ToString("dd/MM/yyyy HH:mm")
                $uptimeSpan = (Get-Date) - $lastBoot
                $uptimeStr = if ($uptimeSpan.Days -gt 0) { "{0}d {1}h" -f $uptimeSpan.Days, $uptimeSpan.Hours } else { "{0}h {1}m" -f $uptimeSpan.Hours, $uptimeSpan.Minutes }
            }
        }

        # 3. Disco C:
        $diskTotal = 0.0
        $diskFree = 0.0
        $diskPct = 0
        try {
            $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -ErrorAction SilentlyContinue
            if ($disk -and $disk.Size -gt 0) {
                $diskTotal = [math]::Round($disk.Size / 1GB, 1)
                $diskFree = [math]::Round($disk.FreeSpace / 1GB, 1)
                $diskPct = [math]::Round((($diskTotal - $diskFree) / $diskTotal) * 100, 0)
            }
        } catch {}

        # 4. Disco I/O
        $diskReadBytes = 0.0
        $diskWriteBytes = 0.0
        try {
            $diskPerf = Get-CimInstance Win32_PerfFormattedData_PerfDisk_LogicalDisk -Filter "Name='C:'" -ErrorAction SilentlyContinue
            if ($diskPerf) {
                $diskReadBytes = [double]$diskPerf.DiskReadBytesPersec
                $diskWriteBytes = [double]$diskPerf.DiskWriteBytesPersec
            }
        } catch {}

        # 5. Rede (Rx / Tx)
        $rxBytes = 0.0
        $txBytes = 0.0
        try {
            $net = Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -notmatch 'Loopback|isatap|Teredo' }
            if ($net) {
                $rxBytes = [double]($net | Measure-Object -Property BytesReceivedPersec -Sum).Sum
                $txBytes = [double]($net | Measure-Object -Property BytesSentPersec -Sum).Sum
            }
        } catch {}

        # 6. Temperatura
        $temp = Get-LhmTemperature

        # 7. Top Processos
        $topProcs = [System.Collections.Generic.List[hashtable]]::new()
        try {
            $numCores = [System.Environment]::ProcessorCount
            if ($numCores -lt 1) { $numCores = 1 }
            $procPerf = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notin '_Total', 'Idle' } |
                Sort-Object -Property PercentProcessorTime, WorkingSetPrivate -Descending |
                Select-Object -First 10
            foreach ($pr in $procPerf) {
                $pClean = ($pr.Name -replace '#\d+$', '')
                if (-not $pClean.EndsWith('.exe', [System.StringComparison]::OrdinalIgnoreCase) -and $pClean -ne 'System') {
                    $pClean = "$pClean.exe"
                }
                $calcCpu = [math]::Round([double]$pr.PercentProcessorTime / $numCores, 1)
                $topProcs.Add(@{
                    Pid   = [int]$pr.IDProcess
                    Name  = $pClean
                    Cpu   = $calcCpu
                    MemMB = [math]::Round($pr.WorkingSetPrivate / 1MB, 1)
                })
            }
        } catch {}

        [System.Threading.Monitor]::Enter($metricsLock)
        try {
            $script:cachedMetrics = @{
                Cpu            = $cpuVal
                TotalRam       = $totalRam
                UsedRam        = $usedRam
                PctRam         = $pctRam
                DiskTotal      = $diskTotal
                DiskFree       = $diskFree
                DiskPct        = $diskPct
                DiskReadBytes  = $diskReadBytes
                DiskWriteBytes = $diskWriteBytes
                RxBytes        = $rxBytes
                TxBytes        = $txBytes
                Temp           = $temp
                Uptime         = $uptimeStr
                BootDate       = $bootDateStr
                TopProcesses   = $topProcs
            }
        } finally {
            [System.Threading.Monitor]::Exit($metricsLock)
        }
    } catch {}
}

# Inicializa as primeiras métricas
Update-LocalMetrics

# Inicia o TcpListener na porta configurada
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $Port)
$listener.Start()
Write-Output "Agente de Telemetria Windows ativo em http://0.0.0.0:$Port/metrics (PID: $PID)"

$lastUpdate = [System.Diagnostics.Stopwatch]::StartNew()

try {
    while ($true) {
        # Atualiza métricas no intervalo especificado
        if ($lastUpdate.ElapsedMilliseconds -ge ($IntervalSeconds * 1000)) {
            Update-LocalMetrics
            $lastUpdate.Restart()
        }

        # Processa requisições HTTP pendentes
        while ($listener.Pending()) {
            try {
                $client = $listener.AcceptTcpClient()
                $stream = $client.GetStream()
                $buffer = New-Object byte[] 2048
                $read = $stream.Read($buffer, 0, $buffer.Length)
                $request = [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)

                [System.Threading.Monitor]::Enter($metricsLock)
                $jsonStr = $script:cachedMetrics | ConvertTo-Json -Depth 4 -Compress
                [System.Threading.Monitor]::Exit($metricsLock)

                $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonStr)
                $responseHeader = "HTTP/1.1 200 OK`r`nContent-Type: application/json; charset=utf-8`r`nContent-Length: $($jsonBytes.Length)`r`nAccess-Control-Allow-Origin: *`r`nConnection: close`r`n`r`n"
                $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($responseHeader)

                $stream.Write($headerBytes, 0, $headerBytes.Length)
                $stream.Write($jsonBytes, 0, $jsonBytes.Length)
                $stream.Flush()
                $client.Close()
            } catch {
                if ($client) { try { $client.Close() } catch {} }
            }
        }

        Start-Sleep -Milliseconds 100
    }
} finally {
    $listener.Stop()
}
