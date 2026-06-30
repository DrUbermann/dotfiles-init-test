#!/usr/bin/env pwsh

## Equivalent of set -eu
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force

$securePassword = Read-Host -Prompt 'Password' -AsSecureString
$password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
)

$creds = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(":$password"))
$url = 'https://dotfiles-init-test.drubermann.workers.dev/init-test.ps1'

Invoke-Expression (Invoke-WebRequest -UseBasicParsing -Uri $url -Headers @{ Authorization = "Basic $creds" }).Content
