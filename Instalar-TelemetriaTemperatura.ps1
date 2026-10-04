# ============================================================
# HABILITAÇÃO AUTOMATIZADA DE TELEMETRIA TÉRMICA DE HARDWARE
# PCProcessMonitor - Instalar-TelemetriaTemperatura.ps1
# Versão: 2.1 (LibreHardwareMonitor v0.9.4 com WMI Nativo)
# ============================================================

[CmdletBinding()]
param(
    [switch]$Diagnostico,
    [switch]$Desinstalar,
    [switch]$SemElevacao,
    [string]$InstallPath = "C:\Tools\LibreHardwareMonitor"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$taskName = "PCProcessMonitor_LibreHardwareMonitor"
$lhmVersion = "v0.9.4"
$downloadUrl = "https://github.com/LibreHardwareMonitor/LibreHardwareMonitor/releases/download/$lhmVersion/LibreHardwareMonitor-net472.zip"
$networkFallback = "V:\Documents\PCProcessMonitor\Tools\LibreHardwareMonitor"

# Auto-elevação para Administrador caso não seja modo somente-diagnóstico
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $Diagnostico -and -not $SemElevacao) {
    Write-Host "Solicitando permissões de Administrador para configurar serviços de hardware..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) { $scriptPath = "$PSScriptRoot\Instalar-TelemetriaTemperatura.ps1" }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$scriptPath`"" -Verb RunAs
    exit
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Telemetria Térmica de CPU - PCProcessMonitor ($env:COMPUTERNAME)" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

# ------------------------------------------------------------
# ROTINA DE DESINSTALAÇÃO
# ------------------------------------------------------------
if ($Desinstalar) {
    Write-Host "`n[DESINSTALAÇÃO] Removendo LibreHardwareMonitor e Tarefa Agendada..." -ForegroundColor Yellow
    
    # 1. Encerra processo
    Get-Process -Name "LibreHardwareMonitor" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host " -> Processo LibreHardwareMonitor finalizado." -ForegroundColor White

    # 2. Remove tarefa agendada
    if ($isAdmin) {
        try {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
            Write-Host " -> Tarefa Agendada '$taskName' removida." -ForegroundColor White
        } catch {
            & schtasks.exe /Delete /TN $taskName /F 2>$null | Out-Null
        }
    }

    # 3. Remove diretório
    if (Test-Path $InstallPath) {
        Remove-Item -Path $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host " -> Diretório '$InstallPath' excluído." -ForegroundColor White
    }

    Write-Host "`nDesinstalação concluída com sucesso.`n" -ForegroundColor Green
    if (-not $SemElevacao) {
        Write-Host "Pressione qualquer tecla para fechar..." -ForegroundColor Yellow
        try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { Read-Host }
    }
    exit
}

# ------------------------------------------------------------
# ROTINA DE INSTALAÇÃO E CONFIGURAÇÃO
# ------------------------------------------------------------
if (-not $Diagnostico) {
    Write-Host "`n[1/4] Verificando diretório de instalação..." -ForegroundColor Cyan
    if (-not (Test-Path $InstallPath)) {
        New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
        Write-Host "      Diretório criado: $InstallPath" -ForegroundColor White
    } else {
        Write-Host "      Diretório já existe: $InstallPath" -ForegroundColor White
    }

    $exePath = Join-Path $InstallPath "LibreHardwareMonitor.exe"
    if (-not (Test-Path $exePath)) {
        Write-Host "`n[2/4] Obtendo LibreHardwareMonitor $lhmVersion (suporte nativo a WMI)..." -ForegroundColor Cyan
        $zipTemp = Join-Path $env:TEMP "LibreHardwareMonitor-net472.zip"
        $downloaded = $false

        if (Test-Path $networkFallback) {
            Write-Host "      Copiando arquivos pré-carregados da rede ($networkFallback)..." -ForegroundColor Gray
            Copy-Item -Path "$networkFallback\*" -Destination $InstallPath -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path $exePath) { $downloaded = $true }
        }

        if (-not $downloaded) {
            try {
                Write-Host "      Baixando do GitHub ($downloadUrl)..." -ForegroundColor Gray
                Invoke-WebRequest -Uri $downloadUrl -OutFile $zipTemp -UseBasicParsing -TimeoutSec 60 -ErrorAction Stop
                $downloaded = $true
                Write-Host "      Download concluído com sucesso." -ForegroundColor Green
                Expand-Archive -Path $zipTemp -DestinationPath $InstallPath -Force
                Remove-Item -Path $zipTemp -Force -ErrorAction SilentlyContinue
            } catch {
                Write-Warning "      Falha no download via GitHub: $($_.Exception.Message)"
            }
        }

        if (-not (Test-Path $exePath)) {
            Write-Error "Não foi possível obter os arquivos do LibreHardwareMonitor em $InstallPath."
            if (-not $SemElevacao) {
                Write-Host "Pressione qualquer tecla para fechar..." -ForegroundColor Yellow
                try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { Read-Host }
            }
            exit 1
        }
    } else {
        Write-Host "`n[2/4] Binários do LibreHardwareMonitor localizados em $InstallPath." -ForegroundColor Green
    }

    # 3. Configuração de Inicialização Minimizada na Bandeja
    Write-Host "`n[3/4] Gravando preferências (iniciar minimizado na bandeja do sistema)..." -ForegroundColor Cyan
    $cfgPath = Join-Path $InstallPath "LibreHardwareMonitor.config"
    $cfgXml = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
  <appSettings>
    <add key="minTrayMenuItem" value="true" />
    <add key="startMinMenuItem" value="true" />
    <add key="minCloseMenuItem" value="true" />
  </appSettings>
</configuration>
"@
    [System.IO.File]::WriteAllText($cfgPath, $cfgXml, [System.Text.Encoding]::UTF8)
    Write-Host "      Configuração salva em: $cfgPath" -ForegroundColor White

    # 4. Criação da Tarefa Agendada no Windows (Execução com Privilégios Elevados no Logon)
    Write-Host "`n[4/4] Configurando Tarefa Agendada com privilégios elevados..." -ForegroundColor Cyan
    if ($isAdmin) {
        try {
            $action = New-ScheduledTaskAction -Execute $exePath
            $trigger = New-ScheduledTaskTrigger -AtLogOn
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Days 0)
            $null = Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop
            Write-Host "      [OK] Tarefa Agendada '$taskName' registrada com sucesso." -ForegroundColor Green
        } catch {
            Write-Warning "      Tentando método alternativo via schtasks: $($_.Exception.Message)"
            & schtasks.exe /Create /TN $taskName /TR "`"$exePath`"" /SC ONLOGON /RL HIGHEST /F | Out-Host
        }

        # Inicia o processo caso não esteja ativo
        $running = Get-Process -Name "LibreHardwareMonitor" -ErrorAction SilentlyContinue
        if (-not $running) {
            Write-Host "      Iniciando LibreHardwareMonitor..." -ForegroundColor Gray
            try {
                Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
            } catch {
                Start-Process -FilePath $exePath
            }
            Start-Sleep -Seconds 4
        } else {
            Write-Host "      Processo LibreHardwareMonitor já em execução (PID: $($running.Id))." -ForegroundColor White
        }
    } else {
        Write-Host "      [AVISO] Privilégios de Administrador não disponíveis para criar a Tarefa Agendada." -ForegroundColor Yellow
        Write-Host "      Inicie manualmente '$exePath' como Administrador." -ForegroundColor White
    }
}

# ------------------------------------------------------------
# DIAGNÓSTICO AO VIVO DE SENSORES
# ------------------------------------------------------------
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " Diagnóstico de Sensores Térmicos em Tempo Real" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

# 1. LibreHardwareMonitor WMI
Write-Host "`n[Provedor 1] LibreHardwareMonitor (root/LibreHardwareMonitor)..." -ForegroundColor Cyan
try {
    $lhm = Get-CimInstance -Namespace "root/LibreHardwareMonitor" -ClassName "Sensor" -Filter "SensorType='Temperature'" -ErrorAction Stop
    Write-Host "  -> [ATIVO] Sensores de temperatura detectados:" -ForegroundColor Green
    foreach ($s in $lhm) {
        $val = [math]::Round([double]$s.Value, 1)
        Write-Host "     * $($s.Name) ($($s.SensorType)): $val °C" -ForegroundColor White
    }
} catch {
    Write-Host "  -> [INATIVO] Provedor root/LibreHardwareMonitor não retornou dados no momento." -ForegroundColor Yellow
    Write-Host "     Verifique se o processo está em execução como Administrador." -ForegroundColor Gray
}

# 2. OpenHardwareMonitor WMI
Write-Host "`n[Provedor 2] OpenHardwareMonitor (root/OpenHardwareMonitor)..." -ForegroundColor Cyan
try {
    $ohm = Get-CimInstance -Namespace "root/OpenHardwareMonitor" -ClassName "Sensor" -Filter "SensorType='Temperature'" -ErrorAction Stop
    Write-Host "  -> [ATIVO] Sensores detectados:" -ForegroundColor Green
    foreach ($s in $ohm) {
        $val = [math]::Round([double]$s.Value, 1)
        Write-Host "     * $($s.Name): $val °C" -ForegroundColor White
    }
} catch {
    Write-Host "  -> [INATIVO] Provedor root/OpenHardwareMonitor não ativo." -ForegroundColor Gray
}

# 3. ACPI Nativo
Write-Host "`n[Provedor 3] ACPI Nativo (root/wmi:MSAcpi_ThermalZoneTemperature)..." -ForegroundColor Cyan
try {
    $tz = Get-CimInstance -Namespace "root/wmi" -ClassName "MSAcpi_ThermalZoneTemperature" -ErrorAction Stop
    Write-Host "  -> [ATIVO] Zonas térmicas ACPI detectadas:" -ForegroundColor Green
    foreach ($z in $tz) {
        $c = [math]::Round(($z.CurrentTemperature - 2732) / 10, 1)
        $isStatic = if ($z.CurrentTemperature -eq 2982) { " (Constante estática de 25°C da BIOS Dell)" } else { "" }
        Write-Host "     * $($z.InstanceName): $c °C$isStatic" -ForegroundColor White
    }
} catch {
    Write-Host "  -> [INATIVO] Placa-mãe não expõe interface genérica ACPI ThermalZone." -ForegroundColor Gray
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " Conclusão do Diagnóstico:" -ForegroundColor Green
Write-Host " O coletor Monitor-Rede.ps1 prioriza automaticamente os sensores" -ForegroundColor White
Write-Host " de CPU Core / Package do LibreHardwareMonitor em tempo real." -ForegroundColor White
Write-Host "============================================================`n" -ForegroundColor Cyan

if (-not $SemElevacao) {
    Write-Host "Pressione qualquer tecla para fechar esta janela..." -ForegroundColor Yellow
    try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { Read-Host }
}
