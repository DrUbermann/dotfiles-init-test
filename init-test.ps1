#!/usr/bin/env pwsh

Write-Output "Starting init-test.ps1" ###############################################

## Equivalent of set -eu
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ((New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Runnig as Administrator is not required, exiting."
    exit 1
}

Set-Location ~

$url_dotfiles = 'https://github.com/DrUbermann/dotfiles-init-test.git'

if ([System.Environment]::OSVersion.Version.Major -ge 10 -and $Host.Version.Major -ge 3) {
    Invoke-Expression "&{$(Invoke-RestMethod 'https://get.chezmoi.io/ps1')} init --apply $url_dotfiles"
} else {

# & ([scriptblock]::Create((New-Object Net.WebClient).DownloadString('https://get.chezmoi.io/ps1'))) init --apply $url_dotfiles

$regPath = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
$netKey = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
if ($null -eq $netKey -or $netKey.Release -lt 528040) {
    Write-Error "Upgrade to .NET 4.8 or later."
    exit 1
}

if ($PSVersionTable.CLRVersion.Major -lt 4) {
    [void](New-Object -ComObject Wscript.Shell).Popup("PowerShell is bound to CLR $($PSVersionTable.CLRVersion) (.NET 2.0/3.5), even if .NET 4.8 is installed on this machine.  Fixing this requires installing config files for powershell and re-launching.`n`nPlease click OK on the administrator prompt that is about to appear.", 0x00, "Privilege Escalation Required", 0x40)

    $tmpScript = Join-Path $env:TEMP "ApplyBindings_Worker.ps1"
    @"
`$configXml = '<?xml version="1.0"?><configuration><startup useLegacyV2RuntimeActivationPolicy="true"><supportedRuntime version="v4.0"/></startup></configuration>'
`$paths = @("`$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe.config", "`$env:WINDIR\SysWOW64\WindowsPowerShell\v1.0\powershell.exe.config")
foreach (`$path in `$paths) {
    if (Test-Path (Split-Path `$path)) {
        Set-Content -Path `$path -Value `$configXml -Encoding ASCII
    }
}
"@ | Out-File -FilePath $tmpScript -Encoding ASCII

    Write-Host "Interactive: $([Environment]::UserInteractive)"
    Write-Host "CWD: $(Get-Location)"
    Write-Host "tmpScript = $tmpScript"
    Start-Process powershell.exe -Wait -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:\Users\Alexander\Documents\test.ps1" #-WindowStyle Hidden
    Remove-Item $tmpScript -ErrorAction SilentlyContinue

    Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $MyInvocation.MyCommand.Path
    exit
}

$client = New-Object System.Net.WebClient
$client.Headers.Add('Authorization', "Basic $creds")
Invoke-Expression $client.DownloadString('https://dotfiles-init-test.drubermann.workers.dev/.excu/chezmoi-install-legacy.ps1')

}

#$Env:LGR_LVL_CNSL = 0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$HOME/chezmoi.tmp/init.ps1"
