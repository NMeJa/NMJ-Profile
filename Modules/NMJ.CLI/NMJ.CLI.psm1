# =====================================================================
# NMJ.CLI — Modern CLI Replacements, Shell Completions & PSReadLine Setup
# =====================================================================

# 1. Shell completions (uv)
if (Get-Command uv -ErrorAction SilentlyContinue) {
    try {
        (& uv generate-shell-completion powershell 2>$null) | Out-String | Invoke-Expression
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

# 3. Terminal Enhancements Modules
if (Get-Module -ListAvailable -Name Terminal-Icons) {
    try {
        Import-Module Terminal-Icons -ErrorAction SilentlyContinue
    }
    catch { }
}

if (Get-Module -ListAvailable -Name PSFzf) {
    try {
        Import-Module PSFzf -ErrorAction SilentlyContinue
        Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -ErrorAction SilentlyContinue
    }
    catch { }
}

# 4. PSReadLine Predictive IntelliSense (ListView)
try {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    $isInteractiveConsole = $Host.UI.RawUI -and -not [Console]::IsOutputRedirected -and -not [Console]::IsInputRedirected
    if ($isInteractiveConsole) {
        Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue
        Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction SilentlyContinue
    }
}
catch { }

Export-ModuleMember -Function ll, lt -Alias ls, cat, sudo
