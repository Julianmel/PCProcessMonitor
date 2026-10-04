param(
    [int]$MaxIterations = 0,
    [int]$IntervalSeconds = 5,
    [pscredential]$Credential = $null
)

# ============================================================
# PAINEL DE DESEMPENHO DA REDE EM TEMPO REAL - JFMELGACO (v1.2.0)
# ============================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Ajusta a largura da janela e do buffer do console para acomodar o painel sem quebras
try {
    $rawUI = $Host.UI.RawUI
    $maxWidth = [math]::Max($rawUI.WindowSize.Width, $rawUI.MaxPhysicalWindowSize.Width)
    $targetWidth = [math]::Min(215, $maxWidth)
    if ($targetWidth -gt $rawUI.WindowSize.Width) {
        $rawUI.BufferSize = [System.Management.Automation.Host.Size]::new($targetWidth, [math]::Max(500, $rawUI.BufferSize.Height))
        $rawUI.WindowSize = [System.Management.Automation.Host.Size]::new($targetWidth, [math]::Min(35, $rawUI.MaxPhysicalWindowSize.Height))
    }
} catch {}

# Credencial padronizada de telemetria para a rede JFMELGACO (Workgroup)
$script:defaultTelemetryCred = $null
try {
    $secPass = ConvertTo-SecureString "Monitor2026@" -AsPlainText -Force
    $script:defaultTelemetryCred = New-Object System.Management.Automation.PSCredential("Monitor", $secPass)
} catch {}

# Cores ANSI para formatação dinâmica
$esc = [char]27
$cReset    = "$esc[0m"
$cYellow   = "$esc[93m"  # Maior que a medição anterior
$cGreen    = "$esc[92m"  # Menor que a medição anterior
$cWhite    = "$esc[97m"  # Inalterado / medição inicial
$cCyan     = "$esc[96m"  # Cabeçalho e títulos
$cGray     = "$esc[90m"  # Bordas e separadores
$cRed      = "$esc[91m"  # OFFLINE
$cOnline   = "$esc[92m"  # ONLINE
$cNoAccess = "$esc[95m"  # SEM ACESSO (Rosa/Magenta: computador ligado, mas consulta WMI bloqueada)

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
if (-not $ScriptDir) { $ScriptDir = $pwd.Path }

# Lista canônica de todas as máquinas da rede (carregada de machines.json com ordenação alfabética estrita)
$machinesJsonPath = Join-Path $ScriptDir "machines.json"
if (-not (Test-Path $machinesJsonPath)) { $machinesJsonPath = Join-Path $ScriptDir "Data\machines.json" }
$Computadores = @('JFMELGACO-1', 'JFMELGACO-2', 'JFMELGACO-3', 'JFMELGACO-4')
if (Test-Path $machinesJsonPath) {
    try {
        $loadedComputers = Get-Content -Raw $machinesJsonPath -Encoding UTF8 | ConvertFrom-Json
        if ($loadedComputers -and $loadedComputers.Count -gt 0) {
            $Computadores = @($loadedComputers | Sort-Object)
        }
    } catch {}
}

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
    param(
        [string]$ComputerName,
        [pscredential]$Cred = $null
    )

    # Identifica se a máquina alvo é a máquina local onde o script está rodando
    $isLocal = ($ComputerName.ToUpper() -eq $env:COMPUTERNAME.ToUpper()) -or ($ComputerName -eq 'localhost')
    $nomeDisplay = if ($isLocal) { "$ComputerName (Local)" } else { $ComputerName }

    # Se for remoto, faz um ping rápido prévio para capturar RTT (ms) e evitar timeouts caso esteja desligado
    $isPingable = $true
    $pingMs = 0
    if (-not $isLocal) {
        try {
            $pObj = [System.Net.NetworkInformation.Ping]::new()
            $reply = $pObj.Send($ComputerName, 1000)
            if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                $isPingable = $true
                $pingMs = [int]$reply.RoundtripTime
            } else {
                $isPingable = $false
            }
        } catch {
            $isPingable = $false
        }
        if (-not $isPingable) {
            return @{
                Success     = $false
                Status      = 'OFFLINE'
                Computer    = $ComputerName
                Display     = $nomeDisplay
                Ping        = $null
                ErrorReason = 'Host inacessível (sem resposta ao ping/desligado)'
            }
        }
    } else {
        $pingMs = 0
    }

    $cimSession = $null
    $needCleanup = $false

    try {
        $sessionArgs = @{ ErrorAction = 'Stop' }
        if (-not $isLocal) {
            $effectiveCred = if ($Cred) { $Cred } else { $script:defaultTelemetryCred }
            $optDcom = New-CimSessionOption -Protocol Dcom

            # 1. Tenta DCOM com a credencial de telemetria da rede (protocolo mais confiável e rápido em Workgroup)
            $connected = $false
            if ($effectiveCred) {
                try {
                    $cimSession = New-CimSession -ComputerName $ComputerName -Credential $effectiveCred -SessionOption $optDcom -OperationTimeoutSec 3 -ErrorAction Stop
                    $null = Get-CimInstance Win32_OperatingSystem -CimSession $cimSession -ErrorAction Stop
                    $sessionArgs['CimSession'] = $cimSession
                    $needCleanup = $true
                    $connected = $true
                } catch {
                    if ($cimSession) { Remove-CimSession $cimSession -ErrorAction SilentlyContinue; $cimSession = $null }
                }
            }

            # 2. Se falhar, tenta WinRM sem credencial (autenticação integrada da sessão local)
            if (-not $connected) {
                try {
                    $optWsman = New-CimSessionOption -Protocol Wsman
                    $cimSession = New-CimSession -ComputerName $ComputerName -SessionOption $optWsman -OperationTimeoutSec 2 -ErrorAction Stop
                    $null = Get-CimInstance Win32_OperatingSystem -CimSession $cimSession -ErrorAction Stop
                    $sessionArgs['CimSession'] = $cimSession
                    $needCleanup = $true
                    $connected = $true
                } catch {
                    if ($cimSession) { Remove-CimSession $cimSession -ErrorAction SilentlyContinue; $cimSession = $null }
                }
            }

            # 3. Se falhar, tenta DCOM sem credencial (fallback de sessão local)
            if (-not $connected) {
                $cimSession = New-CimSession -ComputerName $ComputerName -SessionOption $optDcom -OperationTimeoutSec 3 -ErrorAction Stop
                $null = Get-CimInstance Win32_OperatingSystem -CimSession $cimSession -ErrorAction Stop
                $sessionArgs['CimSession'] = $cimSession
                $needCleanup = $true
            }
        }

        # 1. CPU (Amostragem de alta fidelidade alinhada ao Task Manager do Windows)
        $cpu = $null
        try {
            $perfCpu = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor @sessionArgs | Where-Object { $_.Name -eq '_Total' }
            if ($perfCpu -and $null -ne $perfCpu.PercentProcessorTime) {
                $cpu = [math]::Min(100, [math]::Max(0, [math]::Round([double]$perfCpu.PercentProcessorTime, 0)))
            }
        } catch {}

        if ($null -eq $cpu) {
            try {
                $cpuObj = Get-CimInstance Win32_Processor @sessionArgs | Measure-Object -Property LoadPercentage -Average
                $cpu = [math]::Round($cpuObj.Average, 0)
            } catch {
                $cpu = 0
            }
        }

        # 2. Memória RAM, Uptime e Último Boot (Alinhamento com o modelo de memória em uso do Task Manager)
        $os = Get-CimInstance Win32_OperatingSystem @sessionArgs
        $totalRam = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)

        # Tenta calcular memória em uso através de AvailableMBytes (desconsiderando cache Standby, idêntico ao Task Manager)
        $usedRam = $null
        try {
            $perfMem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory @sessionArgs -ErrorAction Stop
            if ($perfMem -and $null -ne $perfMem.AvailableMBytes) {
                $availGB = [math]::Round($perfMem.AvailableMBytes / 1024, 1)
                $usedRam = [math]::Max(0.0, [math]::Round($totalRam - $availGB, 1))
            }
        } catch {}

        # Fallback para FreePhysicalMemory caso o contador de desempenho falhe
        if ($null -eq $usedRam) {
            $freeRam = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
            $usedRam = [math]::Round($totalRam - $freeRam, 1)
        }
        $pctRam = [math]::Min(100, [math]::Max(0, [math]::Round(($usedRam / $totalRam) * 100, 0)))

        # Uptime e Data do Último Boot
        $lastBoot = $os.LastBootUpTime
        $bootDateStr = if ($lastBoot) { $lastBoot.ToString("dd/MM/yyyy HH:mm") } else { "N/D" }
        $uptimeSpan = if ($lastBoot) { (Get-Date) - $lastBoot } else { $null }
        $uptimeStr = if ($uptimeSpan) {
            if ($uptimeSpan.Days -gt 0) { "{0}d {1}h" -f $uptimeSpan.Days, $uptimeSpan.Hours }
            else { "{0}h {1}m" -f $uptimeSpan.Hours, $uptimeSpan.Minutes }
        } else { "N/D" }

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
            $diskPerf = Get-CimInstance Win32_PerfFormattedData_PerfDisk_LogicalDisk @sessionArgs -Filter "Name='C:'"
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
            $net = Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface @sessionArgs |
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

        # 6. Top 10 Processos com maior consumo (Win32_PerfFormattedData_PerfProc_Process)
        # Normalização de CPU por número de núcleos lógicos para evitar aberrações > 100%
        $topProcs = [System.Collections.Generic.List[hashtable]]::new()
        try {
            $numCores = if ($isLocal) {
                [System.Environment]::ProcessorCount
            } else {
                try {
                    $cs = Get-CimInstance Win32_ComputerSystem @sessionArgs -ErrorAction SilentlyContinue
                    if ($cs -and $cs.NumberOfLogicalProcessors -gt 0) { $cs.NumberOfLogicalProcessors } else { 1 }
                } catch { 1 }
            }
            if (-not $numCores -or $numCores -lt 1) { $numCores = 1 }

            $procPerf = Get-CimInstance Win32_PerfFormattedData_PerfProc_Process @sessionArgs |
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
                    Name  = $pClean
                    Pid   = [int]$pr.IDProcess
                    Cpu   = $calcCpu
                    MemMB = [math]::Round($pr.WorkingSetPrivate / 1MB, 1)
                })
            }
        } catch {}

        # 7. Temperatura do Hardware (°C)
        $tempVal = $null
        
        # 7.1 Provedor especializado LibreHardwareMonitor (DTS real por núcleo/encapsulamento de CPU)
        try {
            $lhmSensors = @(Get-CimInstance -Namespace "root/LibreHardwareMonitor" -ClassName "Sensor" @sessionArgs -Filter "SensorType='Temperature'" |
                            Where-Object { $_.Value -gt 0 -and $_.Name -notlike "*Distance*" -and $_.Name -notlike "*TjMax*" -and $_.Name -notlike "*Margin*" })
            if ($lhmSensors.Count -gt 0) {
                # Prioridade 1: CPU Package / Tctl/Tdie
                $cpuPkg = $lhmSensors | Where-Object { $_.Name -like "*Package*" -or $_.Name -like "*Tctl/Tdie*" } | Select-Object -First 1
                if ($cpuPkg) {
                    $tempVal = [math]::Round($cpuPkg.Value, 0)
                } else {
                    # Prioridade 2: Sensores de CPU Core (pico térmico entre os núcleos)
                    $cpuCores = @($lhmSensors | Where-Object { $_.Name -like "*CPU*" -or $_.Name -like "*Core*" })
                    if ($cpuCores.Count -gt 0) {
                        $tempVal = [math]::Round(($cpuCores | Measure-Object -Property Value -Maximum).Maximum, 0)
                    } else {
                        # Prioridade 3: Maior leitura entre demais sensores térmicos
                        $tempVal = [math]::Round(($lhmSensors | Measure-Object -Property Value -Maximum).Maximum, 0)
                    }
                }
            }
        } catch {}

        # 7.2 Provedor especializado OpenHardwareMonitor
        if ($null -eq $tempVal) {
            try {
                $ohmSensors = @(Get-CimInstance -Namespace "root/OpenHardwareMonitor" -ClassName "Sensor" @sessionArgs -Filter "SensorType='Temperature'" |
                                Where-Object { $_.Value -gt 0 -and $_.Name -notlike "*Distance*" -and $_.Name -notlike "*TjMax*" -and $_.Name -notlike "*Margin*" })
                if ($ohmSensors.Count -gt 0) {
                    $cpuPkg = $ohmSensors | Where-Object { $_.Name -like "*Package*" -or $_.Name -like "*Tctl/Tdie*" } | Select-Object -First 1
                    if ($cpuPkg) {
                        $tempVal = [math]::Round($cpuPkg.Value, 0)
                    } else {
                        $cpuCores = @($ohmSensors | Where-Object { $_.Name -like "*CPU*" -or $_.Name -like "*Core*" })
                        if ($cpuCores.Count -gt 0) {
                            $tempVal = [math]::Round(($cpuCores | Measure-Object -Property Value -Maximum).Maximum, 0)
                        } else {
                            $tempVal = [math]::Round(($ohmSensors | Measure-Object -Property Value -Maximum).Maximum, 0)
                        }
                    }
                }
            } catch {}
        }

        # 7.3 Provedor ACPI nativo do Windows (MSAcpi_ThermalZoneTemperature em root/wmi)
        if ($null -eq $tempVal) {
            try {
                $tzList = @(Get-CimInstance -Namespace "root/wmi" -ClassName "MSAcpi_ThermalZoneTemperature" @sessionArgs)
                # Prioriza zonas com leituras dinâmicas (descarta 2982 dK = 25°C estático de BIOS Dell sem driver OEM)
                $validTz = $tzList | Where-Object { $_.CurrentTemperature -gt 2732 -and $_.CurrentTemperature -ne 2982 } | Select-Object -First 1
                if (-not $validTz) {
                    $validTz = $tzList | Where-Object { $_.CurrentTemperature -gt 2732 } | Select-Object -First 1
                }
                if ($validTz) {
                    $tempVal = [math]::Round(($validTz.CurrentTemperature - 2732) / 10, 0)
                }
            } catch {}
        }

        # 7.4 Fallback para Win32_TemperatureProbe (root/cimv2)
        if ($null -eq $tempVal) {
            try {
                $tp = @(Get-CimInstance -ClassName Win32_TemperatureProbe @sessionArgs |
                        Where-Object { $_.CurrentReading -gt 0 }) | Select-Object -First 1
                if ($tp) { $tempVal = [math]::Round($tp.CurrentReading, 0) }
            } catch {}
        }

        return @{
            Success        = $true
            Status         = 'ONLINE'
            Computer       = $ComputerName
            Display        = $nomeDisplay
            Temp           = $tempVal
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
            Ping           = $pingMs
            Uptime         = $uptimeStr
            BootDate       = $bootDateStr
            TopProcesses   = $topProcs
        }
    } catch {
        $statusFail = if ($isPingable) { 'SEM ACESSO' } else { 'OFFLINE' }
        return @{
            Success     = $false
            Status      = $statusFail
            Computer    = $ComputerName
            Display     = $nomeDisplay
            Ping        = if ($isPingable) { $pingMs } else { $null }
            Uptime      = "---"
            BootDate    = "---"
            ErrorReason = $_.Exception.Message
        }
    } finally {
        if ($needCleanup -and $cimSession) {
            Remove-CimSession $cimSession -ErrorAction SilentlyContinue
        }
    }
}

$barLen = 10

function Build-Lines($m, $prev) {
    if (-not $m.Success) {
        if ($m.Status -eq 'SEM ACESSO') {
            $cStatus = "$cNoAccess" + "SEM ACESSO" + "$cReset"
            $fStatus = "SEM ACESSO"
        } else {
            $cStatus = "$cRed" + "OFFLINE   " + "$cReset"
            $fStatus = "OFFLINE   "
        }
        $pingDisplay = if ($null -ne $m.Ping) { "{0,3}ms" -f $m.Ping } else { "---" }
        $cPingStr = "Ping: $pingDisplay"
        $fPingStr = "Ping: $pingDisplay"
        $uptimeDisplay = if ($m.Uptime) { $m.Uptime } else { "---" }
        $cUptimeStr = "Uptime: {0,7}" -f $uptimeDisplay
        $fUptimeStr = "Uptime: {0,7}" -f $uptimeDisplay
        $cTempStr = "Temp: ---"
        $fTempStr = "Temp: ---"
        $cLine = "$cStatus {0,-22} {1,-16} {2,-28} {3,-22} {4,-24} {5,-24}  {6}  {7}  {8}" -f $m.Display, "---", "---", "---", "---", "---", $cPingStr, $cUptimeStr, $cTempStr
        $fLine = "{0,-10} {1,-22} {2,-16} {3,-28} {4,-22} {5,-24} {6,-24}  {7}  {8}  {9}" -f $fStatus, $m.Display, "---", "---", "---", "---", "---", $fPingStr, $fUptimeStr, $fTempStr
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
    $pingColored      = Color-Num $m.Ping $prev.Ping ("{0,3}ms" -f $m.Ping)

    # Linha para o console (com cores ANSI)
    $cStatus    = "$cOnline" + "ONLINE    " + "$cReset"
    $cName      = "{0,-22}" -f $m.Display
    $cCpuStr    = "[$cGray$barCpu$cReset] $cpuColored"
    $cRamStr    = "[$cGray$barRam$cReset] $ramUsedColored/{0,4:N1} GB $ramPctColored" -f $m.TotalRam
    $cDiskStr   = "$diskFreeColored $diskPctColored"
    $cDiskIOStr = "R: $diskReadColored | W: $diskWriteColored"
    $cNetStr    = "Rx: $rxColored | Tx: $txColored"
    $cPingStr   = "Ping: $pingColored"
    $cUptimeStr = "Uptime: {0,7}" -f $m.Uptime
    $cTempStr   = if ($null -ne $m.Temp) { "Temp: {0,2}°C" -f $m.Temp } else { "Temp: ---" }
    $cLine      = "$cStatus $cName $cCpuStr $cRamStr $cDiskStr  $cDiskIOStr  $cNetStr  $cPingStr  $cUptimeStr  $cTempStr"

    # Linha para o arquivo texto (texto puro, compatível com regex de auditoria)
    $fStatus    = "ONLINE    "
    $fCpuStr    = "[{0}] {1,3}%" -f $barCpu, $m.Cpu
    $fRamStr    = "[{0}] {1,4:N1}/{2,4:N1} GB ({3,2}%)" -f $barRam, $m.UsedRam, $m.TotalRam, $m.PctRam
    $fDiskStr   = "{0,5:N1} GB liv ({1,2}% us)" -f $m.DiskFree, $m.DiskPct
    $fDiskIOStr = "R: {0} | W: {1}" -f $m.DiskReadStr, $m.DiskWriteStr
    $fNetStr    = "Rx: {0} | Tx: {1}" -f $m.RxStr, $m.TxStr
    $fPingStr   = "Ping: {0,3}ms" -f $m.Ping
    $bootShort  = if ($m.BootDate -and $m.BootDate.Length -ge 16) { $m.BootDate.Substring(0, 16) } else { $m.BootDate }
    $fUptimeStr = "Uptime: {0,7} (Boot: {1})" -f $m.Uptime, $bootShort
    $fTempStr   = if ($null -ne $m.Temp) { "Temp: {0}°C" -f $m.Temp } else { "Temp: ---" }
    $fLine      = "{0,-10} {1,-22} {2,-16} {3,-28} {4,-22} {5,-24} {6,-24}  {7}  {8}  {9}" -f $fStatus, $m.Display, $fCpuStr, $fRamStr, $fDiskStr, $fDiskIOStr, $fNetStr, $fPingStr, $fUptimeStr, $fTempStr

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
        $m = Get-MachineMetrics -ComputerName $pc -Cred $Credential
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
    $null = $fileBlock.AppendLine("Status     Computador             CPU              RAM                          Disco C:               Disco I/O (R / W)        Rede (Rx / Tx)            Latência (Ping)     Uptime / Último Boot             Temperatura")
    $null = $fileBlock.AppendLine("---------- ----------             ---              ---                          --------               -----------------        --------------            ---------------     --------------------             -----------")
    foreach ($fl in $fileLines) {
        $null = $fileBlock.AppendLine($fl)
    }
    if (-not (Test-Path $logFilePath)) {
        [System.IO.File]::WriteAllText($logFilePath, "", [System.Text.UTF8Encoding]::new($true))
    }
    [System.IO.File]::AppendAllText($logFilePath, $fileBlock.ToString(), [System.Text.UTF8Encoding]::new($false))

    # 2.1 Grava snapshot dos Top 10 Processos por nó em top_processes.json
    try {
        $topProcMap = @{}
        foreach ($pc in $Computadores) {
            if ($currentMetrics.ContainsKey($pc) -and $currentMetrics[$pc].TopProcesses -and $currentMetrics[$pc].TopProcesses.Count -gt 0) {
                $topProcMap[$pc] = $currentMetrics[$pc].TopProcesses
            }
        }
        if ($topProcMap.Count -gt 0) {
            $topProcJsonPath = Join-Path $LogDir "top_processes.json"
            $jsonStr = $topProcMap | ConvertTo-Json -Depth 4
            [System.IO.File]::WriteAllText($topProcJsonPath, $jsonStr, [System.Text.UTF8Encoding]::new($true))
        }
    } catch {}

    # 3. Atualiza o dashboard HTML em tempo real
    try {
        $builder = Join-Path $ScriptDir "Build-HtmlDashboard.ps1"
        if (Test-Path $builder) {
            $dashHtml = Join-Path $ScriptDir "dashboard_desempenho.html"
            & $builder -LogFile $logFilePath -OutputFile $dashHtml *>$null
            if ($sampleCount -eq 1 -and (Test-Path $dashHtml)) {
                try {
                    Start-Process $dashHtml
                    Write-Host "Dashboard aberto automaticamente no navegador padrão: $dashHtml" -ForegroundColor Green
                } catch {}
            }
        }
    } catch {}

    # 3.1 Recarrega dinamicamente machines.json a cada 5 amostras caso alterado pelo usuário
    if ($sampleCount % 5 -eq 0 -and (Test-Path $machinesJsonPath)) {
        try {
            $dynamicComputers = Get-Content -Raw $machinesJsonPath -Encoding UTF8 | ConvertFrom-Json
            if ($dynamicComputers -and $dynamicComputers.Count -gt 0) {
                $Computadores = @($dynamicComputers | Sort-Object)
            }
        } catch {}
    }

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
    $headerBanner = "[$hora] === DESEMPENHO DA REDE (JFMELGACO) ================================================================================================================================================="
    $headerCols   = "Status     Computador             CPU              RAM                          Disco C:               Disco I/O (R / W)        Rede (Rx / Tx)            Latência (Ping)     Uptime               Temperatura"
    $headerDiv    = "---------- ----------             ---              ---                          --------               -----------------        --------------            ---------------     ------               -----------"

    Write-Host "$cCyan$headerBanner$cReset$esc[K"
    Write-Host "$cYellow$headerCols$cReset$esc[K"
    Write-Host "$cGray$headerDiv$cReset$esc[K"

    foreach ($cl in $consoleLines) {
        Write-Host "$cl$esc[K"
    }

    $legenda = "$cGray-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------$cReset"
    $infoRodape = "$cGray[$sampleCount amostras] $cYellow[^] Amarelo = Subiu$cReset $cGray|$cReset $cGreen[v] Verde = Desceu$cReset $cGray|$cReset $cWhite[=] Branco = Estavel$cReset $cGray|$cReset $cNoAccess[x] Magenta = Sem Acesso$cReset $cGray| Log: $logFileName$cReset"
    Write-Host "$legenda$esc[K"
    Write-Host "$infoRodape$esc[K"

    # 5. Guarda as métricas atuais para a próxima comparação
    $prevMetrics = $currentMetrics

    if ($MaxIterations -gt 0 -and $sampleCount -ge $MaxIterations) {
        Write-Host "Monitoramento concluído após $sampleCount medição(ões)." -ForegroundColor Cyan
        break
    }

    Start-Sleep -Seconds $IntervalSeconds
}
