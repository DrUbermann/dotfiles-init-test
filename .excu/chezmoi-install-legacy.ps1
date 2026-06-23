#### Source: Claude 4.6 (2026-06)

<#
.SYNOPSIS
    Installs chezmoi by building it from source with the go-legacy-win7 Go
    toolchain, for systems (e.g. Windows 7, PowerShell 2.0) where the official
    https://get.chezmoi.io/ps1 script and its precompiled binaries won't run.

.DESCRIPTION
    Same behaviour as Install-ChezmoiLegacy.ps1, but logging uses native
    PowerShell streams instead of custom log-debug/log-info/log-crit wrapper
    functions:

      - debug-level messages use Write-Debug, controlled by the built-in
        -Debug common parameter instead of a custom -EnableDebug/-d switch.
      - info-level messages still use Write-Host directly -- there isn't a
        more "native" way to print plain text unconditionally, so this one
        is unchanged.
      - critical/fatal messages use Write-Error -ErrorAction Continue. The
        -ErrorAction Continue is required here: this script sets
        $ErrorActionPreference = 'Stop' globally so *unexpected* errors are
        caught by the trap below, and without overriding it locally, every
        intentional Write-Error call would itself become a terminating
        error right there instead of reaching the explicit `exit` after it.

    One practical trade-off either way: Write-Error prints PowerShell's
    standard multi-line error record (red text, category info, position),
    not the single colored "critical ..." line the custom version produced.
    If you want that exact compact look back, the custom-function version
    is the one to use.

    The PowerShell 3.0+/.NET 4.5+ rationale, and the go-legacy-win7 build
    steps themselves, are unchanged -- see Install-ChezmoiLegacy.ps1 for the
    full explanation if you haven't read it already.

.PARAMETER BinDir
    Where chezmoi.exe ends up (passed to `go install` via GOBIN).
    Default: .\bin under the current directory. Alias: b

.PARAMETER ChezmoiTag
    chezmoi version to build, e.g. v2.69.4. Default: latest. Alias: t

.PARAMETER GoLegacyTag
    go-legacy-win7 release to install, e.g. go1.24.5-1. Default: latest.

.PARAMETER GoRoot
    Where to install the go-legacy-win7 toolchain. Reused on later runs
    unless -Force is given. Default: $env:LOCALAPPDATA\go-legacy-win7

.PARAMETER Force
    Re-download and re-extract the toolchain even if GoRoot already has one.

.PARAMETER ChezmoiArgs
    Everything after the named parameters is passed straight to chezmoi.exe
    once it's built.

.EXAMPLE
    PS> .\Install-ChezmoiLegacy.Natives.ps1 init --apply https://github.com/Owner/Repo.git

.EXAMPLE
    Use the built-in -Debug common parameter for verbose log output (note:
    plain -Debug now, there's no -d short alias for it):

    PS> .\Install-ChezmoiLegacy.Natives.ps1 -Debug init --apply https://github.com/Owner/Repo.git

.EXAMPLE
    One-liner equivalent of the official script's iex+irm pattern, but using
    WebClient since irm/Invoke-RestMethod doesn't exist in PowerShell 2.0:

    PS> $body = (New-Object Net.WebClient).DownloadString('https://your-host/Install-ChezmoiLegacy.Natives.ps1')
    PS> Invoke-Expression "& { $body } init --apply https://github.com/Owner/Repo.git"
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [Alias('b')]
    [string]
    $BinDir = (Join-Path -Path (Resolve-Path -Path '.') -ChildPath 'bin'),

    [Parameter(Mandatory = $false)]
    [Alias('t')]
    [string]
    $ChezmoiTag = 'latest',

    [Parameter(Mandatory = $false)]
    [string]
    $GoLegacyTag = 'latest',

    [Parameter(Mandatory = $false)]
    [string]
    $GoRoot = (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'go-legacy-win7'),

    [Parameter(Mandatory = $false)]
    [switch]
    $Force,

    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]]
    $ChezmoiArgs
)

# -Debug normally sets $DebugPreference = 'Inquire', which prompts
# Continue/Halt/Suspend at every single Write-Debug call -- exactly what you
# don't want from an unattended install script. Downgrade it to 'Continue'
# so -Debug just prints the messages instead of pausing on each one.
if ($PSBoundParameters.ContainsKey('Debug')) {
    $DebugPreference = 'Continue'
}

$ErrorActionPreference = 'Stop'

# --- CLR / TLS sanity check ----------------------------------------------------
# PowerShell 2.0's host (powershell.exe) is bound to CLR 2.0 by default even
# with .NET 4.x installed, unless powershell.exe.config redirects it. Without
# that redirect, Tls12 and System.IO.Compression.ZipFile don't exist and
# nothing below will work. Fail loudly here instead of dying later with a
# confusing "type not found" error partway through a download.
if ($PSVersionTable.CLRVersion.Major -lt 4) {
    Write-Error "PowerShell is bound to CLR $($PSVersionTable.CLRVersion) (.NET 2.0/3.5), even if .NET 4.8 is installed on this machine." -ErrorAction Continue
    Write-Error 'Create C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe.config containing:' -ErrorAction Continue
    Write-Error '  <configuration><startup useLegacyV2RuntimeActivationPolicy="true"><supportedRuntime version="v4.0"/></startup></configuration>' -ErrorAction Continue
    Write-Error 'then open a new PowerShell window and re-run this script.' -ErrorAction Continue
    exit 1
}

try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
} catch {
    Write-Error "could not enable TLS 1.2: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}

$tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempDir | Out-Null

trap {
    Write-Debug "cleaning up $tempDir"
    Remove-Item -Recurse -Force -Path $tempDir -ErrorAction SilentlyContinue
    break
}

# --- helpers --------------------------------------------------------------------
function Get-Arch {
    $arch = $env:PROCESSOR_ARCHITEW6432
    if (-not $arch) { $arch = $env:PROCESSOR_ARCHITECTURE }
    switch ($arch.ToUpper()) {
        'AMD64' { 'amd64' }
        'X86'   { '386' }
        default { $arch.ToLower() }
    }
}

function Invoke-StringDownload($url) {
    Write-Debug "GET $url"
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'Install-ChezmoiLegacy.ps1')
    try { $wc.DownloadString($url) } finally { $wc.Dispose() }
}

function Invoke-FileDownload($url, $outFile) {
    Write-Debug "downloading $url -> $outFile"
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add('User-Agent', 'Install-ChezmoiLegacy.ps1')
    try { $wc.DownloadFile($url, $outFile) } finally { $wc.Dispose() }
}

function Get-GitHubRelease($owner, $repo, $tag) {
    if ($tag -eq 'latest') {
        $url = "https://api.github.com/repos/$owner/$repo/releases/latest"
    } else {
        $url = "https://api.github.com/repos/$owner/$repo/releases/tags/$tag"
    }
    $json = Invoke-StringDownload $url
    if ($json -notmatch '"tag_name"\s*:\s*"([^"]+)"') {
        throw "could not find tag_name in GitHub API response for ${owner}/${repo}@${tag}"
    }
    @{ Tag = $Matches[1]; Json = $json }
}

function Get-AssetUrl($json, $pattern) {
    $assetMatches = [System.Text.RegularExpressions.Regex]::Matches(
        $json, '"browser_download_url"\s*:\s*"([^"]+)"')
    foreach ($m in $assetMatches) {
        if ($m.Groups[1].Value -match $pattern) { return $m.Groups[1].Value }
    }
    $null
}

function Expand-ZipArchive($zipPath, $destination) {
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
    } catch {
        throw 'System.IO.Compression.FileSystem unavailable -- requires .NET 4.5+ actually loaded by powershell.exe, see the CLR check above'
    }
    Write-Debug "extracting $zipPath to $destination"
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $destination)
}

# --- 1. ensure the go-legacy-win7 toolchain -------------------------------------
$goExe = Join-Path $GoRoot 'bin\go.exe'
if ((Test-Path $goExe) -and -not $Force) {
    Write-Host "info found existing go-legacy-win7 toolchain at $GoRoot (use -Force to redo)"
} else {
    $arch = Get-Arch
    Write-Host "info looking up go-legacy-win7 release '$GoLegacyTag' for windows/$arch"
    $release = Get-GitHubRelease 'thongtech' 'go-legacy-win7' $GoLegacyTag
    Write-Host "info found go-legacy-win7 $($release.Tag)"

    $assetUrl = Get-AssetUrl $release.Json "windows_$arch\.zip$"
    if (-not $assetUrl) {
        Write-Error "no windows_$arch.zip asset found in go-legacy-win7 release $($release.Tag) -- check the actual asset names at https://github.com/thongtech/go-legacy-win7/releases and adjust the pattern in Get-AssetUrl if they differ" -ErrorAction Continue
        exit 1
    }

    $zipPath = Join-Path $tempDir 'go-legacy-win7.zip'
    Write-Host "info downloading $assetUrl"
    Invoke-FileDownload $assetUrl $zipPath

    if (Test-Path $GoRoot) {
        Write-Debug "removing existing $GoRoot"
        Remove-Item -Recurse -Force $GoRoot
    }

    $extractDir = Join-Path $tempDir 'extracted'
    New-Item -ItemType Directory -Path $extractDir | Out-Null
    Expand-ZipArchive $zipPath $extractDir

    # the archive normally contains a single top-level folder
    $topLevel = Get-ChildItem -Path $extractDir
    New-Item -ItemType Directory -Path (Split-Path $GoRoot -Parent) -Force | Out-Null
    if ($topLevel.Count -eq 1 -and $topLevel[0].PSIsContainer) {
        Move-Item -Path $topLevel[0].FullName -Destination $GoRoot
    } else {
        Move-Item -Path $extractDir -Destination $GoRoot
    }

    Write-Host "info installed go-legacy-win7 $($release.Tag) to $GoRoot"
}

# --- 2. build chezmoi from source ------------------------------------------------
if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir | Out-Null
}
$BinDir = (Resolve-Path $BinDir).Path

$env:GOROOT = $GoRoot
$env:PATH = "$GoRoot\bin;$env:PATH"
if (-not $env:GOPATH) { $env:GOPATH = Join-Path $env:USERPROFILE 'go' }
$env:GOBIN = $BinDir

$modulePath = 'github.com/twpayne/chezmoi/v2'
Write-Host "info building $modulePath@$ChezmoiTag with $goExe (first build can take a few minutes)"
& $goExe install "$modulePath@$ChezmoiTag"
if ($LASTEXITCODE -ne 0) {
    Write-Error "go install failed with exit code $LASTEXITCODE" -ErrorAction Continue
    exit $LASTEXITCODE
}

$chezmoiExe = Join-Path $BinDir 'chezmoi.exe'
if (-not (Test-Path $chezmoiExe)) {
    Write-Error "build appeared to succeed but $chezmoiExe was not found" -ErrorAction Continue
    exit 1
}
Write-Host "info installed $chezmoiExe"

Remove-Item -Recurse -Force -Path $tempDir -ErrorAction SilentlyContinue

# --- 3. hand off to chezmoi, same convention as the official script -------------
if ($ChezmoiArgs -and $ChezmoiArgs.Count -gt 0) {
    Write-Debug "executing: $chezmoiExe $ChezmoiArgs"
    & $chezmoiExe @ChezmoiArgs
    exit $LASTEXITCODE
}
