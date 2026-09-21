# =====================================================================
# NMJ.History — Atuin integration
# Replaces the old Clear-ConsoleHistory / Sort-ConsoleHistory system.
# Predictive IntelliSense (PSReadLine History) remains enabled in the profile.
# =====================================================================

if (Get-Command atuin -ErrorAction SilentlyContinue) {
    # Initialize Atuin for PowerShell
    # This sets up Ctrl+R to the Atuin TUI and records commands automatically.
    try {
        Invoke-Expression (& { (atuin init powershell | Out-String) })
    }
    catch {
        Write-Host "[NMJ.History] Failed to init Atuin: $_" -ForegroundColor Yellow
    }
}
else {
    # Atuin not yet installed (bootstrap will get it on next -Force or first run).
    # We silently continue; the old PSReadLine history still works.
}

# Optional convenience wrappers (thin)
function Get-AtuinHistory {
    <#
    .SYNOPSIS
        List or search Atuin history.
    #>
    param(
        [string]$Query,
        [switch]$Interactive
    )
    if (-not (Get-Command atuin -ErrorAction SilentlyContinue)) {
        Write-Host "[NMJ] Atuin is not installed. Run Update-ProfileDependencies -Force" -ForegroundColor Yellow
        return
    }
    if ($Interactive -or -not $Query) {
        atuin search
    }
    else {
        atuin search $Query
    }
}

Export-ModuleMember -Function Get-AtuinHistory
