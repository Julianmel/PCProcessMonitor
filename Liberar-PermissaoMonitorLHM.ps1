# ============================================================
# LIBERAÇÃO DE PERMISSÃO REMOTA NO WMI DO LIBREHARDWAREMONITOR
# PCProcessMonitor - Liberar-PermissaoMonitorLHM.ps1
# ============================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Solicitando permissões de Administrador..." -ForegroundColor Yellow
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($PSScriptRoot) { "$PSScriptRoot\Liberar-PermissaoMonitorLHM.ps1" } else { "C:\Users\Julian\Dev\PCProcessMonitor\Liberar-PermissaoMonitorLHM.ps1" }
    Start-Process powershell.exe -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-NoExit", "-File", "`"$scriptPath`"") -Verb RunAs
    exit
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Liberando Namespace root\LibreHardwareMonitor para 'Monitor'" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

try {
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

    Write-Host "`n[SUCESSO] Namespace root\LibreHardwareMonitor liberado para o usuário Monitor!" -ForegroundColor Green
    Write-Host "ReturnCode: $($res['ReturnValue'])" -ForegroundColor White
    Write-Host "O coletor no JFMELGACO-1 agora conseguirá ler a temperatura remotamente.`n" -ForegroundColor Green
} catch {
    Write-Error "Erro ao configurar descritor de segurança: $($_.Exception.Message)"
}

Write-Host "Pressione qualquer tecla para fechar..." -ForegroundColor Yellow
try { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") } catch { Read-Host }
