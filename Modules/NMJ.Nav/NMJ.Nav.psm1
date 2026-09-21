# =====================================================================
# NMJ.Nav — Fuzzy Navigation (zoxide + Everything CLI / fzf)
# =====================================================================

# Initialize zoxide silently if present
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    try {
        Invoke-Expression (& { (zoxide init powershell | Out-String) })
    }
    catch {
        if ($env:PROFILE_DEBUG) {
            Write-Host "[NMJ.Nav] Failed to initialize zoxide: $_" -ForegroundColor Yellow
        }
    }
}

function Find-FuzzyFolder {
    <#
    .SYNOPSIS
        Fuzzy navigate to folders using zoxide first, then Everything (es.exe) and fzf.
    .EXAMPLE
        nf Documents
        nf myproject -All
        Find-FuzzyFolder src -Disk D
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Target,

        [Alias('h')]
        [switch]$Hidden,

        [switch]$All,

        [string]$Disk = 'C',

        [switch]$SkipZoxide
    )

    # 1. Try zoxide first
    if (-not $SkipZoxide -and (Get-Command zoxide -ErrorAction SilentlyContinue)) {
        try {
            $zoxideMatch = (zoxide query -- $Target 2>$null)
            if ($LASTEXITCODE -eq 0 -and $zoxideMatch -and (Test-Path $zoxideMatch)) {
                Write-Host "`nNavigating to (zoxide): $zoxideMatch" -ForegroundColor Green
                Set-Location $zoxideMatch
                return
            }
        }
        catch {
            if ($env:PROFILE_DEBUG) {
                Write-Host "[NMJ.Nav] zoxide query failed: $_" -ForegroundColor DarkGray
            }
        }
    }

    # 2. Check for Everything CLI (es.exe)
    $hasEs = [bool](Get-Command es -ErrorAction SilentlyContinue) -or [bool](Get-Command es.exe -ErrorAction SilentlyContinue)
    if (-not $hasEs) {
        Write-Host "`n[!] Everything CLI (es.exe) is not installed or not in PATH." -ForegroundColor Yellow
        Write-Host "    Install via: Update-ProfileDependencies -Force" -ForegroundColor DarkGray
        return
    }

    $basePath = if ($All -or $Disk -ne 'C') { "$($Disk):" } else { $HOME }
    $esArgs = @($basePath)
    if (-not $Hidden) {
        $esArgs += '!path:AppData'
        $esArgs += '/a-h'
    }

    $results = @()
    try {
        $exactArgs = @("folder:$Target") + $esArgs
        $results = @(& es.exe $exactArgs -n 50 2>$null)

        if ($results.Count -eq 0) {
            $fuzzyArgs = @("folder:*$Target*") + $esArgs
            $results = @(& es.exe $fuzzyArgs -n 50 2>$null)
        }
    }
    catch {
        Write-Host "`n[!] Everything search failed: $_" -ForegroundColor Red
        return
    }

    $isTypoFallback = $false
    if ($results.Count -eq 0 -and $Target.Length -ge 3) {
        $prefix = $Target.Substring(0, 3)
        $typoArgs = @("folder:*$prefix*") + $esArgs
        try {
            $results = @(& es.exe $typoArgs -n 200 2>$null)
            $isTypoFallback = $true
        }
        catch { }
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

    # Check for fzf
    $hasFzf = [bool](Get-Command fzf -ErrorAction SilentlyContinue)
    $selected = $null

    if ($hasFzf) {
        try {
            if ($isTypoFallback) {
                $selected = $results | fzf --prompt="Select folder ($Target) > " --height=40% --layout=reverse --border --query="$Target"
            }
            else {
                $selected = $results | fzf --prompt="Select folder ($Target) > " --height=40% --layout=reverse --border
            }
        }
        catch {
            Write-Host "`n[!] fzf selection failed: $_" -ForegroundColor Red
            return
        }
    }
    else {
        # Fallback without fzf: pick top result or show brief numbered list
        Write-Host "`n[!] fzf is not installed. Navigating to the closest match:" -ForegroundColor DarkYellow
        $selected = $results[0]
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
Set-Alias -Name nf             -Value Find-FuzzyFolder -Force -ErrorAction SilentlyContinue

Export-ModuleMember -Function Find-FuzzyFolder -Alias Navigate-Fuzzy, nf
