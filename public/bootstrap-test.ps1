#!/usr/bin/env pwsh

Set-ExecutionPolicy -Scope CurrentUser Bypass

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

$webClient = New-Object System.Net.WebClient
$webClient.Headers.Add('Authorization', "Basic $creds")
$script = $webClient.DownloadString($url)

Invoke-Expression $script
