#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string[]]$AllowedSshRemoteAddress = @('Any')
)

$ErrorActionPreference = 'Stop'
$DeploymentRoot = 'C:\cicd-python-demo'

Write-Host '==> Preparing Windows 11 host for CI/CD deployment' -ForegroundColor Cyan

$OpenSshCapability = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
if ($OpenSshCapability.State -ne 'Installed') {
    Write-Host 'Installing OpenSSH Server...'
    Add-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' | Out-Null
}

Set-Service -Name sshd -StartupType Automatic
Start-Service -Name sshd

$FirewallRuleName = 'CI-CD-SSH-In-TCP'
$FirewallRule = Get-NetFirewallRule -Name $FirewallRuleName -ErrorAction SilentlyContinue
if (-not $FirewallRule) {
    New-NetFirewallRule `
        -Name $FirewallRuleName `
        -DisplayName 'CI/CD SSH access to Windows 11' `
        -Enabled True `
        -Direction Inbound `
        -Protocol TCP `
        -Action Allow `
        -LocalPort 22 `
        -RemoteAddress $AllowedSshRemoteAddress | Out-Null
}
else {
    Set-NetFirewallRule -Name $FirewallRuleName -Enabled True | Out-Null
    $FirewallRule | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -LocalPort 22 | Out-Null
    $FirewallRule | Get-NetFirewallAddressFilter | Set-NetFirewallAddressFilter -RemoteAddress $AllowedSshRemoteAddress | Out-Null
}

New-Item -ItemType Directory -Force -Path @(
    (Join-Path $DeploymentRoot 'scripts'),
    (Join-Path $DeploymentRoot 'envs'),
    (Join-Path $DeploymentRoot 'state')
) | Out-Null

$CurrentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$Grant = '{0}:(OI)(CI)M' -f $CurrentIdentity
& icacls.exe $DeploymentRoot /grant $Grant /T | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw 'Could not grant deployment directory permissions to the current account.'
}

Write-Host "OpenSSH service: $((Get-Service sshd).Status)"
Write-Host "SSH port: 22 (default)"
Write-Host "Allowed SSH remote addresses: $($AllowedSshRemoteAddress -join ', ')"
Write-Host "Deployment directory: $DeploymentRoot"
Write-Host "Modify permission granted to: $CurrentIdentity"

if ($AllowedSshRemoteAddress -contains 'Any') {
    Write-Warning 'The SSH firewall rule currently allows any remote IP. Restrict this before exposing the server to the Internet.'
}

$DockerCommand = Get-Command docker -ErrorAction SilentlyContinue
if ($DockerCommand) {
    Write-Host 'Docker CLI found. Checking Docker Engine...'
    & docker version
    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'Docker CLI exists but Engine is not available. Start Docker Desktop in this user session.'
    }
}
else {
    Write-Warning 'Docker CLI was not found. Install Docker Desktop, enable WSL 2/Linux containers, then sign in with the deployment account.'
}

Write-Host 'Bootstrap completed. Add an SSH public key to authorized_keys and verify remote connectivity next.' -ForegroundColor Green
