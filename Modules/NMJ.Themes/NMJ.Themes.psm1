# =====================================================================
# NMJ.Themes — Oh My Posh + FastFetch
# Themes directory defaults to .nmj/Themes (configurable manually by user)
# =====================================================================

$themeConfigFile = Join-Path $HOME '.posh_theme'

$Global:PoshThemePresets = [ordered]@{
    '1'  = 'jandedobbeleer'
    '2'  = 'if_tea'
    '3'  = 'wholespace'
    '4'  = 'catppuccin_mocha'
    '5'  = 'tokyonight'
    '6'  = 'nord'
    '7'  = 'gruvbox'
    '8'  = 'paradox'
    '9'  = 'agnoster'
    '10' = 'catppuccin_frappe'
}

function Get-ThemeConfig {
    if (-not (Test-Path $themeConfigFile)) {
        return @{ main = $Global:PoshThemePresets['1']; icon = ''; themesRoot = '' }
    }
    try {
        $content = Get-Content -Path $themeConfigFile -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($content)) {
            return @{ main = $Global:PoshThemePresets['1']; icon = ''; themesRoot = '' }
        }
        $json = $content | ConvertFrom-Json -ErrorAction Stop
        return @{
            main       = if ($json.main) { $json.main } else { $Global:PoshThemePresets['1'] }
            icon       = if ($json.icon) { $json.icon } else { '' }
            themesRoot = if ($json.themesRoot) { $json.themesRoot } else { '' }
        }
    }
    catch {
        $clean = if ($content) { $content.Trim() } else { $Global:PoshThemePresets['1'] }
        return @{ main = $clean; icon = ''; themesRoot = '' }
    }
}

function Save-ThemeConfig {
    param(
        [string]$Main,
        [string]$Icon,
        [string]$ThemesRoot
    )
    try {
        $current = Get-ThemeConfig
        $newMain = if ($PSBoundParameters.ContainsKey('Main')) { $Main } else { $current.main }
        $newIcon = if ($PSBoundParameters.ContainsKey('Icon')) { $Icon } else { $current.icon }
        $newRoot = if ($PSBoundParameters.ContainsKey('ThemesRoot')) { $ThemesRoot } else { $current.themesRoot }
        [ordered]@{
            main       = $newMain
            icon       = $newIcon
            themesRoot = $newRoot
        } | ConvertTo-Json | Set-Content -Path $themeConfigFile -Encoding utf8 -ErrorAction SilentlyContinue
    }
    catch { }
}

function Get-FastFetchThemesRoot {
    <#
    .SYNOPSIS
        Resolves the FastFetch icon themes root directory.
        Priority:
          1. $env:FASTFETCH_THEMES_ROOT
          2. Saved config in ~/.posh_theme (.themesRoot)
          3. $Global:FastFetchThemesRoot (session override)
          4. .nmj/Themes (under $env:NMJ_CONFIG or $HOME\.nmj\Themes)
          5. Local repository .nmj/Themes fallback
    #>
    if ($env:FASTFETCH_THEMES_ROOT -and (Test-Path $env:FASTFETCH_THEMES_ROOT)) {
        return (Resolve-Path $env:FASTFETCH_THEMES_ROOT).Path
    }

    $cfg = Get-ThemeConfig
    if ($cfg.themesRoot -and (Test-Path $cfg.themesRoot)) {
        return (Resolve-Path $cfg.themesRoot).Path
    }

    if ($Global:FastFetchThemesRoot -and (Test-Path $Global:FastFetchThemesRoot)) {
        return (Resolve-Path $Global:FastFetchThemesRoot).Path
    }

    # Default: .nmj/Themes
    $configBase = if ($env:NMJ_CONFIG) { $env:NMJ_CONFIG } else { Join-Path $HOME '.nmj' }
    $defaultNmjThemes = Join-Path $configBase 'Themes'
    if (Test-Path $defaultNmjThemes) {
        return (Resolve-Path $defaultNmjThemes).Path
    }

    $homeNmjThemes = Join-Path $HOME '.nmj\Themes'
    if (Test-Path $homeNmjThemes) {
        return (Resolve-Path $homeNmjThemes).Path
    }

    return $defaultNmjThemes
}

function Set-FastFetchThemesFolder {
    <#
    .SYNOPSIS
        Manually set or change the FastFetch icon themes directory.
    .EXAMPLE
        Set-FastFetchThemesFolder "D:\MyThemes" -Permanent
        Set-FastFetchThemesFolder (Join-Path $HOME '.nmj\Themes')
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [Alias('Perm')]
        [switch]$Permanent
    )

    if (-not (Test-Path $Path)) {
        Write-Host "[NMJ.Themes] Directory does not exist: $Path" -ForegroundColor Yellow
        return
    }

    $resolved = (Resolve-Path $Path).Path
    $Global:FastFetchThemesRoot = $resolved

    if ($Permanent) {
        Save-ThemeConfig -ThemesRoot $resolved
        Write-Host "Saved FastFetch themes directory to '$resolved' as permanent default." -ForegroundColor Green
    }
    else {
        Write-Host "Set active session FastFetch themes directory to '$resolved'." -ForegroundColor Cyan
    }
}

function Resolve-PoshThemePath {
    param([string]$ThemeNameOrPath)
    if ([string]::IsNullOrWhiteSpace($ThemeNameOrPath)) { return $ThemeNameOrPath }

    # If it's a file path or URL, return directly
    if (Test-Path $ThemeNameOrPath -ErrorAction SilentlyContinue) {
        return (Resolve-Path $ThemeNameOrPath).Path
    }
    if ($ThemeNameOrPath -match '^https?://') {
        return $ThemeNameOrPath
    }

    # Check $env:POSH_THEMES_PATH
    if ($env:POSH_THEMES_PATH) {
        $candidate1 = Join-Path $env:POSH_THEMES_PATH "$ThemeNameOrPath.omp.json"
        if (Test-Path $candidate1) { return $candidate1 }
        $candidate2 = Join-Path $env:POSH_THEMES_PATH "$ThemeNameOrPath.json"
        if (Test-Path $candidate2) { return $candidate2 }
    }

    return $ThemeNameOrPath
}

function Get-NMJOhMyPoshExe {
    # this changed: the WindowsApps alias is a 0-byte stub that swallows `init` stdout
    if ($Global:NMJ_OMP_EXE -and (Test-Path -LiteralPath $Global:NMJ_OMP_EXE) -and (Get-Item -LiteralPath $Global:NMJ_OMP_EXE).Length -gt 0) {
        return $Global:NMJ_OMP_EXE
    }

    $cacheFile = $null
    $configBase = if ($env:NMJ_CONFIG) { $env:NMJ_CONFIG } else { Join-Path $HOME '.nmj' }
    $cacheFile = Join-Path $configBase 'cache\omp.exe.path'

    if ($cacheFile -and (Test-Path -LiteralPath $cacheFile)) {
        $cached = (Get-Content -LiteralPath $cacheFile -Raw -ErrorAction SilentlyContinue).Trim()
        if ($cached -and (Test-Path -LiteralPath $cached) -and (Get-Item -LiteralPath $cached).Length -gt 0) {
            return $cached
        }
    }

    $resolved = $null
    $cmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path -LiteralPath $cmd.Source) -and (Get-Item -LiteralPath $cmd.Source).Length -gt 0) {
        $resolved = $cmd.Source
    }
    else {
        try {
            $pkg = Get-AppxPackage -Name 'ohmyposh.cli' -ErrorAction SilentlyContinue
            if ($pkg -and $pkg.InstallLocation) {
                $real = Join-Path $pkg.InstallLocation 'oh-my-posh.exe'
                if (Test-Path -LiteralPath $real) { $resolved = $real }
            }
        }
        catch { }
    }

    if ($resolved -and $cacheFile) {
        try {
            $dir = Split-Path $cacheFile -Parent
            if (-not (Test-Path -LiteralPath $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
            }
            Set-Content -LiteralPath $cacheFile -Value $resolved -Encoding utf8NoBOM
        }
        catch { }
    }

    return $resolved
}

function Initialize-NMJPoshPrompt {
    param([string]$ThemeNameOrPath)

    $exe = Get-NMJOhMyPoshExe
    if (-not $exe) { return }

    if (-not $env:POSH_THEMES_PATH) {
        $themeDir = Join-Path (Split-Path $exe -Parent) 'themes'
        if (Test-Path -LiteralPath $themeDir) {
            $env:POSH_THEMES_PATH = $themeDir
        }
    }

    $config = Resolve-PoshThemePath $ThemeNameOrPath
    $Global:NMJ_OMP_EXE = $exe
    $Global:NMJ_OMP_CONFIG = $config

    # this changed: skip `oh-my-posh init` (empty under the MSIX alias) and render via print primary
    function global:prompt {
        $ok = $?
        $lastCode = $global:LASTEXITCODE
        $status = if ($ok) { 0 } elseif ($lastCode) { $lastCode } else { 1 }
        $pwdPath = $PWD.ProviderPath
        $ompArgs = @(
            'print', 'primary'
            '--shell', 'pwsh'
            '--status', "$status"
            '--pwd', $pwdPath
            '--pswd', $pwdPath
        )
        if ($Global:NMJ_OMP_CONFIG) {
            $ompArgs += @('--config', $Global:NMJ_OMP_CONFIG)
        }
        $rendered = & $Global:NMJ_OMP_EXE @ompArgs
        $global:LASTEXITCODE = $lastCode
        if ($rendered) { return $rendered }
        return "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
    }

    $Global:NMJ_OMP_INITIALIZED = $true
}

# Load saved theme silently on import
$themeConfig = Get-ThemeConfig
if (-not $Global:NMJ_OMP_INITIALIZED -and -not [string]::IsNullOrWhiteSpace($themeConfig.main)) {
    try {
        Import-Module PSReadLine -ErrorAction SilentlyContinue
        Initialize-NMJPoshPrompt -ThemeNameOrPath $themeConfig.main
    }
    catch {
        if ($env:PROFILE_DEBUG) {
            Write-Host "[NMJ.Themes] Oh My Posh init failed: $_" -ForegroundColor DarkGray
        }
    }
}

function Show-NMJAppearanceHelp {
    Write-Host @"

NMJ appearance
  nmj [-Help|-?]
  nmj theme [-List|-l | -Choose|-c | <name|number>] [-Permanent|-Perm]
  nmj icon  [-List|-l | -Choose|-c | <name|number>] [-Permanent|-Perm]

Same commands:
  Set-Theme ...              = nmj theme ...
  set-icon / Set-Icon ...    = nmj icon ...
  ff                         reprint FastFetch with the current icon

Examples:
  nmj theme -l               list Oh My Posh presets
  nmj theme -c -Perm         pick a prompt theme (fzf) and save it
  nmj theme 5 -Permanent     tokyonight, persist
  nmj icon -l                list FastFetch icon packs
  nmj icon -c                pick an icon pack
  nmj icon wolf -Perm        save the wolf pack

"@ -ForegroundColor Cyan
}

function Show-NMJPoshThemeList {
    $current = (Get-ThemeConfig).main
    Write-Host "`nOh My Posh presets:" -ForegroundColor Cyan
    foreach ($k in $Global:PoshThemePresets.Keys) {
        $name = $Global:PoshThemePresets[$k]
        $mark = if ($name -eq $current) { ' *' } else { '' }
        Write-Host ("  {0,2}  {1}{2}" -f $k, $name, $mark)
    }
    Write-Host "  (* current)  Any other Oh My Posh theme name or path also works." -ForegroundColor DarkGray
    Write-Host ""
}

function Select-NMJPoshThemeInteractive {
    $rows = foreach ($k in $Global:PoshThemePresets.Keys) {
        '{0,2}  {1}' -f $k, $Global:PoshThemePresets[$k]
    }
    $chosen = $null
    if (Get-Command fzf -ErrorAction SilentlyContinue) {
        $chosen = @($rows) | fzf --prompt="Select Oh My Posh theme > " --height=40% --layout=reverse --border
    }
    else {
        Show-NMJPoshThemeList
        $chosen = Read-Host "Theme number or name"
    }
    if ([string]::IsNullOrWhiteSpace($chosen)) { return $null }
    if ($chosen -match '^\s*(\d+)\b') { return $Matches[1] }
    return $chosen.Trim()
}

function Get-NMJIconThemeDirs {
    $root = Get-FastFetchThemesRoot
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    @(Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue)
}

function Show-NMJIconThemeList {
    $root = Get-FastFetchThemesRoot
    $dirs = Get-NMJIconThemeDirs
    if (-not $dirs -or $dirs.Count -eq 0) {
        Write-Host "[!] No FastFetch icon themes in: $root" -ForegroundColor Yellow
        return
    }
    $current = (Get-ThemeConfig).icon
    Write-Host "`nFastFetch icon themes ($root):" -ForegroundColor Cyan
    foreach ($d in $dirs) {
        $mark = if ($d.Name -eq $current) { ' *' } else { '' }
        Write-Host ("  - {0}{1}" -f $d.Name, $mark)
    }
    Write-Host "  (* current)" -ForegroundColor DarkGray
    Write-Host ""
}

function Select-NMJIconThemeInteractive {
    $dirs = Get-NMJIconThemeDirs
    if (-not $dirs -or $dirs.Count -eq 0) {
        Show-NMJIconThemeList
        return $null
    }
    $chosen = $null
    if (Get-Command fzf -ErrorAction SilentlyContinue) {
        $chosen = @($dirs.Name) | fzf --prompt="Select FastFetch icon theme > " --height=40% --layout=reverse --border
    }
    else {
        Show-NMJIconThemeList
        $chosen = Read-Host "Icon theme name or number"
    }
    if ([string]::IsNullOrWhiteSpace($chosen)) { return $null }
    return $chosen.Trim()
}

function Set-Theme {
    <#
    .SYNOPSIS
        Switch Oh My Posh theme (active session or permanent).
    .DESCRIPTION
        nmj theme / Set-Theme. Use -List, -Choose, or a preset number/name.
        nmj -? and Set-Theme -? show the same cheat sheet via -Help.
    .EXAMPLE
        nmj theme -List
        Set-Theme -Choose -Permanent
        Set-Theme 5
        Set-Theme tokyonight -Permanent
    #>
    [CmdletBinding(DefaultParameterSetName = 'Help')]
    param(
        [Parameter(ParameterSetName = 'ByName', Position = 0, Mandatory)]
        [string]$Name,

        [Parameter(ParameterSetName = 'List')]
        [Alias('l')]
        [switch]$List,

        [Parameter(ParameterSetName = 'Choose')]
        [Alias('c')]
        [switch]$Choose,

        [Parameter(ParameterSetName = 'Help')]
        [Alias('h')]
        [switch]$Help,

        [Parameter(ParameterSetName = 'ByName')]
        [Parameter(ParameterSetName = 'Choose')]
        [Alias('Perm')]
        [switch]$Permanent
    )

    if ($PSCmdlet.ParameterSetName -eq 'Help' -or $Help) {
        Show-NMJAppearanceHelp
        return
    }
    if ($List) {
        Show-NMJPoshThemeList
        return
    }
    if ($Choose) {
        $picked = Select-NMJPoshThemeInteractive
        if ([string]::IsNullOrWhiteSpace($picked)) {
            Write-Host "`n[!] Selection cancelled." -ForegroundColor Yellow
            return
        }
        $Name = $picked
    }

    $targetTheme = $Name
    if ($Global:PoshThemePresets.Contains($Name)) {
        $targetTheme = $Global:PoshThemePresets[$Name]
    }

    $resolved = Resolve-PoshThemePath $targetTheme

    if (Get-NMJOhMyPoshExe) {
        try {
            Initialize-NMJPoshPrompt -ThemeNameOrPath $resolved
        }
        catch {
            Write-Host "[NMJ.Themes] Failed to apply Oh My Posh theme '$resolved': $_" -ForegroundColor Yellow
            return
        }
    }
    else {
        Write-Host "[NMJ.Themes] oh-my-posh not found in PATH." -ForegroundColor Yellow
        return
    }

    if ($Permanent) {
        Save-ThemeConfig -Main $targetTheme
        Write-Host "Set prompt theme to '$targetTheme' as permanent default." -ForegroundColor Green
    }
    else {
        Write-Host "Switched active session prompt theme to '$targetTheme'." -ForegroundColor Cyan
    }
}

function Invoke-FastFetch {
    <#
    .SYNOPSIS
        Runs fastfetch with configured theme.
    #>
    if (Get-Command fastfetch -ErrorAction SilentlyContinue) {
        try {
            # this changed: --pipe false + no PowerShell pipeline so $1–$9 logo colors survive
            $ffArgs = @('--pipe', 'false')
            if ($Global:CurrentFastFetchConfig -and (Test-Path -LiteralPath $Global:CurrentFastFetchConfig)) {
                $ffArgs += @('--config', $Global:CurrentFastFetchConfig)
            }
            $ffArgs += @args

            $prevRendering = $null
            if ($PSStyle) {
                $prevRendering = $PSStyle.OutputRendering
                $PSStyle.OutputRendering = [System.Management.Automation.OutputRendering]::Ansi
            }
            try {
                & fastfetch.exe @ffArgs
            }
            finally {
                if ($null -ne $prevRendering) {
                    $PSStyle.OutputRendering = $prevRendering
                }
            }
        }
        catch { }
    }
    else {
        Write-Host "[!] FastFetch not found in PATH." -ForegroundColor Yellow
    }
}
Set-Alias -Name ff -Value Invoke-FastFetch -Force -ErrorAction SilentlyContinue

function Set-FastFetchIconTheme {
    <#
    .SYNOPSIS
        Switch FastFetch icon themes. Default root is .nmj/Themes.
    .DESCRIPTION
        nmj icon / set-icon / Set-Icon. Use -List, -Choose, or a folder name/number.
    .EXAMPLE
        nmj icon -List
        set-icon -Choose
        Set-Icon wolf -Permanent
    #>
    [CmdletBinding(DefaultParameterSetName = 'Help')]
    param(
        [Parameter(ParameterSetName = 'ByName', Position = 0)]
        [string]$Name,

        [Parameter(ParameterSetName = 'List')]
        [Alias('l')]
        [switch]$List,

        [Parameter(ParameterSetName = 'Choose')]
        [Alias('c')]
        [switch]$Choose,

        [Parameter(ParameterSetName = 'Help')]
        [Alias('h')]
        [switch]$Help,

        [Parameter(ParameterSetName = 'ByName')]
        [Parameter(ParameterSetName = 'Choose')]
        [Alias('Perm')]
        [switch]$Permanent,

        [Parameter(ParameterSetName = 'ByName')]
        [Alias('q')]
        [switch]$Quiet
    )

    if ($PSCmdlet.ParameterSetName -eq 'Help' -or $Help) {
        Show-NMJAppearanceHelp
        return
    }
    if ($List -or $Name -eq 'list' -or $Name -eq '?') {
        Show-NMJIconThemeList
        return
    }
    if ($Choose -or [string]::IsNullOrWhiteSpace($Name)) {
        $picked = Select-NMJIconThemeInteractive
        if ([string]::IsNullOrWhiteSpace($picked)) {
            if (-not $Quiet) {
                Write-Host "`n[!] Selection cancelled." -ForegroundColor Yellow
            }
            return
        }
        $Name = $picked
    }

    $themesRoot = Get-FastFetchThemesRoot
    if (-not (Test-Path $themesRoot)) {
        if (-not $Quiet) {
            Write-Host "[!] FastFetch themes folder not found at: $themesRoot" -ForegroundColor Yellow
            Write-Host "    You can change the folder with: Set-FastFetchThemesFolder <path> -Permanent" -ForegroundColor DarkGray
        }
        return
    }

    $themeDirs = Get-NMJIconThemeDirs
    if (-not $themeDirs -or $themeDirs.Count -eq 0) {
        if (-not $Quiet) {
            Write-Host "[!] No theme folders found inside $themesRoot" -ForegroundColor Yellow
        }
        return
    }

    $formattedNum = $Name
    if ([int]::TryParse($Name, [ref]$null)) {
        $formattedNum = "{0:D2}" -f [int]$Name
    }
    $selectedFolder = $themeDirs | Where-Object {
        $_.Name -like "$formattedNum - *" -or
        $_.Name -eq $Name -or
        $_.Name -like "*$Name*"
    } | Select-Object -First 1

    if (-not $selectedFolder) {
        if (-not $Quiet) {
            Write-Host "`n[!] Could not find any FastFetch theme matching '$Name' in $themesRoot." -ForegroundColor Yellow
        }
        return
    }

    $configPath = Join-Path $selectedFolder.FullName 'config.jsonc'
    if (-not (Test-Path $configPath)) {
        if (-not $Quiet) {
            Write-Host "`n[!] config.jsonc missing in $($selectedFolder.FullName)" -ForegroundColor Red
        }
        return
    }

    $env:themeRoot = $selectedFolder.FullName.Replace('\', '/')
    $Global:CurrentFastFetchConfig = $configPath

    if (-not $Quiet) {
        Write-Host "`nSwitched FastFetch icon theme to '$($selectedFolder.Name)'." -ForegroundColor Green
        Invoke-FastFetch
    }
    if ($Permanent) {
        Save-ThemeConfig -Icon $selectedFolder.Name
        if (-not $Quiet) {
            Write-Host "Saved '$($selectedFolder.Name)' as permanent FastFetch default." -ForegroundColor Green
        }
    }
}

Set-Alias -Name set-icon -Value Set-FastFetchIconTheme -Force -ErrorAction SilentlyContinue
Set-Alias -Name Set-Icon -Value Set-FastFetchIconTheme -Force -ErrorAction SilentlyContinue

function Invoke-NMJ {
    <#
    .SYNOPSIS
        NMJ appearance dispatcher: prompt themes and FastFetch icons.
    .DESCRIPTION
        nmj theme ... and nmj icon ... are the collision-free entry points.
        -? shows this help. Does not use `set`, which is Set-Variable.
    .EXAMPLE
        nmj
        nmj theme -List
        nmj icon -Choose -Permanent
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Command,

        [Parameter(Position = 1)]
        [string]$Name,

        [Alias('l')]
        [switch]$List,

        [Alias('c')]
        [switch]$Choose,

        [Alias('h')]
        [switch]$Help,

        [Alias('Perm')]
        [switch]$Permanent
    )

    $noun = if ($Command) { $Command.Trim().ToLowerInvariant() } else { '' }

    if ($Help -or $noun -eq 'help' -or $noun -eq '?' -or (
            [string]::IsNullOrWhiteSpace($noun) -and -not $List -and -not $Choose -and [string]::IsNullOrWhiteSpace($Name)
        )) {
        Show-NMJAppearanceHelp
        return
    }

    switch -Regex ($noun) {
        '^(theme|themes|t|prompt)$' {
            if ($List) { Set-Theme -List; return }
            if ($Choose) { Set-Theme -Choose -Permanent:$Permanent; return }
            if (-not [string]::IsNullOrWhiteSpace($Name)) {
                Set-Theme -Name $Name -Permanent:$Permanent
                return
            }
            Show-NMJAppearanceHelp
            return
        }
        '^(icon|icons|i|logo)$' {
            if ($List) { Set-FastFetchIconTheme -List; return }
            if ($Choose) { Set-FastFetchIconTheme -Choose -Permanent:$Permanent; return }
            if (-not [string]::IsNullOrWhiteSpace($Name)) {
                Set-FastFetchIconTheme -Name $Name -Permanent:$Permanent
                return
            }
            Show-NMJAppearanceHelp
            return
        }
        default {
            Write-Host "[NMJ] Unknown command '$Command'. Use: nmj theme | nmj icon" -ForegroundColor Yellow
            Show-NMJAppearanceHelp
        }
    }
}

Set-Alias -Name nmj -Value Invoke-NMJ -Force -ErrorAction SilentlyContinue

# this changed: apply saved (or first) icon theme; banner is printed by the profile loader
if ([string]::IsNullOrWhiteSpace($themeConfig.icon)) {
    $themesRoot = Get-FastFetchThemesRoot
    if (Test-Path -LiteralPath $themesRoot) {
        $firstTheme = Get-ChildItem -Path $themesRoot -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($firstTheme) {
            $themeConfig.icon = $firstTheme.Name
        }
    }
}
if (-not [string]::IsNullOrWhiteSpace($themeConfig.icon)) {
    Set-FastFetchIconTheme -Name $themeConfig.icon -Quiet
}

Export-ModuleMember -Function Set-Theme, Set-FastFetchIconTheme, Invoke-FastFetch, Set-FastFetchThemesFolder, Get-FastFetchThemesRoot, Invoke-NMJ -Alias ff, set-icon, Set-Icon, nmj
