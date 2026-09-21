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

# Load saved theme silently on import
$themeConfig = Get-ThemeConfig
if (-not [string]::IsNullOrWhiteSpace($themeConfig.main) -and (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    try {
        Import-Module PSReadLine -ErrorAction SilentlyContinue
        $resolvedTheme = Resolve-PoshThemePath $themeConfig.main
        oh-my-posh init pwsh --config $resolvedTheme 2>$null | Invoke-Expression
    }
    catch { }
}

function Set-Theme {
    <#
    .SYNOPSIS
        Switch Oh My Posh theme (active session or permanent).
    .EXAMPLE
        Set-Theme 5
        Set-Theme tokyonight -Permanent
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)][string]$Name,
        [Alias('Perm')][switch]$Permanent
    )

    $targetTheme = $Name
    if ($Global:PoshThemePresets.Contains($Name)) {
        $targetTheme = $Global:PoshThemePresets[$Name]
    }

    $resolved = Resolve-PoshThemePath $targetTheme

    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        try {
            oh-my-posh init pwsh --config $resolved | Invoke-Expression
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
            if ($Global:CurrentFastFetchConfig -and (Test-Path $Global:CurrentFastFetchConfig)) {
                fastfetch.exe --config $Global:CurrentFastFetchConfig @args
            }
            else {
                fastfetch.exe @args
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
    #>
    param(
        [Parameter(Position = 0)][string]$Name,
        [Alias('Perm')][switch]$Permanent,
        [Alias('q')][switch]$Quiet
    )

    $themesRoot = Get-FastFetchThemesRoot
    if (-not (Test-Path $themesRoot)) {
        if (-not $Quiet) {
            Write-Host "[!] FastFetch themes folder not found at: $themesRoot" -ForegroundColor Yellow
            Write-Host "    You can change the folder with: Set-FastFetchThemesFolder <path> -Permanent" -ForegroundColor DarkGray
        }
        return
    }

    $themeDirs = Get-ChildItem -Path $themesRoot -Directory -ErrorAction SilentlyContinue
    if (-not $themeDirs -or $themeDirs.Count -eq 0) {
        if (-not $Quiet) {
            Write-Host "[!] No theme folders found inside $themesRoot" -ForegroundColor Yellow
        }
        return
    }

    $selectedFolder = $null
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -eq 'list' -or $Name -eq '?') {
        if (Get-Command fzf -ErrorAction SilentlyContinue) {
            $chosen = $themeDirs.Name | fzf --prompt="Select FastFetch Icon Theme > " --height=40% --layout=reverse --border
            if ([string]::IsNullOrWhiteSpace($chosen)) {
                Write-Host "`n[!] Selection cancelled." -ForegroundColor Yellow
                return
            }
            $selectedFolder = $themeDirs | Where-Object { $_.Name -eq $chosen }
        }
        else {
            Write-Host "`nAvailable FastFetch Icon Themes ($themesRoot):" -ForegroundColor Cyan
            $themeDirs | ForEach-Object { Write-Host " - $($_.Name)" }
            return
        }
    }
    else {
        $formattedNum = $Name
        if ([int]::TryParse($Name, [ref]$null)) {
            $formattedNum = "{0:D2}" -f [int]$Name
        }
        $selectedFolder = $themeDirs | Where-Object {
            $_.Name -like "$formattedNum - *" -or
            $_.Name -eq $Name -or
            $_.Name -like "*$Name*"
        } | Select-Object -First 1
    }

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

# Apply saved icon theme quietly on load
if (-not [string]::IsNullOrWhiteSpace($themeConfig.icon)) {
    Set-FastFetchIconTheme -Name $themeConfig.icon -Quiet
}

Export-ModuleMember -Function Set-Theme, Set-FastFetchIconTheme, Invoke-FastFetch, Set-FastFetchThemesFolder, Get-FastFetchThemesRoot -Alias ff, set-icon, Set-Icon
