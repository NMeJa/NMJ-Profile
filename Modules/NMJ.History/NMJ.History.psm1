# =====================================================================
# NMJ.History — Atuin integration
# =====================================================================

function Initialize-NMJAtuin {
    # this changed: skip re-init when Atuin is already loaded (avoids "replacing it" on . $profile)
    if (Get-Module -Name Atuin -ErrorAction SilentlyContinue) { return }

    $atuinCmd = Get-Command atuin -ErrorAction SilentlyContinue
    if (-not $atuinCmd) { return }

    try {
        $initFile = $null
        if (Get-Command Get-NMJCachedInitPath -ErrorAction SilentlyContinue) {
            $initFile = Get-NMJCachedInitPath -Name 'atuin' -BinaryPath $atuinCmd.Source
            if (-not $initFile) {
                $initFile = Set-NMJCachedInit -Name 'atuin' -Script (atuin init powershell 2>$null | Out-String)
            }
        }
        if ($initFile) {
            . $initFile
        }
        else {
            Invoke-Expression (& { (atuin init powershell 2>$null | Out-String) })
        }
    }
    catch {
        if ($env:PROFILE_DEBUG) {
            Write-Host "[NMJ.History] Failed to init Atuin: $_" -ForegroundColor DarkGray
        }
    }
}

# this changed: defer Atuin to OnIdle so the ~100ms module build is off the profile clock
if (Get-Command atuin -ErrorAction SilentlyContinue) {
    Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
        Initialize-NMJAtuin
    } | Out-Null
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
    Initialize-NMJAtuin
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

Export-ModuleMember -Function Get-AtuinHistory, Initialize-NMJAtuin
