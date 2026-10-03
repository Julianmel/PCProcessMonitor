# ============================================================
# HABILITAÇÃO DE TELEMETRIA TÉRMICA DE HARDWARE (DTS / CPU)
# PCProcessMonitor - Instalar-TelemetriaTemperatura.ps1
# ============================================================
# Este script documenta e verifica a disponibilidade de sensores
# térmicos em computadores da rede local (JFMELGACO).
# ============================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Diagnóstico de Sensores Térmicos ($env:COMPUTERNAME)" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Verifica LibreHardwareMonitor WMI
Write-Host "`n[1/3] Verificando provedor LibreHardwareMonitor (root/LibreHardwareMonitor)..." -ForegroundColor Cyan
try {
    $lhm = Get-CimInstance -Namespace "root/LibreHardwareMonitor" -ClassName "Sensor" -Filter "SensorType='Temperature'" -ErrorAction Stop
    Write-Host "      [OK] Provedor ativo! Sensores identificados:" -ForegroundColor Green
    foreach ($s in $lhm) {
        Write-Host "           -> $($s.Name): $($s.Value) °C" -ForegroundColor White
    }
} catch {
    Write-Host "      [INFO] LibreHardwareMonitor não ativo neste nó." -ForegroundColor Yellow
}

# 2. Verifica OpenHardwareMonitor WMI
Write-Host "`n[2/3] Verificando provedor OpenHardwareMonitor (root/OpenHardwareMonitor)..." -ForegroundColor Cyan
try {
    $ohm = Get-CimInstance -Namespace "root/OpenHardwareMonitor" -ClassName "Sensor" -Filter "SensorType='Temperature'" -ErrorAction Stop
    Write-Host "      [OK] Provedor ativo! Sensores identificados:" -ForegroundColor Green
    foreach ($s in $ohm) {
        Write-Host "           -> $($s.Name): $($s.Value) °C" -ForegroundColor White
    }
} catch {
    Write-Host "      [INFO] OpenHardwareMonitor não ativo neste nó." -ForegroundColor Yellow
}

# 3. Verifica ACPI Nativo do Windows
Write-Host "`n[3/3] Verificando provedor ACPI Nativo (root/wmi:MSAcpi_ThermalZoneTemperature)..." -ForegroundColor Cyan
try {
    $tz = Get-CimInstance -Namespace "root/wmi" -ClassName "MSAcpi_ThermalZoneTemperature" -ErrorAction Stop
    Write-Host "      [OK] Zonas térmicas ACPI detectadas:" -ForegroundColor Green
    foreach ($z in $tz) {
        $c = [math]::Round(($z.CurrentTemperature - 2732) / 10, 1)
        $isStatic = if ($z.CurrentTemperature -eq 2982) { " (Constante estática 25°C da BIOS Dell)" } else { "" }
        Write-Host "           -> $($z.InstanceName): $c °C$isStatic" -ForegroundColor White
    }
} catch {
    Write-Host "      [INFO] ACPI ThermalZone genérico não exposto pela BIOS da placa-mãe (comum em desktops de consumidor)." -ForegroundColor Gray
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " Recomendação para nós sem sensor nativo:" -ForegroundColor Yellow
Write-Host " Baixar LibreHardwareMonitor (portátil), marcar em 'Options':" -ForegroundColor White
Write-Host "  [X] Run on Windows Startup" -ForegroundColor White
Write-Host "  [X] Minimize to System Tray" -ForegroundColor White
Write-Host "  [X] WMI Provider" -ForegroundColor White
Write-Host "============================================================`n" -ForegroundColor Cyan
