# =====================================================================
# NMJ PowerShell Profile — Thin Loader
# Place this file at: $PROFILE (usually Documents\PowerShell\Microsoft.PowerShell_profile.ps1)
# All real logic lives in modular NMJ.* modules under Modules\
# =====================================================================

# Optional startup debug timing ($env:PROFILE_DEBUG = 1)
if ($env:PROFILE_DEBUG) {
    $Global:__ProfileStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
}

# this changed: merge User+Machine PATH first so WinGet tools (atuin, etc.) are found
try {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $seen        = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $merged      = foreach ($part in @($userPath, $machinePath, $env:Path)) {
        if ([string]::IsNullOrWhiteSpace($part)) { continue }
        foreach ($p in ($part -split ';')) {
            if ($p -and $seen.Add($p)) { $p }
        }
    }
    $env:Path = $merged -join ';'
}
catch { }

# Auto-detect NMJ_ROOT: prefer local Modules/ if running from repository, else standard Documents
$localModuleDir = if ($PSScriptRoot) { Join-Path $PSScriptRoot 'Modules' } else { $null }
if ($localModuleDir -and (Test-Path $localModuleDir)) {
    $env:NMJ_ROOT = $localModuleDir
}
else {
    $env:NMJ_ROOT = Join-Path $HOME 'Documents\PowerShell\Modules'
}

$localConfigDir = if ($PSScriptRoot) { Join-Path $PSScriptRoot '.nmj' } else { $null }
$homeConfigDir  = Join-Path $HOME '.nmj'

if ($localConfigDir -and (Test-Path $localConfigDir)) {
    $env:NMJ_CONFIG = $localConfigDir
}
else {
    $env:NMJ_CONFIG = $homeConfigDir
}

# Ensure configuration directory exists
if (-not (Test-Path $env:NMJ_CONFIG)) {
    try {
        New-Item -Path $env:NMJ_CONFIG -ItemType Directory -Force | Out-Null
    }
    catch { }
}

# Ensure home config directory also exists and is seeded if needed
if (-not (Test-Path $homeConfigDir)) {
    try {
        New-Item -Path $homeConfigDir -ItemType Directory -Force | Out-Null
    }
    catch { }
}
$homeShortcuts = Join-Path $homeConfigDir 'shortcuts.json'
$localShortcuts = if ($localConfigDir) { Join-Path $localConfigDir 'shortcuts.json' } else { $null }
if ($localShortcuts -and (Test-Path $localShortcuts)) {
    if (-not (Test-Path $homeShortcuts)) {
        Copy-Item -Path $localShortcuts -Destination $homeShortcuts -Force -ErrorAction SilentlyContinue
    }
    else {
        try {
            $existing = Get-Content -Path $homeShortcuts -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
            if (-not $existing.shortcuts -or $existing.shortcuts.Count -eq 0) {
                Copy-Item -Path $localShortcuts -Destination $homeShortcuts -Force -ErrorAction SilentlyContinue
            }
        }
        catch { }
    }
}

# Ensure PSReadLine is loaded globally before Oh My Posh initializes
Import-Module PSReadLine -Global -ErrorAction SilentlyContinue

# Modules in strict dependency order
$modules = @(
    'NMJ.Core'
    'NMJ.Nav'
    'NMJ.CLI'
    'NMJ.History'
    'NMJ.AI'
    'NMJ.Shortcuts'
    'NMJ.Themes'
)

foreach ($mod in $modules) {
    $modPath = Join-Path $env:NMJ_ROOT $mod
    if (-not (Test-Path $modPath)) {
        if ($env:PROFILE_DEBUG) {
            Write-Host "[NMJ] Module not found: $modPath" -ForegroundColor Yellow
        }
        continue
    }

    # this changed: -Force only on reload so first start does not re-parse already-loaded modules
    $alreadyLoaded = [bool](Get-Module -Name $mod)
    $modSw = if ($env:PROFILE_DEBUG) { [System.Diagnostics.Stopwatch]::StartNew() } else { $null }
    try {
        Import-Module $modPath -Global -DisableNameChecking -ErrorAction Stop -Force:$alreadyLoaded
    }
    catch {
        Write-Host "[NMJ] Failed to load $mod : $($_.Exception.Message)" -ForegroundColor Yellow
    }
    if ($modSw) {
        $modSw.Stop()
        Write-Host "[NMJ] $mod $($modSw.ElapsedMilliseconds) ms" -ForegroundColor DarkGray
    }
}

# this changed: FastFetch after Import-Module so the banner is not swallowed by module import
$showBanner = if (Get-Command Test-NMJInteractiveHost -ErrorAction SilentlyContinue) {
    Test-NMJInteractiveHost
}
else {
    [Environment]::UserInteractive -and $Host.Name -ne 'ServerRemoteHost' -and -not [Console]::IsOutputRedirected
}
if ($showBanner -and $Global:CurrentFastFetchConfig -and (Get-Command Invoke-FastFetch -ErrorAction SilentlyContinue)) {
    Invoke-FastFetch
}

if ($env:PROFILE_DEBUG -and $Global:__ProfileStopwatch) {
    Write-Host "[Profile loaded in $($Global:__ProfileStopwatch.ElapsedMilliseconds) ms]" -ForegroundColor DarkGray
}
