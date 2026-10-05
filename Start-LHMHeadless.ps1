<#
.SYNOPSIS
    Serviço Headless de Telemetria Térmica do LibreHardwareMonitor (PCProcessMonitor).
.DESCRIPTION
    Executa a telemetria do LibreHardwareMonitor sem interface gráfica (GUI), permitindo
    a publicação contínua dos sensores de hardware no namespace WMI root\LibreHardwareMonitor
    mesmo em Sessão 0 (sob a conta SYSTEM) no boot do Windows, sem necessidade de usuário logado.
#>

param(
    [string]$InstallPath = "C:\Tools\LibreHardwareMonitor",
    [int]$IntervalSeconds = 3
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$logFile = Join-Path $InstallPath "lhm_headless.log"
function Write-Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $msg
    try { Add-Content -Path $logFile -Value $line -Force } catch {}
}

Write-Log "=== INICIANDO Start-LHMHeadless (PID: $PID, Session: $((Get-Process -Id $PID).SessionId), User: $env:USERNAME) ==="

$dllPath = Join-Path $InstallPath "LibreHardwareMonitorLib.dll"
$exePath = Join-Path $InstallPath "LibreHardwareMonitor.exe"

if (-not (Test-Path $dllPath) -or -not (Test-Path $exePath)) {
    Write-Log "[ERRO] Bibliotecas do LibreHardwareMonitor não encontradas em $InstallPath"
    exit 1
}

try {
    $null = [System.Reflection.Assembly]::LoadFrom($dllPath)
    $null = [System.Reflection.Assembly]::LoadFrom($exePath)
    Write-Log "[OK] Assemblies carregados com sucesso."
} catch {
    Write-Log "[ERRO] Falha ao carregar assemblies: $($_.Exception.ToString())"
    exit 1
}

$computer = New-Object LibreHardwareMonitor.Hardware.Computer
$computer.IsCpuEnabled = $true
$computer.IsMotherboardEnabled = $true
$computer.IsMemoryEnabled = $true
$computer.IsGpuEnabled = $true
$computer.IsStorageEnabled = $false
$computer.IsNetworkEnabled = $false
$computer.IsControllerEnabled = $false

try {
    Write-Log "Abrindo Computer..."
    $computer.Open()
    Write-Log "[OK] Computer.Open() concluído. Total de Hardware: $($computer.Hardware.Count)"
    foreach ($h in $computer.Hardware) {
        Write-Log "  Hardware detectado: $($h.Name) ($($h.HardwareType)) - Sensores: $($h.Sensors.Count)"
        foreach ($s in $h.Sensors) {
            if ($s.SensorType -eq "Temperature") {
                Write-Log "    Sensor Térmico: $($s.Name) = $($s.Value) °C"
            }
        }
    }
} catch {
    Write-Log "[ERRO] Falha ao abrir Computer: $($_.Exception.ToString())"
    exit 1
}

$wmi = $null
try {
    Write-Log "Instanciando WmiProvider..."
    $wmi = New-Object LibreHardwareMonitor.Wmi.WmiProvider($computer)
    Write-Log "[OK] WmiProvider instanciado com sucesso."
} catch {
    Write-Log "[ERRO] Falha ao instanciar WmiProvider: $($_.Exception.ToString())"
    $computer.Close()
    exit 1
}

# Permissão para usuário Monitor
try {
    $monUser = Get-LocalUser -Name "Monitor" -ErrorAction SilentlyContinue
    if ($monUser) {
        $sidObj = (New-Object System.Security.Principal.NTAccount("Monitor")).Translate([System.Security.Principal.SecurityIdentifier])
        $localSidBytes = New-Object byte[] ($sidObj.BinaryLength)
        $sidObj.GetBinaryForm($localSidBytes, 0)
        $b64 = "AQAEgJQAAACkAAAAAAAAABQAAAACAIAABQAAAAAAJAAjAAIAAQUAAAAAAAUVAAAAV3LPoKSHU0cqOBGlBAQAAAASGAA/AAYAAQIAAAAAAAUgAAAAIAIAAAASFAATAAAAAQEAAAAAAAUUAAAAABIUABMAAAABAQAAAAAABRMAAAAAEhQAEwAAAAEBAAAAAAAFCwAAAAECAAAAAAAFIAAAACACAAABAgAAAAAABSAAAAAgAgAA"
        $bin = [Convert]::FromBase64String($b64)
        [System.Buffer]::BlockCopy($localSidBytes, 0, $bin, 36, 28)
        $inv = New-Object System.Management.ManagementClass("root\LibreHardwareMonitor:__SystemSecurity")
        $p = $inv.GetMethodParameters("SetSD")
        $p.Properties["SD"].Value = $bin
        $res = $inv.InvokeMethod("SetSD", $p, $null)
        Write-Log "[OK] SetSD executado para Monitor (ReturnCode: $($res['ReturnValue']))."
    }
} catch {
    Write-Log "[AVISO] Falha ao definir SetSD: $($_.Exception.Message)"
}

Write-Log "Iniciando loop contínuo de atualização..."
$loopCount = 0
try {
    while ($true) {
        $loopCount++
        foreach ($hw in $computer.Hardware) {
            $hw.Update()
            foreach ($sub in $hw.SubHardware) {
                $sub.Update()
            }
        }
        $wmi.Update()
        if ($loopCount % 60 -eq 1) {
            Write-Log "Loop ativo (ciclo #$loopCount) - WMI atualizado."
        }
        Start-Sleep -Seconds $IntervalSeconds
    }
} catch {
    Write-Log "[ERRO] Erro no ciclo de atualização WMI: $($_.Exception.ToString())"
} finally {
    Write-Log "Finalizando Start-LHMHeadless..."
    if ($wmi) {
        try { $wmi.Dispose() } catch {}
    }
    if ($computer) {
        try { $computer.Close() } catch {}
    }
}
