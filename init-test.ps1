#!/usr/bin/env pwsh

Write-Output "Starting init-test.ps1"

Set-ExecutionPolicy -Scope CurrentUser Bypass

# Use integer value for TLS 1.2 to support .NET 4.0
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]3072

Set-Location ~

iex "&{$(irm 'https://get.chezmoi.io/ps1')} init --apply 'https://github.com/DrUbermann/dotfiles-init-test.git'"
#$Env:LGR_LVL_CNSL = 0
& "$HOME/chezmoi.tmp/init.ps1"
