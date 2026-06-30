#!/usr/bin/env pwsh

Write-Output "Starting init-test.ps1" ###############################################

## Equivalent of set -eu
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
exit
if ((New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Running as Administrator is not required, exiting."
    exit 1
}

Set-Location ~

Invoke-Expression "&{$(Invoke-RestMethod 'https://get.chezmoi.io/ps1')} init --apply https://github.com/DrUbermann/dotfiles-init-test.git"

#$Env:LGR_LVL_CNSL = 0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$HOME\chezmoi.tmp\init.ps1"
