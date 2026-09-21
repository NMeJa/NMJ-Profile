# =====================================================================
# NMJ.Core — Bootstrap, shared helpers, Ollama warning logic, help aggregator
# =====================================================================

$script:BootstrapMarker     = Join-Path $HOME '.ps_profile_bootstrap_v2'
$script:OllamaWarnCounter   = Join-Path $env:NMJ_CONFIG 'ollama_warn_count.txt'
$script:MaxOllamaWarnings   = 3

# ---------------------------------------------------------------------
# Path helpers
# ---------------------------------------------------------------------
function Get-NMJConfigPath {
    param([string]$Name = 'shortcuts.json')
    Join-Path $env:NMJ_CONFIG $Name
}

function Expand-NMJPath {
    <#
    .SYNOPSIS
        Expands dynamic tags in paths ($HOME$, $LOCALAPPDATA$, $APPDATA$, $TEMP$, $USERPROFILE$).
    #>
    param([Parameter(Mandatory)][string]$Path)
    $expanded = $Path
    $expanded = $expanded.Replace('$HOME$', $HOME)
    $expanded = $expanded.Replace('$USERPROFILE$', $env:USERPROFILE)
    $expanded = $expanded.Replace('$LOCALAPPDATA$', $env:LOCALAPPDATA)
    $expanded = $expanded.Replace('$APPDATA$', $env:APPDATA)
    $expanded = $expanded.Replace('$TEMP$', $env:TEMP)
    $expanded = $expanded.Replace('$USERNAME$', $env:USERNAME)
    return $expanded
}

function Write-NMJWarning {
    param([string]$Message, [string]$Color = 'Yellow')
    Write-Host "[NMJ] $Message" -ForegroundColor $Color
}

# ---------------------------------------------------------------------
# Ollama presence check with 3-warning limit
# ---------------------------------------------------------------------
function Test-OllamaInstalled {
    return [bool](Get-Command ollama -ErrorAction SilentlyContinue)
}

function Get-OllamaWarnCount {
    if (Test-Path $script:OllamaWarnCounter) {
        $raw = Get-Content $script:OllamaWarnCounter -ErrorAction SilentlyContinue
        $count = 0
        if ([int]::TryParse($raw, [ref]$count)) { return $count }
    }
    return 0
}

function Set-OllamaWarnCount {
    param([int]$Value)
    $dir = Split-Path $script:OllamaWarnCounter -Parent
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    Set-Content -Path $script:OllamaWarnCounter -Value $Value -Encoding utf8
}

function Assert-OllamaAvailable {
    <#
    .SYNOPSIS
        Called by AI commands. Always warns if Ollama is missing.
    #>
    if (Test-OllamaInstalled) { return $true }

    Write-NMJWarning "Ollama is not installed or not in PATH." 'Red'
    Write-Host "  Install from https://ollama.com  then restart the terminal." -ForegroundColor DarkYellow
    Write-Host "  After install, pull a model:  ollama pull qwen2.5-coder:7b" -ForegroundColor DarkYellow
    return $false
}

function Show-OllamaStartupWarning {
    <#
    .SYNOPSIS
        Called once per profile load. Warns at most 3 times, then stops.
    #>
    if (Test-OllamaInstalled) { return }

    $count = Get-OllamaWarnCount
    if ($count -ge $script:MaxOllamaWarnings) { return }

    $remaining = $script:MaxOllamaWarnings - $count - 1
    Write-NMJWarning "Ollama is not installed (warning $($count + 1)/$($script:MaxOllamaWarnings))."
    Write-Host "  This warning will be shown $remaining more time(s), then silenced." -ForegroundColor DarkYellow
    Write-Host "  Install: https://ollama.com   |   Then: ollama pull qwen2.5-coder:7b" -ForegroundColor DarkYellow
    Set-OllamaWarnCount ($count + 1)
}

# ---------------------------------------------------------------------
# Dependency Bootstrap (winget + modules)
# ---------------------------------------------------------------------
function Update-ProfileDependencies {
    [CmdletBinding()]
    param([switch]$Force)

    if ((Test-Path $script:BootstrapMarker) -and -not $Force) { return }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-NMJWarning "winget not found - skipping automatic tool install. Install 'App Installer' from Microsoft Store, then run Update-ProfileDependencies -Force."
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
        'atuin'      = 'Atuinsh.Atuin'          # new
    }

    # Everything GUI
    if (-not (winget list --id voidtools.Everything -e 2>$null | Select-String 'voidtools.Everything')) {
        Write-Host "  Installing Everything (voidtools.Everything)..." -ForegroundColor DarkCyan
        winget install -e --id voidtools.Everything --accept-source-agreements --accept-package-agreements --silent | Out-Null
    }

    foreach ($tool in $wingetTools.GetEnumerator()) {
        if (-not (Get-Command $tool.Key -ErrorAction SilentlyContinue)) {
            Write-Host "  Installing $($tool.Key) ($($tool.Value))..." -ForegroundColor DarkCyan
            winget install -e --id $tool.Value --accept-source-agreements --accept-package-agreements --silent | Out-Null
        }
    }

    # PowerShell modules
    if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    }
    foreach ($mod in @('PSFzf', 'Terminal-Icons')) {
        if (-not (Get-Module -ListAvailable -Name $mod)) {
            Write-Host "  Installing PowerShell module $mod..." -ForegroundColor DarkCyan
            Install-Module -Name $mod -Scope CurrentUser -Force -ErrorAction SilentlyContinue
        }
    }

    # Refresh PATH
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path    = "$machinePath;$userPath"

    New-Item -Path $script:BootstrapMarker -ItemType File -Force | Out-Null
    Write-Host "Dependency check complete. Restart the shell once if tools were just installed.`n" -ForegroundColor Green
}

# Run bootstrap + Ollama soft warning on every load
Update-ProfileDependencies
Show-OllamaStartupWarning

# ---------------------------------------------------------------------
# Help aggregator (reads comment-based help + Shortcuts JSON)
# ---------------------------------------------------------------------
function Show-ProfileHelp {
    <#
    .SYNOPSIS
        Shows a cheat sheet of all NMJ commands and hotkeys.
    .DESCRIPTION
        Aggregates help from loaded modules and the Shortcuts JSON.
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
  askai "..."     Ask a question – answer lands in buffer or is printed
  fixit           Explain / fix the last error
  aish            Interactive chat with the current model
  Note            Requires Ollama + a model (default: qwen2.5-coder:7b)

[📁 Fuzzy Navigation]
  nf / Find-FuzzyFolder   zoxide first, then Everything + fzf
  z / zi                  plain zoxide
  Ctrl+t                  fuzzy file/dir insert (PSFzf)
  Alt+c                   fuzzy cd (PSFzf)

[📜 History (Atuin)]
  Ctrl+R                  Atuin interactive history search (default)
  atuin search            Search history
  atuin history list      List history
  atuin import powershell Import old PSReadLine history (one-time)

[🎨 Themes]
  Set-Theme <name|number> [-Perm]
  set-icon / Set-Icon     FastFetch icon themes
  ff                      Run FastFetch with current theme

[🧰 Modern CLI]
  ls → eza, cat → bat, sudo → gsudo, rg
  ll / lt                 eza long / tree

[🚀 Shortcuts]
  Defined in `$HOME\.nmj\shortcuts.json`
  Every shortcut answers -? / -help
  Use New-Shortcut to add new ones

[⚙️ Dependencies]
  Update-ProfileDependencies -Force

Tip: Use the built-in -? flag on any command for detailed help.
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

Export-ModuleMember -Function * -Alias *
