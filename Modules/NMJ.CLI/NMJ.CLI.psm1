# =====================================================================
# NMJ.CLI — Modern CLI Replacements, Shell Completions & PSReadLine Setup
# =====================================================================

# this changed: skip uv completions on reload; cache and defer the generated script
function Initialize-NMJUvCompletions {
    if ($Global:NMJ_UV_COMPLETIONS) { return }
    $uvCmd = Get-Command uv -ErrorAction SilentlyContinue
    if (-not $uvCmd) { return }
    try {
        $initFile = $null
        if (Get-Command Get-NMJCachedInitPath -ErrorAction SilentlyContinue) {
            $initFile = Get-NMJCachedInitPath -Name 'uv-completion' -BinaryPath $uvCmd.Source
            if (-not $initFile) {
                $initFile = Set-NMJCachedInit -Name 'uv-completion' -Script (uv generate-shell-completion powershell 2>$null | Out-String)
            }
        }
        if ($initFile) {
            . $initFile
        }
        else {
            (& uv generate-shell-completion powershell 2>$null) | Out-String | Invoke-Expression
        }
        $Global:NMJ_UV_COMPLETIONS = $true
    }
    catch {
        if ($env:PROFILE_DEBUG) {
            Write-Host "[NMJ.CLI] uv shell completion init failed: $_" -ForegroundColor DarkGray
        }
    }
}

# 2. Modern CLI Replacements
# eza -> ls / ll / lt
if (Get-Command eza -ErrorAction SilentlyContinue) {
    Set-Alias -Name ls -Value eza -Force -ErrorAction SilentlyContinue

    function ll {
        [CmdletBinding()]
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [string[]]$ArgumentList
        )
        eza -la --icons --git @ArgumentList
    }

    function lt {
        [CmdletBinding()]
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [string[]]$ArgumentList
        )
        eza -T --icons --git-ignore @ArgumentList
    }
}

# bat -> cat
if (Get-Command bat -ErrorAction SilentlyContinue) {
    Set-Alias -Name cat -Value bat -Force -ErrorAction SilentlyContinue
}

# gsudo -> sudo
if (Get-Command gsudo -ErrorAction SilentlyContinue) {
    Set-Alias -Name sudo -Value gsudo -Force -ErrorAction SilentlyContinue
}

# this changed: defer Terminal-Icons, PSFzf, and uv completions until idle
Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
    if (-not (Get-Module -Name Terminal-Icons -ErrorAction SilentlyContinue)) {
        Import-Module Terminal-Icons -ErrorAction SilentlyContinue
    }
    if (-not (Get-Module -Name PSFzf -ErrorAction SilentlyContinue)) {
        Import-Module PSFzf -ErrorAction SilentlyContinue
        Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -ErrorAction SilentlyContinue
    }
    Initialize-NMJUvCompletions
} | Out-Null

# 4. PSReadLine Predictive IntelliSense (ListView)
try {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    $isInteractiveConsole = if (Get-Command Test-NMJInteractiveHost -ErrorAction SilentlyContinue) {
        Test-NMJInteractiveHost
    }
    else {
        [Environment]::UserInteractive -and $Host.Name -ne 'ServerRemoteHost' -and -not [Console]::IsOutputRedirected
    }
    if ($isInteractiveConsole) {
        Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue
        Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction SilentlyContinue
    }
}
catch { }

Export-ModuleMember -Function ll, lt, Initialize-NMJUvCompletions -Alias ls, cat, sudo
