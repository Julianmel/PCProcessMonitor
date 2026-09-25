# ============================================================
# CONFIGURAR USUÁRIO MONITOR LOCALMENTE (JFMELGACO3)
# Execute este script como Administrador no PowerShell do JFMELGACO3
# ============================================================

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Este script precisa ser executado como Administrador!"
    Write-Warning "Abra o PowerShell como Administrador e execute: .\Configurar-MonitorLocal.ps1"
    pause
    return
}

Write-Host "[1/3] Criando usuário Monitor (sem direitos administrativos)..." -ForegroundColor Cyan
net user Monitor Monitor2026@ /add /expires:never /comment:"Usuario de Telemetria PCProcessMonitor"

Write-Host "`n[2/3] Adicionando aos grupos de telemetria..." -ForegroundColor Cyan
$groups = @(
    "Usuários do Monitor de Desempenho",
    "Usuários do COM Distribuído",
    "Usuários de Gerenciamento Remoto",
    "Performance Monitor Users",
    "Distributed COM Users",
    "Remote Management Users"
)

foreach ($g in $groups) {
    net localgroup "$g" Monitor /add 2>$null
}

Write-Host "`n[3/3] Aplicando permissão de Remote Enable no WMI (root\cimv2)..." -ForegroundColor Cyan
try {
    $invClass = New-Object System.Management.ManagementClass("root\cimv2:__SystemSecurity")
    $outParams = $invClass.InvokeMethod("GetSD", $null, $null)
    $binarySD = $outParams["SD"]

    $sd = New-Object System.Security.AccessControl.CommonSecurityDescriptor($false, $false, $binarySD, 0)
    $sid = (New-Object System.Security.Principal.NTAccount("Monitor")).Translate([System.Security.Principal.SecurityIdentifier])

    # 131107 = Enable (1) + Method Execute (2) + Remote Access (32) + Read Perm (131072)
    $sd.DiscretionaryAcl.AddAccess([System.Security.AccessControl.AccessControlType]::Allow, $sid, 131107, [System.Security.AccessControl.InheritanceFlags]::None, [System.Security.AccessControl.PropagationFlags]::None)

    $newBinarySD = New-Object byte[] ($sd.BinaryLength)
    $sd.GetBinaryForm($newBinarySD, 0)

    $inParams = $invClass.GetMethodParameters("SetSD")
    $inParams.Properties["SD"].Value = $newBinarySD
    $res = $invClass.InvokeMethod("SetSD", $inParams, $null)
    Write-Host "Permissão WMI concedida com sucesso! ReturnCode: $($res['ReturnValue'])" -ForegroundColor Green
} catch {
    Write-Warning "Erro ao ajustar WMI: $($_.Exception.Message)"
}

Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host " Concluído! O usuário Monitor está configurado no JFMELGACO3." -ForegroundColor Green
Write-Host "============================================================`n" -ForegroundColor Cyan
