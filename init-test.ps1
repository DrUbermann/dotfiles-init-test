#!/usr/bin/env pwsh

Write-Output "Starting init-test.ps1" ###############################################

## Equivalent of set -eu
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force

# Use integer value for TLS 1.2 to support .NET 4.0
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]3072

Set-Location ~

## Enable Developer Mode
if (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock") {
    function Test-DeveloperMode {
        $value = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -ErrorAction SilentlyContinue
        return ($value -ne $null -and $value.AllowDevelopmentWithoutDevLicense -eq 1)
    }
    if (-not (Test-DeveloperMode)) {
        $regCmd = "New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowDevelopmentWithoutDevLicense' -PropertyType DWORD -Value 1 -Force"
        Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList $regCmd -Wait
    }
    if (-not (Test-DeveloperMode)) {
        throw "Failed to enable Developer Mode"
    }
}

iex "&{$(irm 'https://get.chezmoi.io/ps1')} init --apply 'https://github.com/DrUbermann/dotfiles-init-test.git'"
#$Env:LGR_LVL_CNSL = 0
## Start a new process so Developer Mode registry change will be read
powershell.exe -ExecutionPolicy RemoteSigned -File "$HOME/chezmoi.tmp/init.ps1"
