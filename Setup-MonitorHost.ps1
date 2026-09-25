# ============================================================
# CONFIGURADOR DE NÓ DE REDE PARA MONITORAMENTO (JFMELGACO)
# PCProcessMonitor - Setup-MonitorHost.ps1 (v1.0.2)
# ============================================================
# Execute este script como Administrador em qualquer notebook
# da rede para habilitar a monitoração remota bidirecional.
# ============================================================

# Requere privilégios de Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Este script precisa ser executado como Administrador!"
    Write-Warning "Clique com o botão direito no PowerShell e selecione 'Executar como Administrador'."
    pause
    return
}

Write-Host "`n[1/5] Habilitando serviço WinRM e PowerShell Remoting..." -ForegroundColor Cyan
try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction SilentlyContinue
    Start-Service WinRM -ErrorAction SilentlyContinue
    Set-Service WinRM -StartupType Automatic
    Write-Host "      WinRM habilitado com sucesso e configurado para inicialização automática." -ForegroundColor Green
} catch {
    Write-Warning "      Erro ao habilitar WinRM: $($_.Exception.Message)"
}

Write-Host "`n[2/5] Configurando TrustedHosts no cliente WinRM..." -ForegroundColor Cyan
try {
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
    Write-Host "      TrustedHosts configurado como '*' (permite consultas remotas em Workgroup)." -ForegroundColor Green
} catch {
    Write-Warning "      Erro ao configurar TrustedHosts: $($_.Exception.Message)"
}

Write-Host "`n[3/5] Ajustando política de token de contas locais (Workgroup UAC Filter)..." -ForegroundColor Cyan
try {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    New-ItemProperty -Path $regPath -Name "LocalAccountTokenFilterPolicy" -Value 1 -PropertyType DWord -Force | Out-Null
    Write-Host "      LocalAccountTokenFilterPolicy habilitado (permite WMI/CIM com contas de administrador local)." -ForegroundColor Green
} catch {
    Write-Warning "      Erro ao registrar LocalAccountTokenFilterPolicy: $($_.Exception.Message)"
}

Write-Host "`n[4/5] Liberando regras do Firewall do Windows..." -ForegroundColor Cyan
try {
    # 4.1 WinRM HTTP porta 5985 para todos os perfis (incluindo público)
    netsh advfirewall firewall delete rule name="PCProcessMonitor-WinRM-In" | Out-Null
    netsh advfirewall firewall add rule name="PCProcessMonitor-WinRM-In" dir=in action=allow protocol=TCP localport=5985 profile=any description="Acesso WinRM para PCProcessMonitor" | Out-Null
    Write-Host "      Regra de Firewall: Porta 5985 TCP liberada em todos os perfis." -ForegroundColor Green

    # 4.2 ICMPv4 Echo Request (Ping) para detecção rápida de nós
    netsh advfirewall firewall delete rule name="PCProcessMonitor-ICMPv4-Echo-In" | Out-Null
    netsh advfirewall firewall add rule name="PCProcessMonitor-ICMPv4-Echo-In" dir=in action=allow protocol=icmpv4:8,any profile=any description="Resposta ao Ping ICMPv4 para PCProcessMonitor" | Out-Null
    Write-Host "      Regra de Firewall: Resposta ao Ping ICMPv4 liberada." -ForegroundColor Green
} catch {
    Write-Warning "      Erro ao configurar regras de firewall: $($_.Exception.Message)"
}

Write-Host "`n[5/5] Verificação final dos serviços e ouvintes..." -ForegroundColor Cyan
$svc = Get-Service WinRM
Write-Host "      Status do Serviço WinRM: $($svc.Status)" -ForegroundColor $(if ($svc.Status -eq 'Running') { 'Green' } else { 'Yellow' })
$th = (Get-Item WSMan:\localhost\Client\TrustedHosts).Value
Write-Host "      TrustedHosts: $th" -ForegroundColor Green

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " Configuração concluída! Este computador está pronto para:" -ForegroundColor Green
Write-Host " 1. Ser monitorado por outros computadores da rede." -ForegroundColor White
Write-Host " 2. Monitorar outros computadores da rede via Monitor-Rede.ps1." -ForegroundColor White
Write-Host "============================================================`n" -ForegroundColor Cyan
