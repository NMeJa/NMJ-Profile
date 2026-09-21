# =====================================================================
# NMJ.Core — Bootstrap, shared helpers, Ollama warning logic, help aggregator
# =====================================================================

$script:BootstrapMarker   = Join-Path $HOME '.ps_profile_bootstrap_v2'
$configDir                = if ($env:NMJ_CONFIG) { $env:NMJ_CONFIG } else { Join-Path $HOME '.nmj' }
$script:OllamaWarnCounter = Join-Path $configDir 'ollama_warn_count.txt'
$script:MaxOllamaWarnings = 3

# ---------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------
function Get-NMJConfigPath {
    param([string]$Name = 'shortcuts.json')
    $base = if ($env:NMJ_CONFIG) { $env:NMJ_CONFIG } else { Join-Path $HOME '.nmj' }
    Join-Path $base $Name
}

function Expand-NMJPath {
    <#
    .SYNOPSIS
        Expands dynamic tags in paths ($HOME$, $LOCALAPPDATA$, $APPDATA$, $TEMP$, $USERPROFILE$, $USERNAME$).
    #>
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $expanded = $Path
    if ($HOME)             { $expanded = $expanded.Replace('$HOME$', $HOME) }
    if ($env:USERPROFILE)  { $expanded = $expanded.Replace('$USERPROFILE$', $env:USERPROFILE) }
    if ($env:LOCALAPPDATA) { $expanded = $expanded.Replace('$LOCALAPPDATA$', $env:LOCALAPPDATA) }
    if ($env:APPDATA)      { $expanded = $expanded.Replace('$APPDATA$', $env:APPDATA) }
    if ($env:TEMP)         { $expanded = $expanded.Replace('$TEMP$', $env:TEMP) }
    if ($env:USERNAME)     { $expanded = $expanded.Replace('$USERNAME$', $env:USERNAME) }
    return $expanded
}

function Write-NMJWarning {
    param([string]$Message, [string]$Color = 'Yellow')
    Write-Host "[NMJ] $Message" -ForegroundColor $Color
}

# ---------------------------------------------------------------------
# Ollama presence check
# ---------------------------------------------------------------------
function Test-OllamaInstalled {
    return [bool](Get-Command ollama -ErrorAction SilentlyContinue)
}

function Get-OllamaWarnCount {
    if (Test-Path $script:OllamaWarnCounter) {
        try {
            $raw = Get-Content $script:OllamaWarnCounter -ErrorAction SilentlyContinue
            $count = 0
            if ([int]::TryParse($raw, [ref]$count)) { return $count }
        }
        catch { }
    }
    return 0
}

function Set-OllamaWarnCount {
    param([int]$Value)
    try {
        $dir = Split-Path $script:OllamaWarnCounter -Parent
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        Set-Content -Path $script:OllamaWarnCounter -Value $Value -Encoding utf8 -ErrorAction SilentlyContinue
    }
    catch { }
}

function Assert-OllamaAvailable {
    <#
    .SYNOPSIS
        Called by AI commands. Warns cleanly only when an AI command is explicitly executed.
    #>
    if (Test-OllamaInstalled) { return $true }

    Write-NMJWarning "Ollama is not installed or not in PATH." 'Yellow'
    Write-Host "  Install from https://ollama.com then restart terminal." -ForegroundColor DarkGray
    Write-Host "  After install, pull a model:  ollama pull qwen2.5-coder:7b" -ForegroundColor DarkGray
    return $false
}

function Show-OllamaStartupWarning {
    <#
    .SYNOPSIS
        Silent on standard startup. Only outputs warning if $env:PROFILE_DEBUG is enabled.
    #>
    if (Test-OllamaInstalled) { return }

    if ($env:PROFILE_DEBUG) {
        $count = Get-OllamaWarnCount
        if ($count -ge $script:MaxOllamaWarnings) { return }
        $remaining = $script:MaxOllamaWarnings - $count - 1
        Write-NMJWarning "[DEBUG] Ollama is not installed ($($count + 1)/$($script:MaxOllamaWarnings))."
        Set-OllamaWarnCount ($count + 1)
    }
}

# ---------------------------------------------------------------------
# Dependency Bootstrap (winget + modules)
# ---------------------------------------------------------------------
function Update-ProfileDependencies {
    [CmdletBinding()]
    param([switch]$Force)

    if ((Test-Path $script:BootstrapMarker) -and -not $Force) { return }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        if ($Force) {
            Write-NMJWarning "winget not found. Install 'App Installer' from Microsoft Store, then run Update-ProfileDependencies -Force."
        }
        return
    }

    Write-Host "`nChecking profile dependencies (first run or -Force)..." -ForegroundColor Cyan

    $wingetTools = [ordered]@{
        'oh-my-posh' = 'JanDeDobbeleer.OhMyPosh'
        'fastfetch'  = 'Fastfetch-cli.Fastfetch'
        'fzf'        = 'junegunn.fzf'
        'es'         = 'voidtools.Everything.Cli'
        'zoxide'     = 'ajeetdsouza.zoxide'
        'eza'        = 'eza-community.eza'
        'bat'        = 'sharkdp.bat'
        'rg'         = 'BurntSushi.ripgrep.MSVC'
        'gsudo'      = 'gerardog.gsudo'
        'uv'         = 'astral-sh.uv'
        'atuin'      = 'Atuinsh.Atuin'
    }

    try {
        # Everything GUI
        $hasEverything = winget list --id voidtools.Everything -e 2>$null | Select-String 'voidtools.Everything'
        if (-not $hasEverything) {
            Write-Host "  Installing Everything (voidtools.Everything)..." -ForegroundColor DarkCyan
            winget install -e --id voidtools.Everything --accept-source-agreements --accept-package-agreements --silent 2>$null | Out-Null
        }
    }
    catch { }

    foreach ($tool in $wingetTools.GetEnumerator()) {
        if (-not (Get-Command $tool.Key -ErrorAction SilentlyContinue)) {
            Write-Host "  Installing $($tool.Key) ($($tool.Value))..." -ForegroundColor DarkCyan
            try {
                winget install -e --id $tool.Value --accept-source-agreements --accept-package-agreements --silent 2>$null | Out-Null
            }
            catch { }
        }
    }

    # PowerShell modules
    try {
        if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
        }
    }
    catch { }

    foreach ($mod in @('PSFzf', 'Terminal-Icons')) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            Write-Host "  Installing PowerShell module $mod..." -ForegroundColor DarkCyan
            try {
                Install-Module -Name $mod -Scope CurrentUser -Force -ErrorAction SilentlyContinue
            }
            catch { }
        }
    }

    # Refresh PATH preserving session additions
    try {
        $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
        $userPath    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
        $allPaths    = ("$machinePath;$userPath;$env:Path" -split ';') | Select-Object -Unique | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $env:Path    = $allPaths -join ';'
    }
    catch { }

    try {
        New-Item -Path $script:BootstrapMarker -ItemType File -Force | Out-Null
    }
    catch { }

    Write-Host "Dependency check complete. Restart shell once if tools were just installed.`n" -ForegroundColor Green
}

# Run bootstrap check & startup check
Update-ProfileDependencies
Show-OllamaStartupWarning

# ---------------------------------------------------------------------
# Help aggregator
# ---------------------------------------------------------------------
function Show-ProfileHelp {
    <#
    .SYNOPSIS
        Shows a cheat sheet of all NMJ commands and hotkeys.
    .DESCRIPTION
        Aggregates help from loaded modules and shortcuts.json.
        Usage: myhelp / nmjhelp
               myhelp shortcuts
               myhelp ai
    #>
    param(
        [Parameter(Position = 0)]
        [string]$Section
    )

    $helpText = @"
=== NMJ Commands & Hotkeys ===
(type myhelp or nmjhelp any time)

[🤖 AI Assistant (Ollama)]
  askai "..."       Ask a question – answer lands in buffer or is printed
  fixit             Explain / fix the last error
  aish              Interactive chat with the current model
  Note              Requires Ollama + a model (default: qwen2.5-coder:7b)

[📁 Fuzzy Navigation]
  nf / Find-FuzzyFolder   zoxide first, then Everything + fzf
  z / zi                  plain zoxide
  Ctrl+t                  fuzzy file/dir insert (PSFzf)

[🧰 Modern CLI & Shell]
  ls → eza, cat → bat, sudo → gsudo, rg
  ll / lt                 eza detailed / tree
  uv                      Python package management & completions

[📜 History (Atuin)]
  Ctrl+R                  Atuin interactive history search
  atuin search            Search history
  atuin history list      List history
  Get-AtuinHistory        PowerShell history search wrapper

[🎨 Themes]
  Set-Theme <name|number> [-Perm]
  set-icon / Set-Icon     FastFetch icon themes
  ff                      Run FastFetch with current theme

[🚀 Shortcuts]
  Defined in `$HOME\.nmj\shortcuts.json`
  Supports multi-format invocation:
    ollama.logs / ollama logs / ollama.debugs / ollama debugs
  Use 'myhelp shortcuts' to list all custom shortcuts.
  Add new: New-Shortcut -Name <name> -Command <cmd> / -Path <exe>

[⚙️ Dependencies]
  Update-ProfileDependencies -Force

Tip: Use the built-in -? flag on any shortcut or command for detailed help.
"@

    if ($Section -match 'shortcut|cmd|alias') {
        if (Get-Command Get-NMJShortcutHelp -ErrorAction SilentlyContinue) {
            Get-NMJShortcutHelp
            return
        }
    }

    Write-Host $helpText -ForegroundColor Cyan
}

Set-Alias -Name myhelp  -Value Show-ProfileHelp -Force -ErrorAction SilentlyContinue
Set-Alias -Name nmjhelp -Value Show-ProfileHelp -Force -ErrorAction SilentlyContinue

Export-ModuleMember -Function Update-ProfileDependencies, Show-ProfileHelp, Get-NMJConfigPath, Expand-NMJPath, Write-NMJWarning, Assert-OllamaAvailable, Test-OllamaInstalled -Alias myhelp, nmjhelp
