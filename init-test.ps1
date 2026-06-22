#!/usr/bin/env pwsh

Write-Output "Starting init-test.ps1" ###############################################

## Equivalent of set -eu
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Set-Location ~

#Invoke-Expression "&{$(Invoke-RestMethod 'https://get.chezmoi.io/ps1')} init --apply 'https://github.com/DrUbermann/dotfiles-init-test.git'"

#& ([scriptblock]::Create((New-Object Net.WebClient).DownloadString('https://get.chezmoi.io/ps1'))) init --apply 'https://github.com/DrUbermann/dotfiles-init-test.git'

#### Use for Windows 7
#### Source: Claude 4.6 (2026-06)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]3072
$script = (New-Object Net.WebClient).DownloadString('https://get.chezmoi.io/ps1')

## PS compatibility fixes
$script = $script -replace '\[System\.Net\.WebClient\]::new\(\)', '(New-Object System.Net.WebClient)'
$script = $script -replace '\$PSVersionTable\.PSEdition', '"Desktop"'
$script = $script -replace 'Write-Information', 'Write-Host'
$script = $script -replace "\`$script:InformationPreference = 'Continue'", ''
$script = $script -replace 'Get-CimInstance -ClassName Win32_Processor', 'Get-WmiObject Win32_Processor'

## Replace download block with go install
$oldBlock = @'
$goOS = Get-GoOS
$goArch = Get-GoArch

foreach ($variableName in @('goOS', 'goArch')) {
    Write-DebugVariable $variableName
}

$realTag = Get-RealTag $Tag
$version = $realTag.TrimStart('v')
Write-Information "found version ${version} for ${Tag}/${goOS}/${goArch}"

$binarySuffix = ''
$archiveFormat = 'tar.gz'
$goOSExtra = ''

switch ($goOS) {
    'linux' {
        $goOSExtra = "-$( Get-LibC )"
        break
    }
    'windows' {
        $binarySuffix = '.exe'
        $archiveFormat = 'zip'
        break
    }
}

Write-DebugVariable 'binarySuffix', 'archiveFormat', 'goOSExtra'

$archiveFilename = "chezmoi_${version}_${goOS}${goOSExtra}_${goArch}.${archiveFormat}"
$tempArchivePath = Join-Path -Path $tempDir -ChildPath $archiveFilename

Write-DebugVariable 'archiveFilename', 'tempArchivePath'

Invoke-FileDownload "${BaseUrl}/download/${realTag}/${archiveFilename}" $tempArchivePath

$checksums = Get-Checksums $realTag $version
Confirm-Checksum $tempArchivePath $checksums

Expand-ChezmoiArchive $tempArchivePath

$binaryFilename = "chezmoi${binarySuffix}"
$tempBinaryPath = Join-Path -Path $tempDir -ChildPath $binaryFilename

Write-DebugVariable 'binaryFilename', 'tempBinaryPath'
'@

$newBlock = @'
Write-Host "building chezmoi@${Tag} from source"
& go install "github.com/twpayne/chezmoi@${Tag}"
if ($LASTEXITCODE -ne 0) { Write-Error "go install failed" }
$goPathBin = & go env GOPATH | Join-Path -ChildPath 'bin'
$binaryFilename = 'chezmoi.exe'
$tempBinaryPath = Join-Path -Path $goPathBin -ChildPath $binaryFilename
'@

$script = $script -replace [regex]::Escape($oldBlock), $newBlock

## Remove now-unused temp dir setup and cleanup
$script = $script -replace '(?s)\$tempDir = ''''.*?Write-DebugVariable ''BinDir'', ''Tag'', ''ChezmoiArgs'', ''tempDir''', 'Write-DebugVariable ''BinDir'', ''Tag'', ''ChezmoiArgs'''
$script = $script -replace 'Invoke-CleanUp \$tempDir', ''

& ([scriptblock]::Create($script)) init --apply 'https://github.com/DrUbermann/dotfiles-init-test.git'
#### ####


#$Env:LGR_LVL_CNSL = 0
powershell.exe -ExecutionPolicy Bypass -File "$HOME/chezmoi.tmp/init.ps1"
