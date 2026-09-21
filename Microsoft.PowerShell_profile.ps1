# =====================================================================
# NMJ PowerShell Profile — thin loader
# Place this file at: $PROFILE  (usually Documents\PowerShell\Microsoft.PowerShell_profile.ps1)
# All real logic lives in the NMJ.* modules under Modules\
# =====================================================================

$env:NMJ_ROOT = Join-Path $HOME 'Documents\PowerShell\Modules'
$env:NMJ_CONFIG = Join-Path $HOME '.nmj'

# Ensure config directory exists
if (-not (Test-Path $env:NMJ_CONFIG)) {
    New-Item -Path $env:NMJ_CONFIG -ItemType Directory -Force | Out-Null
}

# Optional debug timing
if ($env:PROFILE_DEBUG) {
    $Global:__ProfileStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
}

# Import modules in dependency order
$modules = @(
    'NMJ.Core'
    'NMJ.History'
    'NMJ.AI'
    'NMJ.Shortcuts'
    'NMJ.Themes'
)

foreach ($mod in $modules) {
    $modPath = Join-Path $env:NMJ_ROOT $mod
    if (Test-Path $modPath) {
        Import-Module $modPath -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-Host "[NMJ] Module not found: $modPath" -ForegroundColor Yellow
    }
}

# Remaining classic features that stay in the profile for now
# (zoxide, fuzzy navigation, modern CLI replacements, etc.)
# These will stay here until you decide to move them into modules too.

# --- 2. Fuzzy Navigation (zoxide + Everything/fzf) ---
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

function Find-FuzzyFolder {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Target,
        [Alias('h')]
        [switch]$Hidden,
        [switch]$All,
        [string]$Disk = "C",
        [switch]$SkipZoxide
    )
    if (-not $SkipZoxide -and (Get-Command zoxide -ErrorAction SilentlyContinue)) {
        $zoxideMatch = (zoxide query -- $Target 2>$null)
        if ($LASTEXITCODE -eq 0 -and $zoxideMatch -and (Test-Path $zoxideMatch)) {
            Write-Host "`nNavigating to (zoxide): $zoxideMatch" -ForegroundColor Green
            Set-Location $zoxideMatch
            return
        }
    }
    $basePath = if ($All -or $Disk -ne "C") { "$($Disk):" } else { $HOME }
    $esArgs = @($basePath)
    if (-not $Hidden) {
        $esArgs += "!path:AppData"
        $esArgs += "/a-h"
    }
    $exactArgs = @("folder:$Target") + $esArgs
    $results = @(& es.exe $exactArgs -n 50 2>$null)
    if ($results.Count -eq 0) {
        $fuzzyArgs = @("folder:*$Target*") + $esArgs
        $results = @(& es.exe $fuzzyArgs -n 50 2>$null)
    }
    $isTypoFallback = $false
    if ($results.Count -eq 0 -and $Target.Length -ge 3) {
        $prefix = $Target.Substring(0, 3)
        $typoArgs = @("folder:*$prefix*") + $esArgs
        $results = @(& es.exe $typoArgs -n 200 2>$null)
        $isTypoFallback = $true
    }
    if ($results.Count -eq 0) {
        Write-Host "`n[!] Could not find any folder matching '$Target' in $($basePath) (Hidden: $Hidden)." -ForegroundColor Yellow
        return
    }
    $results = @($results | Sort-Object { ($_ -split '\\').Count }, { $_ })
    if ($results.Count -eq 1 -and -not $isTypoFallback) {
        Write-Host "`nNavigating to: $($results[0])" -ForegroundColor Green
        Set-Location $results[0]
        return
    }
    if ($isTypoFallback) {
        $selected = $results | fzf --prompt="Select folder ($Target) > " --height=40% --layout=reverse --border --query="$Target"
    }
    else {
        $selected = $results | fzf --prompt="Select folder ($Target) > " --height=40% --layout=reverse --border
    }
    if (-not [string]::IsNullOrWhiteSpace($selected)) {
        Write-Host "`nNavigating to: $selected" -ForegroundColor Green
        Set-Location $selected
    }
    else {
        Write-Host "`n[!] Selection cancelled." -ForegroundColor Yellow
    }
}
Set-Alias -Name Navigate-Fuzzy -Value Find-FuzzyFolder -Force -ErrorAction SilentlyContinue
Set-Alias -Name nf -Value Find-FuzzyFolder -Force -ErrorAction SilentlyContinue

# --- 4. Shell completions (uv) ---
if (Get-Command uv -ErrorAction SilentlyContinue) {
    (& uv generate-shell-completion powershell) | Out-String | Invoke-Expression
}

# --- 6. Modern CLI Replacements ---
if (Get-Command eza -ErrorAction SilentlyContinue) {
    Set-Alias -Name ls -Value eza -Force -ErrorAction SilentlyContinue
    function ll { eza -la --icons --git @args }
    function lt { eza -T --icons --git-ignore @args }
}
if (Get-Command bat -ErrorAction SilentlyContinue) {
    Set-Alias -Name cat -Value bat -Force -ErrorAction SilentlyContinue
}
if (Get-Command gsudo -ErrorAction SilentlyContinue) {
    Set-Alias -Name sudo -Value gsudo -Force -ErrorAction SilentlyContinue
}
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    Import-Module Terminal-Icons -ErrorAction SilentlyContinue
}
if (Get-Module -ListAvailable -Name PSFzf) {
    Import-Module PSFzf -ErrorAction SilentlyContinue
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -ErrorAction SilentlyContinue
}

# --- Predictive IntelliSense (kept here, works with Atuin) ---
Import-Module PSReadLine -ErrorAction SilentlyContinue
$isInteractiveConsole = $Host.UI.RawUI -and -not [Console]::IsOutputRedirected -and -not [Console]::IsInputRedirected
if ($isInteractiveConsole) {
    try {
        Set-PSReadLineOption -PredictionSource History
        Set-PSReadLineOption -PredictionViewStyle ListView
    }
    catch { }
}

if ($env:PROFILE_DEBUG) {
    Write-Host "[Profile loaded in $($Global:__ProfileStopwatch.ElapsedMilliseconds) ms]" -ForegroundColor DarkGray
}
