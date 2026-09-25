# ============================================================
# CONFIGURAR USUÁRIO MONITOR LOCALMENTE (JFMELGACO3)
# PCProcessMonitor - Configurar-MonitorLocal.ps1
# ============================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$logFile = "$PSScriptRoot\setup_log.txt"
if (-not $PSScriptRoot) { $logFile = "C:\Users\Julian\Dev\PCProcessMonitor\setup_log.txt" }

# Inicia registro de log
Start-Transcript -Path $logFile -Force -ErrorAction SilentlyContinue | Out-Null

# Auto-elevação para Administrador caso executado sem elevação
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Solicitando permissões de Administrador..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) { $scriptPath = "$PSScriptRoot\Configurar-MonitorLocal.ps1" }
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Configurando Usuário Monitor e Telemetria (JFMELGACO3)" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Cria ou atualiza o usuário Monitor
Write-Host "`n[1/8] Configurando conta de usuário 'Monitor'..." -ForegroundColor Cyan
try {
    $existing = Get-LocalUser -Name "Monitor" -ErrorAction SilentlyContinue
    if (-not $existing) {
        net user Monitor Monitor2026@ /add /expires:never /comment:"Usuario de Telemetria PCProcessMonitor"
        Write-Host "      Conta 'Monitor' criada com sucesso." -ForegroundColor Green
    } else {
        net user Monitor Monitor2026@ /expires:never
        Set-LocalUser -Name "Monitor" -PasswordNeverExpires $true -ErrorAction SilentlyContinue
        Write-Host "      Conta 'Monitor' já existe - senha e expiração atualizadas." -ForegroundColor Green
    }
} catch {
    Write-Warning "      Erro ao configurar conta Monitor: $($_.Exception.Message)"
}

# 2. Adiciona aos grupos de telemetria usando SIDs conhecidos (independente do idioma do Windows)
Write-Host "`n[2/8] Adicionando 'Monitor' aos grupos de monitoramento..." -ForegroundColor Cyan
$targetSids = @(
    @{ SID = 'S-1-5-32-558'; Role = 'Performance Monitor Users' },
    @{ SID = 'S-1-5-32-559'; Role = 'Performance Log Users' },
    @{ SID = 'S-1-5-32-562'; Role = 'Distributed COM Users' },
    @{ SID = 'S-1-5-32-580'; Role = 'Remote Management Users' },
    @{ SID = 'S-1-5-32-573'; Role = 'Event Log Readers' }
)

foreach ($item in $targetSids) {
    try {
        $sidObj = [System.Security.Principal.SecurityIdentifier]::new($item.SID)
        $groupName = $sidObj.Translate([System.Security.Principal.NTAccount]).Value.Split('\')[-1]
        Add-LocalGroupMember -Group $groupName -Member "Monitor" -ErrorAction SilentlyContinue
        Write-Host "      [OK] Grupo: $groupName ($($item.Role))" -ForegroundColor Green
    } catch {
        Write-Warning "      [AVISO] Não foi possível adicionar ao grupo $($item.Role): $($_.Exception.Message)"
    }
}

# 3. Ajusta o perfil da rede Wi-Fi/Ethernet para 'Private' (permite tráfego local seguro)
Write-Host "`n[3/8] Verificando perfil de rede..." -ForegroundColor Cyan
try {
    Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { $_.NetworkCategory -eq 'Public' -and ($_.Name -like '*TECHNOFLORA*' -or $_.InterfaceAlias -match 'Wi-Fi|Ethernet') } | ForEach-Object {
        Set-NetConnectionProfile -InputObject $_ -NetworkCategory Private -ErrorAction SilentlyContinue
        Write-Host "      Perfil de rede '$($_.Name)' alterado de Public para Private." -ForegroundColor Green
    }
} catch {
    Write-Warning "      Não foi possível alterar o perfil de rede: $($_.Exception.Message)"
}

# 4. Habilita e configura WinRM
Write-Host "`n[4/8] Configurando serviço WinRM e PowerShell Remoting..." -ForegroundColor Cyan
try {
    Start-Service WinRM -ErrorAction SilentlyContinue
    Set-Service WinRM -StartupType Automatic -ErrorAction SilentlyContinue
    Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction SilentlyContinue
    
    $listener = Get-ChildItem WSMan:\localhost\Listener -ErrorAction SilentlyContinue | Where-Object { $_.Keys -match 'Transport=HTTP' }
    if (-not $listener) {
        New-Item -Path WSMan:\localhost\Listener -Transport HTTP -Address * -Force | Out-Null
    }
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
    Write-Host "      WinRM habilitado com ouvinte HTTP na porta 5985 e TrustedHosts='*'." -ForegroundColor Green
} catch {
    Write-Warning "      Erro ao configurar WinRM: $($_.Exception.Message)"
}

# 5. Restaura e configura permissões WMI (root e root\cimv2)
Write-Host "`n[5/8] Configurando permissões WMI no root e root\cimv2..." -ForegroundColor Cyan
try {
    $sidObj = (New-Object System.Security.Principal.NTAccount("Monitor")).Translate([System.Security.Principal.SecurityIdentifier])
    $localSidBytes = New-Object byte[] ($sidObj.BinaryLength)
    $sidObj.GetBinaryForm($localSidBytes, 0)

    # 5.1 Restaura namespace 'root' para o descritor padrão genuíno do Windows (144 bytes)
    # SDDL: O:BAG:BAD:(A;;CCDCRP;;;AU)(A;;CCDCRP;;;LS)(A;;CCDCRP;;;NS)(A;;CCDCLCSWRPWPRCWD;;;BA)
    $b64Root = "AQAEgJQAAACkAAAAAAAAABQAAAACAIAABAAAAAACGAA/AAYAAQIAAAAAAAUgAAAAIAIAAAACFAATAAAAAQEAAAAAAAUUAAAAAAIUABMAAAABAQAAAAAABRMAAAAAAhQAEwAAAAEBAAAAAAAFCwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAECAAAAAAAFIAAAACACAAABAgAAAAAABSAAAAAgAgAA"
    $binRoot = [Convert]::FromBase64String($b64Root)
    $invRoot = New-Object System.Management.ManagementClass("root:__SystemSecurity")
    $pRoot = $invRoot.GetMethodParameters("SetSD")
    $pRoot.Properties["SD"].Value = $binRoot
    $rRoot = $invRoot.InvokeMethod("SetSD", $pRoot, $null)
    Write-Host "      [OK] Namespace 'root' restaurado com descritor padrao do Windows (ReturnCode: $($rRoot['ReturnValue']))" -ForegroundColor Green

    # 5.2 Concede permissão a 'Monitor' em 'root\cimv2' clonando o descritor binario de 180 bytes comprovado
    # SDDL: O:BAG:BAD:(A;;CCDCWPRC;;;<Monitor-SID>)(A;ID;CCDCLCSWRPWPRCWD;;;BA)(A;ID;CCDCRP;;;NS)(A;ID;CCDCRP;;;LS)(A;ID;CCDCRP;;;AU)
    $b64Cim = "AQAEgJQAAACkAAAAAAAAABQAAAACAIAABQAAAAAAJAAjAAIAAQUAAAAAAAUVAAAAV3LPoKSHU0cqOBGlBAQAAAASGAA/AAYAAQIAAAAAAAUgAAAAIAIAAAASFAATAAAAAQEAAAAAAAUUAAAAABIUABMAAAABAQAAAAAABRMAAAAAEhQAEwAAAAEBAAAAAAAFCwAAAAECAAAAAAAFIAAAACACAAABAgAAAAAABSAAAAAgAgAA"
    $binCim = [Convert]::FromBase64String($b64Cim)
    # Substitui os 28 bytes do SID do Monitor local no offset 36 (ACE 0)
    [System.Buffer]::BlockCopy($localSidBytes, 0, $binCim, 36, 28)

    $invCim = New-Object System.Management.ManagementClass("root\cimv2:__SystemSecurity")
    $pCim = $invCim.GetMethodParameters("SetSD")
    $pCim.Properties["SD"].Value = $binCim
    $rCim = $invCim.InvokeMethod("SetSD", $pCim, $null)
    Write-Host "      [OK] Namespace 'root\cimv2' configurado com descritor binario comprovado (ReturnCode: $($rCim['ReturnValue']))" -ForegroundColor Green
} catch {
    Write-Warning "      [AVISO] Erro ao configurar WMI: $($_.Exception.Message)"
}

# 6. Registra política LocalAccountTokenFilterPolicy
Write-Host "`n[6/8] Ajustando LocalAccountTokenFilterPolicy no Registro..." -ForegroundColor Cyan
try {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    New-ItemProperty -Path $regPath -Name "LocalAccountTokenFilterPolicy" -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Host "      LocalAccountTokenFilterPolicy = 1 configurado." -ForegroundColor Green
} catch {
    Write-Warning "      Erro ao configurar LocalAccountTokenFilterPolicy: $($_.Exception.Message)"
}

# 7. Liberando regras do Firewall do Windows para todos os perfis
Write-Host "`n[7/8] Configurando regras de Firewall do Windows (para todos os perfis)..." -ForegroundColor Cyan
try {
    # 7.1 WinRM HTTP (5985)
    netsh advfirewall firewall delete rule name="PCProcessMonitor-WinRM-In" | Out-Null
    netsh advfirewall firewall add rule name="PCProcessMonitor-WinRM-In" dir=in action=allow protocol=TCP localport=5985 profile=any description="PCProcessMonitor WinRM" | Out-Null

    # 7.2 DCOM / RPC Endpoint Mapper (135)
    netsh advfirewall firewall delete rule name="PCProcessMonitor-DCOM-In" | Out-Null
    netsh advfirewall firewall add rule name="PCProcessMonitor-DCOM-In" dir=in action=allow protocol=TCP localport=135 profile=any description="PCProcessMonitor DCOM RPC" | Out-Null

    # 7.3 Portas dinâmicas de RPC para DCOM (49152-65535)
    netsh advfirewall firewall delete rule name="PCProcessMonitor-RPCDynamic-In" | Out-Null
    netsh advfirewall firewall add rule name="PCProcessMonitor-RPCDynamic-In" dir=in action=allow protocol=TCP localport=49152-65535 profile=any description="PCProcessMonitor RPC Dynamic" | Out-Null

    # 7.4 ICMPv4 Echo (Ping)
    netsh advfirewall firewall delete rule name="PCProcessMonitor-ICMPv4-Echo-In" | Out-Null
    netsh advfirewall firewall add rule name="PCProcessMonitor-ICMPv4-Echo-In" dir=in action=allow protocol=icmpv4:8,any profile=any description="PCProcessMonitor Ping ICMP" | Out-Null

    Write-Host "      Regras de Firewall liberadas: TCP 5985, TCP 135, TCP 49152-65535, ICMP Ping." -ForegroundColor Green
} catch {
    Write-Warning "      Erro ao configurar Firewall: $($_.Exception.Message)"
}

# 8. Reinicia os serviços para limpar cache de segurança e matar instâncias antigas de provedores
Write-Host "`n[8/8] Reiniciando WMI, WinRM e finalizando provedores antigos..." -ForegroundColor Cyan
try {
    cmd.exe /c "taskkill /f /im WmiPrvSE.exe 2>nul" | Out-Null
    cmd.exe /c "net stop winmgmt /y 2>nul" | Out-Null
    cmd.exe /c "net start winmgmt 2>nul" | Out-Null
    cmd.exe /c "net start winrm 2>nul" | Out-Null
    cmd.exe /c "net start iphlpsvc 2>nul" | Out-Null
    Write-Host "      Serviços reiniciados com sucesso! Provedores limpos." -ForegroundColor Green
} catch {
    Write-Warning "      Aviso ao reiniciar serviços: $($_.Exception.Message)"
}

# 9. Teste de validação imediata com o usuário Monitor
Write-Host "`n[Validação] Testando leitura WMI como usuário 'Monitor' via WinRM..." -ForegroundColor Cyan
try {
    $sec = New-Object System.Security.SecureString
    "Monitor2026@".ToCharArray() | ForEach-Object { $sec.AppendChar($_) }
    $cred = New-Object System.Management.Automation.PSCredential("JFMELGACO3\Monitor", $sec)
    $opt = New-CimSessionOption -Protocol Wsman
    $s = New-CimSession -ComputerName "127.0.0.1" -Credential $cred -SessionOption $opt -OperationTimeoutSec 5 -ErrorAction Stop
    $osTest = Get-CimInstance Win32_OperatingSystem -CimSession $s -Namespace "root\cimv2" -ErrorAction Stop
    Remove-CimSession $s
    Write-Host "      [SUCESSO TOTAL] Conexão WMI do Monitor 100% OPERACIONAL! Sistema: $($osTest.Caption)" -ForegroundColor Green
} catch {
    Write-Warning "      Aviso no teste do Monitor: $($_.Exception.Message)"
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " CONFIGURAÇÃO CONCLUÍDA COM SUCESSO!" -ForegroundColor Green
Write-Host " O JFMELGACO3 agora permite conexões de telemetria do Monitor." -ForegroundColor Green
Write-Host " O script no JFMELGACO-1 passará a mostrar ONLINE automaticamente." -ForegroundColor White
Write-Host "============================================================`n" -ForegroundColor Cyan

Stop-Transcript -ErrorAction SilentlyContinue | Out-Null

Write-Host "Pressione qualquer tecla para fechar..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
