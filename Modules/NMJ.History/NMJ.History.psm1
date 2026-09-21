# =====================================================================
# NMJ.History — Atuin integration
# =====================================================================

if (Get-Command atuin -ErrorAction SilentlyContinue) {
    try {
        Invoke-Expression (& { (atuin init powershell 2>$null | Out-String) })
    }
    catch {
        if ($env:PROFILE_DEBUG) {
            Write-Host "[NMJ.History] Failed to init Atuin: $_" -ForegroundColor DarkGray
        }
    }
}

function Get-AtuinHistory {
    <#
    .SYNOPSIS
        List or search Atuin history.
    .EXAMPLE
        Get-AtuinHistory git
        Get-AtuinHistory -Interactive
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Query,
        [switch]$Interactive
    )
    if (-not (Get-Command atuin -ErrorAction SilentlyContinue)) {
        Write-Host "[NMJ] Atuin is not installed. Run: Update-ProfileDependencies -Force" -ForegroundColor Yellow
        return
    }
    try {
        if ($Interactive -or -not $Query) {
            atuin search
        }
        else {
            atuin search $Query
        }
    }
    catch {
        Write-Host "[NMJ.History] Atuin search error: $_" -ForegroundColor Yellow
    }
}

Export-ModuleMember -Function Get-AtuinHistory
