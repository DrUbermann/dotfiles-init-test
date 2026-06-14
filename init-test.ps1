#!/usr/bin/env pwsh

Write-Output "Starting init-test.ps1" ###############################################

## Equivalent of set -eu
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

#Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

## Use integer value for TLS 1.2 to support .NET 4.0
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]3072

Set-Location ~

#Invoke-Expression "&{$(Invoke-RestMethod 'https://get.chezmoi.io/ps1')} init --apply 'https://github.com/DrUbermann/dotfiles-init-test.git'"
& ([scriptblock]::Create((New-Object Net.WebClient).DownloadString('https://get.chezmoi.io/ps1'))) init --apply 'https://github.com/DrUbermann/dotfiles-init-test.git'
#$Env:LGR_LVL_CNSL = 0
## Start a new process so Developer Mode registry change will be read
powershell.exe -ExecutionPolicy Bypass -File "$HOME/chezmoi.tmp/init.ps1"
