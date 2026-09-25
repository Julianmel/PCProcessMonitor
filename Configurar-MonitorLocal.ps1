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
    Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Public' -and ($_.Name -like '*TECHNOFLORA*' -or $_.InterfaceAlias -match 'Wi-Fi|Ethernet') } | ForEach-Object {
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

# 5. Concede permissão Remote Enable no WMI (root e root\cimv2)
Write-Host "`n[5/8] Concedendo permissões remotas WMI (root e root\cimv2)..." -ForegroundColor Cyan
$namespaces = @("root", "root\cimv2")
foreach ($ns in $namespaces) {
    try {
        $invClass = New-Object System.Management.ManagementClass("$($ns):__SystemSecurity")
        $outParams = $invClass.InvokeMethod("GetSD", $null, $null)
        $binarySD = $outParams["SD"]

        $sd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($false, $false, $binarySD, 0)
        $sid = (New-Object System.Security.Principal.NTAccount("Monitor")).Translate([System.Security.Principal.SecurityIdentifier])

        # 131107 = Enable (1) + Method Execute (2) + Remote Access (32) + Read Perm (131072)
        $sd.DiscretionaryAcl.SetAccess(
            [System.Security.AccessControl.AccessControlType]::Allow,
            $sid,
            131107,
            [System.Security.AccessControl.InheritanceFlags]::None,
            [System.Security.AccessControl.PropagationFlags]::None
        )

        $newBinarySD = New-Object byte[] ($sd.BinaryLength)
        $sd.GetBinaryForm($newBinarySD, 0)

        $inParams = $invClass.GetMethodParameters("SetSD")
        $inParams.Properties["SD"].Value = $newBinarySD
        $res = $invClass.InvokeMethod("SetSD", $inParams, $null)
        Write-Host "      [OK] Permissão WMI concedida em '$ns' (ReturnCode: $($res['ReturnValue']))" -ForegroundColor Green
    } catch {
        Write-Warning "      [AVISO] Erro ao ajustar WMI em '$ns': $($_.Exception.Message)"
    }
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

# 8. Reinicia os serviços para limpar cache de segurança
Write-Host "`n[8/8] Reiniciando serviços Winmgmt e WinRM para atualizar cache de segurança..." -ForegroundColor Cyan
try {
    Restart-Service winmgmt -Force -ErrorAction SilentlyContinue
    Restart-Service WinRM -Force -ErrorAction SilentlyContinue
    Write-Host "      Serviços reiniciados com sucesso! Caches renovados." -ForegroundColor Green
} catch {
    Write-Warning "      Aviso ao reiniciar serviços: $($_.Exception.Message)"
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " CONFIGURAÇÃO CONCLUÍDA COM SUCESSO!" -ForegroundColor Green
Write-Host " O JFMELGACO3 agora permite conexões de telemetria do Monitor." -ForegroundColor Green
Write-Host " O script no JFMELGACO-1 passará a mostrar ONLINE automaticamente." -ForegroundColor White
Write-Host "============================================================`n" -ForegroundColor Cyan

Stop-Transcript -ErrorAction SilentlyContinue | Out-Null

Write-Host "Pressione qualquer tecla para fechar..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
