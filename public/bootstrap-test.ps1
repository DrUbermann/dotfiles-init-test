#!/usr/bin/env pwsh

## Equivalent of set -eu
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force

## Use integer value for TLS 1.2 to support .NET 4.0
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]3072

$securePassword = Read-Host -Prompt 'Password' -AsSecureString
$password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
)

$creds = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes(":$password")
)

$url = 'https://dotfiles-init-test.drubermann.workers.dev/init-test.ps1'

#### Simpler version for PowerShell 5+
# $script = (Invoke-WebRequest -Uri $url -Headers @{ Authorization = "Basic $creds" }).Content

$client = New-Object System.Net.WebClient
$client.Headers.Add('Authorization', "Basic $creds")
$script = $client.DownloadString($url)

Invoke-Expression $script
