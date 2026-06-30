#### Source: Claude 4.6 (2026-06)

<#
.SYNOPSIS
    Installs chezmoi by building it from source with the go-legacy-win7 Go
    toolchain, for systems (e.g. Windows 7, PowerShell 2.0) where the official
    https://get.chezmoi.io/ps1 script and its precompiled binaries won't run.

.DESCRIPTION
    The official install.ps1 requires PowerShell 3.0+ (it calls
    Set-StrictMode -Version 3.0) and .NET 4.5+ APIs (Tls12, ZipFile) that
    powershell.exe won't use even if .NET 4.x is installed, unless it has been
    explicitly redirected to the newer CLR. It also only ever downloads a
    prebuilt release archive, which doesn't exist for Windows 7-compatible
    binaries.

    This script avoids PowerShell 3.0+-only cmdlets (no Invoke-WebRequest,
    no Invoke-RestMethod, no ConvertFrom-Json) and instead:

      1. Downloads and extracts the go-legacy-win7 toolchain
         (https://github.com/thongtech/go-legacy-win7), a Go fork that keeps
         Windows 7 / Server 2008 R2 support that upstream Go dropped after 1.21.
      2. Downloads chezmoi's own source for the target version and runs
         `go install .` from inside it, rather than `go install pkg@version`
         -- chezmoi's go.mod currently has `exclude` directives, which Go
         refuses for the pkg@version form on any Go version (not specific
         to this legacy toolchain).
      3. If extra arguments were given, execs the resulting chezmoi.exe with
         them, e.g. `init --apply <repo>` -- same convention as the official
         script.

    Note: chezmoi's own module fetch (via `go install`) and the resulting
    chezmoi.exe's own HTTPS calls go through Go's bundled crypto/tls, not
    PowerShell's .NET stack, so the CLR/TLS concerns below only affect *this*
    script's own downloads (the go-legacy-win7 toolchain itself).

    Logging uses native PowerShell streams instead of custom wrapper
    functions: debug-level messages use Write-Debug (controlled by the
    built-in -Debug common parameter), info-level messages use Write-Host
    directly, and critical/fatal messages use Write-Error -ErrorAction
    Continue (the -ErrorAction override is required because
    $ErrorActionPreference is set to 'Stop' globally below, so unexpected
    errors are caught by the trap -- without it, every intentional
    Write-Error call would itself become a terminating error right there
    instead of reaching the explicit `exit` that follows it).

.PARAMETER BinDir
    Where chezmoi.exe ends up (passed to `go install` via GOBIN).
    Default: .\bin under the current directory. Alias: b

.PARAMETER ChezmoiTag
    chezmoi version to build, e.g. v2.69.4. Default: latest, which resolves
    via the GitHub releases API to the actual current tag. Used to fetch
    chezmoi's source archive (not passed to `go install pkg@version` --
    see the build step below for why). Alias: t

.PARAMETER GoLegacyTag
    go-legacy-win7 release to install, e.g. go1.24.5-1. Default: latest.

.PARAMETER GoRoot
    Where to install the go-legacy-win7 toolchain. Reused on later runs
    unless -Force is given. Default: $env:LOCALAPPDATA\go-legacy-win7
    Any wrapping folder the archive extracts (e.g. go-legacy-win7\bin\go.exe)
    gets flattened into GoRoot itself on a fresh extraction, so GoRoot ends
    up directly containing bin\ rather than being a parent of it.

.PARAMETER Force
    Re-download and re-extract the toolchain even if GoRoot already has one.

.PARAMETER ChezmoiArgs
    Everything after the named parameters is passed straight to chezmoi.exe
    once it's built. Use -- to separate this script's own flags from chezmoi's,
    same as the official script.

.EXAMPLE
    PS> .\Install-ChezmoiLegacy.ps1 -- init --apply https://github.com/Owner/Repo.git

.EXAMPLE
    Use the built-in -Debug common parameter for verbose log output (note:
    plain -Debug, there's no -d short alias for it the way the old
    -EnableDebug switch had):

    PS> .\Install-ChezmoiLegacy.ps1 -Debug -- init --apply https://github.com/Owner/Repo.git

.EXAMPLE
    One-liner equivalent of the official script's iex+irm pattern, but using
    WebClient since irm/Invoke-RestMethod doesn't exist in PowerShell 2.0:

    PS> $body = (New-Object Net.WebClient).DownloadString('https://your-host/Install-ChezmoiLegacy.ps1')
    PS> Invoke-Expression "& { $body } -- init --apply https://github.com/Owner/Repo.git"
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

function Expand-ZipArchive($zipPath, $destination, $waitForFile = 'go.exe') {
    # System.IO.Compression.ZipFile (.NET 4.5+) didn't resolve by simple name
    # under this CLR2-host-forced-to-CLR4 setup even though the CLR itself is
    # genuinely v4 -- use the Shell.Application COM object instead, which has
    # worked unchanged since Windows XP and has no .NET version dependency.
    Write-Debug "extracting $zipPath to $destination (via Shell.Application)"
    $shell = New-Object -ComObject Shell.Application
    $zipItems = $shell.NameSpace($zipPath).Items()
    $shell.NameSpace($destination).CopyHere($zipItems, 0x14)  # 0x4 = no progress UI, 0x10 = yes-to-all

    # CopyHere hands off to the shell and returns before a large copy
    # actually finishes, so poll for a file we expect rather than assuming
    # it's done the moment this call returns. Different archives need a
    # different marker file (go.exe for the toolchain, go.mod for source).
    $timeout = (Get-Date).AddMinutes(5)
    while (-not (Get-ChildItem -Path $destination -Recurse -Filter $waitForFile -ErrorAction SilentlyContinue) -and (Get-Date) -lt $timeout) {
        Start-Sleep -Seconds 1
    }
    if (-not (Get-ChildItem -Path $destination -Recurse -Filter $waitForFile -ErrorAction SilentlyContinue)) {
        throw "zip extraction via Shell.Application timed out -- $waitForFile not found under $destination"
    }
}

# --- 1. ensure the go-legacy-win7 toolchain -------------------------------------
function Find-GoExe($root) {
    Get-ChildItem -Path $root -Recurse -Filter 'go.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}

$goExe = Find-GoExe $GoRoot
if ($goExe -and -not $Force) {
    Write-Host "info found existing go-legacy-win7 toolchain at $goExe (use -Force to redo)"
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

    # extract straight into GoRoot -- no separate Move-Item step, so there's
    # nothing left to nest incorrectly if GoRoot happens to already exist.
    New-Item -ItemType Directory -Path $GoRoot -Force | Out-Null
    Expand-ZipArchive $zipPath $GoRoot

    # don't assume a fixed nesting depth (single wrapping folder, double,
    # none) -- search for go.exe wherever it actually landed instead.
    $goExe = Find-GoExe $GoRoot
    if (-not $goExe) {
        Write-Error "go.exe not found anywhere under $GoRoot after extraction -- check the archive layout with: Get-ChildItem -Recurse $GoRoot" -ErrorAction Continue
        exit 1
    }

    # the archive wraps everything in its own folder (e.g. go-legacy-win7\bin\go.exe)
    # -- flatten that wrapper's contents up into GoRoot itself, so -GoRoot ends up
    # being the literal folder that contains bin\, not a parent of it.
    $wrapperDir = Split-Path (Split-Path $goExe -Parent) -Parent
    if ($wrapperDir -ne $GoRoot) {
        Write-Debug "flattening $wrapperDir into $GoRoot"
        Get-ChildItem -Path $wrapperDir -Force | Move-Item -Destination $GoRoot -Force
        Remove-Item -Recurse -Force $wrapperDir -ErrorAction SilentlyContinue
        $goExe = Find-GoExe $GoRoot
    }

    Write-Host "info installed go-legacy-win7 $($release.Tag) -- go.exe at $goExe"
}

$actualGoRoot = Split-Path (Split-Path $goExe -Parent) -Parent

# --- 2. build chezmoi from source ------------------------------------------------
if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir | Out-Null
}
$BinDir = (Resolve-Path $BinDir).Path

$env:GOROOT = $actualGoRoot
$env:PATH = "$(Split-Path $goExe -Parent);$env:PATH"
if (-not $env:GOPATH) { $env:GOPATH = Join-Path $env:USERPROFILE 'go' }
$env:GOBIN = $BinDir

# `go install github.com/twpayne/chezmoi/v2@<tag>` fails on *any* Go version,
# not just this legacy one: chezmoi's go.mod currently carries `exclude`
# directives (working around a charmbracelet/bubbles regression -- see
# https://github.com/twpayne/chezmoi/issues/4405), and `go install pkg@version`
# refuses to install any module whose own go.mod has replace/exclude
# directives, since it can't be treated as if it were the main module. See
# https://github.com/golang/go/issues/44840. Downloading the source and
# building from inside it sidesteps this entirely, since the module then
# genuinely *is* the main module.
if ($ChezmoiTag -eq 'latest') {
    Write-Host "info looking up latest chezmoi release"
    $resolvedChezmoiTag = (Get-GitHubRelease 'twpayne' 'chezmoi' 'latest').Tag
} else {
    $resolvedChezmoiTag = $ChezmoiTag
}

Write-Host "info downloading chezmoi $resolvedChezmoiTag source"
$chezmoiZipPath = Join-Path $tempDir 'chezmoi-src.zip'
Invoke-FileDownload "https://github.com/twpayne/chezmoi/archive/refs/tags/$resolvedChezmoiTag.zip" $chezmoiZipPath

$chezmoiSrcExtractDir = Join-Path $tempDir 'chezmoi-src'
New-Item -ItemType Directory -Path $chezmoiSrcExtractDir | Out-Null
Expand-ZipArchive $chezmoiZipPath $chezmoiSrcExtractDir 'go.mod'

$chezmoiGoMod = Get-ChildItem -Path $chezmoiSrcExtractDir -Recurse -Filter 'go.mod' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $chezmoiGoMod) {
    Write-Error "go.mod not found anywhere under $chezmoiSrcExtractDir after extracting chezmoi $resolvedChezmoiTag source" -ErrorAction Continue
    exit 1
}
$chezmoiSrcDir = $chezmoiGoMod.DirectoryName

Write-Host "info building chezmoi $resolvedChezmoiTag from source with $goExe (first build can take a few minutes)"
Push-Location $chezmoiSrcDir
try {
    & $goExe install .
    $buildExitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
if ($buildExitCode -ne 0) {
    Write-Error "go install failed with exit code $buildExitCode" -ErrorAction Continue
    exit $buildExitCode
}

# --- 2b. work around pre-Windows-10 console incompatibilities: several
# dependencies try to set console mode flags (ENABLE_VIRTUAL_TERMINAL_*)
# that don't exist before Windows 10 and fail with ERROR_INVALID_PARAMETER
# -- the documented, expected way Windows signals a down-level console (see
# https://learn.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences).
# They treat that as fatal instead of degrading gracefully. The build above
# already pulled all of them into the module cache as ordinary dependencies;
# copy each one, neutralize the specific failure, and rebuild against the
# patched copies.
function Update-LegacyConsoleModule($modulePath, $parentRelPath, $nameFilter, $patchedName, $targetFile, $linePatternsToRemove, $chezmoiSrcDir) {
    $cacheDir = Get-ChildItem -Path (Join-Path $env:GOPATH "pkg\mod\$parentRelPath") -Filter $nameFilter -ErrorAction SilentlyContinue |
        Where-Object { $_.PSIsContainer } | Select-Object -Last 1
    if (-not $cacheDir) {
        Write-Host "info $modulePath not found in the module cache -- skipping its console compatibility patch"
        return $false
    }

    $patchedDir = Join-Path $env:LOCALAPPDATA $patchedName
    if (-not (Test-Path $patchedDir)) {
        Write-Host "info patching $($cacheDir.Name) for pre-Windows-10 console compatibility"
        Copy-Item -Recurse -Force $cacheDir.FullName $patchedDir
        Get-ChildItem -Recurse $patchedDir | Where-Object { -not $_.PSIsContainer } | ForEach-Object { $_.IsReadOnly = $false }

        $file = Join-Path $patchedDir $targetFile
        $content = Get-Content $file
        foreach ($pattern in $linePatternsToRemove) {
            $content = $content | Where-Object { $_ -notmatch $pattern }
        }
        $content | Set-Content $file
    } else {
        Write-Debug "reusing existing patched $modulePath at $patchedDir"
    }

    $replaceLine = "replace $modulePath => $($patchedDir -replace '\\', '/')"
    Add-Content -Path (Join-Path $chezmoiSrcDir 'go.mod') -Value "`n$replaceLine"
    return $true
}

$patchedAny = $false

# termenv: SetConsoleMode failure (output color/VT processing) is propagated
# as a fatal error instead of degrading gracefully.
if (Update-LegacyConsoleModule 'github.com/muesli/termenv' 'github.com\muesli' 'termenv@*' 'termenv-patched' 'termenv_windows.go' @(
        'err = fmt\.Errorf\("windows\.SetConsoleMode: %w", err2\)',
        '^\s*"fmt"\s*$'
    ) $chezmoiSrcDir) { $patchedAny = $true }

# charmbracelet/x/term: makeRaw() additionally tries to set
# ENABLE_VIRTUAL_TERMINAL_INPUT on top of the (Windows-7-compatible)
# echo/line/processed-input flags it clears for raw mode.
if (Update-LegacyConsoleModule 'github.com/charmbracelet/x/term' 'github.com\charmbracelet\x' 'term@*' 'xterm-patched' 'term_windows.go' @(
        'raw \|= windows\.ENABLE_VIRTUAL_TERMINAL_INPUT'
    ) $chezmoiSrcDir) { $patchedAny = $true }

# bubbletea: initInput() redundantly tries to set the same VT input flag
# itself (independent of the term package above) and also sets the VT
# output-processing flag, treating either failure as fatal.
if (Update-LegacyConsoleModule 'github.com/charmbracelet/bubbletea' 'github.com\charmbracelet' 'bubbletea@*' 'bubbletea-patched' 'tty_windows.go' @(
        'return fmt\.Errorf\("error setting console mode: %w", err\)'
    ) $chezmoiSrcDir) { $patchedAny = $true }

if ($patchedAny) {
    Write-Host "info rebuilding chezmoi against patched console-compatibility modules"
    Push-Location $chezmoiSrcDir
    try {
        & $goExe install .
        $buildExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($buildExitCode -ne 0) {
        Write-Error "rebuild against patched modules failed with exit code $buildExitCode" -ErrorAction Continue
        exit $buildExitCode
    }
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


    Write-Host "after running chezmoi-install-legacy chezmoi.exe chezmoi_args, LASTEXITCODE = $LASTEXITCODE"




    exit $LASTEXITCODE
}
