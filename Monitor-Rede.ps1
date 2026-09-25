param(
    [int]$MaxIterations = 0,
    [int]$IntervalSeconds = 5
)

# ============================================================
# PAINEL DE DESEMPENHO DA REDE EM TEMPO REAL - JFMELGACO
# ============================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Cores ANSI para formatação dinâmica
$esc = [char]27
$cReset  = "$esc[0m"
$cYellow = "$esc[93m"  # Maior que a medição anterior
$cGreen  = "$esc[92m"  # Menor que a medição anterior
$cWhite  = "$esc[97m"  # Inalterado / medição inicial
$cCyan   = "$esc[96m"  # Cabeçalho e títulos
$cGray   = "$esc[90m"  # Bordas e separadores
$cRed    = "$esc[91m"  # OFFLINE
$cOnline = "$esc[92m"  # ONLINE

# Lista canônica de todas as máquinas da rede
$Computadores = @(
    'JFMELGACO3',
    'JFMELGACO-1',
    'JFMELGACO-2',
    'JFMELGACO-3'
)

# Resolução dinâmica da pasta de logs (suporta execução em qualquer computador e pasta 'Data' se existir)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $ScriptDir) { $ScriptDir = $pwd.Path }

$dataSubDir = Join-Path $ScriptDir "Data"
$LogDir = if (Test-Path $dataSubDir) { $dataSubDir } else { $ScriptDir }
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$timestamp = (Get-Date).ToString("yyyyMMdd - HHmm")
$logFileName = "$timestamp - PC Processmonitor.txt"
$logFilePath = Join-Path $LogDir $logFileName

Write-Host "Iniciando monitoramento da rede (JFMELGACO)..." -ForegroundColor Cyan
Write-Host "Host Local identificado: $env:COMPUTERNAME" -ForegroundColor Yellow
Write-Host "Arquivo de log gerado em: $logFilePath" -ForegroundColor Green
Write-Host "Painel atualizado 'na mesma linha' com comparativo dinâmico de cores.`n" -ForegroundColor DarkGray

function Format-Speed($bytesPerSec) {
    if ($null -eq $bytesPerSec -or $bytesPerSec -le 0) {
        return "   0 KB/s"
    } elseif ($bytesPerSec -ge 1MB) {
        return ("{0,4:N1} MB/s" -f ($bytesPerSec / 1MB))
    } else {
        return ("{0,4:N0} KB/s" -f ($bytesPerSec / 1KB))
    }
}

# Regra 1: Quando o número for maior do que a medição anterior => Amarelo; se menor => Verde; igual/inicial => Branco
function Color-Num($current, $prev, [string]$displayStr) {
    if ($null -eq $prev -or $current -eq $prev) {
        return "$cWhite$displayStr$cReset"
    } elseif ($current -gt $prev) {
        return "$cYellow$displayStr$cReset"
    } else {
        return "$cGreen$displayStr$cReset"
    }
}

function Get-MachineMetrics {
    param([string]$ComputerName)

    # Identifica se a máquina alvo é a máquina local onde o script está rodando
    $isLocal = ($ComputerName.ToUpper() -eq $env:COMPUTERNAME.ToUpper()) -or ($ComputerName -eq 'localhost')
    $nomeDisplay = if ($isLocal) { "$ComputerName (Local)" } else { $ComputerName }

    # Se for remoto, faz um ping rápido prévio para não travar com timeouts WMI caso a máquina esteja desligada
    if (-not $isLocal) {
        $alive = Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -ErrorAction SilentlyContinue
        if (-not $alive) {
            return @{
                Success  = $false
                Computer = $ComputerName
                Display  = $nomeDisplay
            }
        }
    }

    try {
        $sessionArgs = @{ ErrorAction = 'Stop' }
        if (-not $isLocal) {
            $sessionArgs['ComputerName'] = $ComputerName
            $sessionArgs['OperationTimeoutSec'] = 3
        }

        # 1. CPU
        $cpuObj = Get-CimInstance Win32_Processor @sessionArgs | Measure-Object -Property LoadPercentage -Average
        $cpu = [math]::Round($cpuObj.Average, 0)

        # 2. Memória RAM
        $os = Get-CimInstance Win32_OperatingSystem @sessionArgs
        $totalRam = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $freeRam  = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
        $usedRam  = [math]::Round($totalRam - $freeRam, 1)
        $pctRam   = [math]::Round(($usedRam / $totalRam) * 100, 0)

        # 3. Disco C: (Espaço livre e ocupação)
        $disk = Get-CimInstance Win32_LogicalDisk @sessionArgs -Filter "DeviceID='C:'"
        $diskFree  = [math]::Round($disk.FreeSpace / 1GB, 1)
        $diskTotal = [math]::Round($disk.Size / 1GB, 1)
        $diskPct   = [math]::Round((($diskTotal - $diskFree) / $diskTotal) * 100, 0)

        # 4. Disco C: Taxa de I/O (Input / Output: Leitura e Escrita em KB/s ou MB/s)
        $diskReadBytes = 0.0
        $diskWriteBytes = 0.0
        $diskReadStr = "   0 KB/s"
        $diskWriteStr = "   0 KB/s"
        try {
            $diskPerfArgs = @{ ErrorAction = 'Stop' }
            if (-not $isLocal) {
                $diskPerfArgs['ComputerName'] = $ComputerName
                $diskPerfArgs['OperationTimeoutSec'] = 2
            }
            $diskPerf = Get-CimInstance Win32_PerfFormattedData_PerfDisk_LogicalDisk @diskPerfArgs -Filter "Name='C:'"
            if ($diskPerf) {
                $diskReadBytes = [double]$diskPerf.DiskReadBytesPersec
                $diskWriteBytes = [double]$diskPerf.DiskWriteBytesPersec
                $diskReadStr = Format-Speed $diskReadBytes
                $diskWriteStr = Format-Speed $diskWriteBytes
            }
        } catch {
            $diskReadStr = "  N/D"
            $diskWriteStr = "  N/D"
        }

        # 5. Tráfego de Rede (Rx / Tx)
        $recvBytes = 0.0
        $sentBytes = 0.0
        $rxStr = "   0 KB/s"
        $txStr = "   0 KB/s"
        try {
            $netArgs = @{ ErrorAction = 'Stop' }
            if (-not $isLocal) {
                $netArgs['ComputerName'] = $ComputerName
                $netArgs['OperationTimeoutSec'] = 2
            }
            $net = Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface @netArgs |
                   Where-Object { $_.Name -notmatch 'Loopback|isatap|Teredo' }
            if ($net) {
                $recvBytes = [double]($net | Measure-Object -Property BytesReceivedPersec -Sum).Sum
                $sentBytes = [double]($net | Measure-Object -Property BytesSentPersec -Sum).Sum
                $rxStr = Format-Speed $recvBytes
                $txStr = Format-Speed $sentBytes
            }
        } catch {
            $rxStr = "  N/D"
            $txStr = "  N/D"
        }

        return @{
            Success        = $true
            Computer       = $ComputerName
            Display        = $nomeDisplay
            Cpu            = $cpu
            TotalRam       = $totalRam
            UsedRam        = $usedRam
            PctRam         = $pctRam
            DiskFree       = $diskFree
            DiskTotal      = $diskTotal
            DiskPct        = $diskPct
            DiskReadBytes  = $diskReadBytes
            DiskWriteBytes = $diskWriteBytes
            DiskReadStr    = $diskReadStr
            DiskWriteStr   = $diskWriteStr
            RxBytes        = $recvBytes
            TxBytes        = $sentBytes
            RxStr          = $rxStr
            TxStr          = $txStr
        }
    } catch {
        return @{
            Success     = $false
            Computer    = $ComputerName
            Display     = $nomeDisplay
        }
    }
}

$barLen = 10

function Build-Lines($m, $prev) {
    if (-not $m.Success) {
        $cLine = "{0,-8} {1,-22} {2,-16} {3,-28} {4,-22} {5,-24} {6}" -f "$cRed`OFFLINE$cReset", $m.Display, "---", "---", "---", "---", "---"
        $fLine = "{0,-8} {1,-22} {2,-16} {3,-28} {4,-22} {5,-24} {6}" -f "OFFLINE", $m.Display, "---", "---", "---", "---", "---"
        return @{ Console = $cLine; File = $fLine }
    }

    # Barras gráficas (10 posições)
    $fillCpu = [math]::Min($barLen, [math]::Max(0, [math]::Round(($m.Cpu / 100) * $barLen)))
    $barCpu = ("=" * $fillCpu) + ("-" * ($barLen - $fillCpu))

    $fillRam = [math]::Min($barLen, [math]::Max(0, [math]::Round(($m.PctRam / 100) * $barLen)))
    $barRam = ("=" * $fillRam) + ("-" * ($barLen - $fillRam))

    # Comparações de cores (Amarelo se subiu, Verde se desceu, Branco se estável)
    $cpuColored       = Color-Num $m.Cpu $prev.Cpu ("{0,3}%" -f $m.Cpu)
    $ramUsedColored   = Color-Num $m.UsedRam $prev.UsedRam ("{0,4:N1}" -f $m.UsedRam)
    $ramPctColored    = Color-Num $m.PctRam $prev.PctRam ("({0,2}%)" -f $m.PctRam)
    $diskFreeColored  = Color-Num $m.DiskFree $prev.DiskFree ("{0,5:N1} GB liv" -f $m.DiskFree)
    $diskPctColored   = Color-Num $m.DiskPct $prev.DiskPct ("({0,2}% us)" -f $m.DiskPct)
    $diskReadColored  = Color-Num $m.DiskReadBytes $prev.DiskReadBytes $m.DiskReadStr
    $diskWriteColored = Color-Num $m.DiskWriteBytes $prev.DiskWriteBytes $m.DiskWriteStr
    $rxColored        = Color-Num $m.RxBytes $prev.RxBytes $m.RxStr
    $txColored        = Color-Num $m.TxBytes $prev.TxBytes $m.TxStr

    # Linha para o console (com cores ANSI)
    $cStatus    = "$cOnline" + "ONLINE  " + "$cReset"
    $cName      = "{0,-22}" -f $m.Display
    $cCpuStr    = "[$cGray$barCpu$cReset] $cpuColored"
    $cRamStr    = "[$cGray$barRam$cReset] $ramUsedColored/{0,4:N1} GB $ramPctColored" -f $m.TotalRam
    $cDiskStr   = "$diskFreeColored $diskPctColored"
    $cDiskIOStr = "R: $diskReadColored | W: $diskWriteColored"
    $cNetStr    = "Rx: $rxColored | Tx: $txColored"
    $cLine      = "$cStatus $cName $cCpuStr $cRamStr $cDiskStr  $cDiskIOStr  $cNetStr"

    # Linha para o arquivo texto (texto puro, compatível com regex de auditoria)
    $fStatus    = "ONLINE  "
    $fCpuStr    = "[{0}] {1,3}%" -f $barCpu, $m.Cpu
    $fRamStr    = "[{0}] {1,4:N1}/{2,4:N1} GB ({3,2}%)" -f $barRam, $m.UsedRam, $m.TotalRam, $m.PctRam
    $fDiskStr   = "{0,5:N1} GB liv ({1,2}% us)" -f $m.DiskFree, $m.DiskPct
    $fDiskIOStr = "R: {0} | W: {1}" -f $m.DiskReadStr, $m.DiskWriteStr
    $fNetStr    = "Rx: {0} | Tx: {1}" -f $m.RxStr, $m.TxStr
    $fLine      = "{0,-8} {1,-22} {2,-16} {3,-28} {4,-22} {5,-24} {6}" -f $fStatus, $m.Display, $fCpuStr, $fRamStr, $fDiskStr, $fDiskIOStr, $fNetStr

    return @{ Console = $cLine; File = $fLine }
}

$prevMetrics = @{}
$sampleCount = 0
$startTop = $null
$tableHeight = 9

while ($true) {
    $hora = Get-Date -Format 'HH:mm:ss'
    $sampleCount++

    # 1. Coleta métricas de todas as máquinas
    $currentMetrics = @{}
    $consoleLines = [System.Collections.Generic.List[string]]::new()
    $fileLines = [System.Collections.Generic.List[string]]::new()

    foreach ($pc in $Computadores) {
        $m = Get-MachineMetrics -ComputerName $pc
        $prev = if ($prevMetrics.ContainsKey($pc)) { $prevMetrics[$pc] } else { $null }
        $res = Build-Lines $m $prev
        $consoleLines.Add($res.Console)
        $fileLines.Add($res.File)
        if ($m.Success) {
            $currentMetrics[$pc] = $m
        }
    }

    # 2. Grava bloco no arquivo texto (AAAAMMDD - HHMM - PC Processmonitor.txt)
    $fileBlock = [System.Text.StringBuilder]::new()
    $null = $fileBlock.AppendLine("[$hora] ============================== DESEMPENHO DA REDE (JFMELGACO) ==============================")
    $null = $fileBlock.AppendLine("Status   Computador             CPU              RAM                          Disco C:               Disco I/O (R / W)        Rede (Rx / Tx)")
    $null = $fileBlock.AppendLine("------   ----------             ---              ---                          --------               -----------------        --------------")
    foreach ($fl in $fileLines) {
        $null = $fileBlock.AppendLine($fl)
    }
    $null = $fileBlock.AppendLine()
    [System.IO.File]::AppendAllText($logFilePath, $fileBlock.ToString(), [System.Text.Encoding]::UTF8)

    # 3. Atualiza o dashboard HTML em tempo real
    try {
        $builder = Join-Path $ScriptDir "Build-HtmlDashboard.ps1"
        if (Test-Path $builder) {
            & $builder -LogFile $logFilePath -OutputFile (Join-Path $ScriptDir "dashboard_desempenho.html") *>$null
        }
    } catch {}

    # 4. Renderização no terminal "na mesma linha"
    if ($null -eq $startTop) {
        try {
            if ([Console]::CursorTop + $tableHeight + 2 -ge [Console]::BufferHeight) {
                Clear-Host
            }
            $startTop = [Console]::CursorTop
        } catch {
            $startTop = -1
        }
    } else {
        if ($startTop -ge 0) {
            try {
                [Console]::SetCursorPosition(0, $startTop)
            } catch {
                Write-Host ("$esc[{0}A$esc[0G" -f $tableHeight) -NoNewline
            }
        } else {
            Write-Host ("$esc[{0}A$esc[0G" -f $tableHeight) -NoNewline
        }
    }

    # Imprime tabela com cabeçalho, dados e rodapé de status
    $headerBanner = "[$hora] ============================== DESEMPENHO DA REDE (JFMELGACO) =============================="
    $headerCols   = "Status   Computador             CPU              RAM                          Disco C:               Disco I/O (R / W)        Rede (Rx / Tx)"
    $headerDiv    = "------   ----------             ---              ---                          --------               -----------------        --------------"

    Write-Host "$cCyan$headerBanner$cReset".PadRight(150)
    Write-Host "$cYellow$headerCols$cReset".PadRight(150)
    Write-Host "$cGray$headerDiv$cReset".PadRight(150)

    foreach ($cl in $consoleLines) {
        Write-Host $cl.PadRight(150)
    }

    $legenda = "$cGray-------------------------------------------------------------------------------------------------------------------------------------------------$cReset"
    $infoRodape = "$cGray[$sampleCount amostras] $cYellow▲ Amarelo = Subiu$cReset $cGray|$cReset $cGreen▼ Verde = Desceu$cReset $cGray|$cReset $cWhite■ Branco = Estável$cReset $cGray| Log: $logFileName$cReset"
    Write-Host $legenda.PadRight(150)
    Write-Host $infoRodape.PadRight(150)

    # 5. Guarda as métricas atuais para a próxima comparação
    $prevMetrics = $currentMetrics

    if ($MaxIterations -gt 0 -and $sampleCount -ge $MaxIterations) {
        Write-Host "Monitoramento concluído após $sampleCount medição(ões)." -ForegroundColor Cyan
        break
    }

    Start-Sleep -Seconds $IntervalSeconds
}
