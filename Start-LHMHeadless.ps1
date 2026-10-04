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

$dllPath = Join-Path $InstallPath "LibreHardwareMonitorLib.dll"
$exePath = Join-Path $InstallPath "LibreHardwareMonitor.exe"

if (-not (Test-Path $dllPath) -or -not (Test-Path $exePath)) {
    Write-Error "Bibliotecas do LibreHardwareMonitor não encontradas em $InstallPath"
    exit 1
}

try {
    $null = [System.Reflection.Assembly]::LoadFrom($dllPath)
    $null = [System.Reflection.Assembly]::LoadFrom($exePath)
} catch {
    Write-Error "Falha ao carregar assemblies: $($_.Exception.Message)"
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
    $computer.Open()
} catch {
    Write-Error "Falha ao abrir Computer: $($_.Exception.Message)"
    exit 1
}

$wmi = $null
try {
    $wmi = New-Object LibreHardwareMonitor.Wmi.WmiProvider($computer)
} catch {
    Write-Error "Falha ao instanciar WmiProvider: $($_.Exception.Message)"
    $computer.Close()
    exit 1
}

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
        $null = $inv.InvokeMethod("SetSD", $p, $null)
    }
} catch {}

try {
    while ($true) {
        foreach ($hw in $computer.Hardware) {
            $hw.Update()
            foreach ($sub in $hw.SubHardware) {
                $sub.Update()
            }
        }
        $wmi.Update()
        Start-Sleep -Seconds $IntervalSeconds
    }
} catch {
    Write-Error "Erro no ciclo de atualização WMI: $($_.Exception.Message)"
} finally {
    if ($wmi) {
        try { $wmi.Dispose() } catch {}
    }
    if ($computer) {
        try { $computer.Close() } catch {}
    }
}
