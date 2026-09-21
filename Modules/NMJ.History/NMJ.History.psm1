# =====================================================================
# NMJ.History — Atuin integration
# =====================================================================

function Restore-NMJPsReadLineHistoryKeys {
    # this changed: Atuin TUI is Ctrl+R only; Up/Down stay PSReadLine
    if (Get-Command Enable-AtuinSearchKeys -ErrorAction SilentlyContinue) {
        Enable-AtuinSearchKeys -CtrlR $false -UpArrow $false
    }

    try {
        Set-PSReadLineKeyHandler -Chord UpArrow -Function PreviousHistory -ErrorAction SilentlyContinue
        Set-PSReadLineKeyHandler -Chord DownArrow -Function NextHistory -ErrorAction SilentlyContinue
        Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -BriefDescription 'Atuin search' -Description 'Search Atuin history and restore the Oh My Posh prompt' -ScriptBlock {
            Invoke-NMJAtuinSearch
        }
        Set-PSReadLineKeyHandler -Chord 'Ctrl+Alt+d' -BriefDescription 'Forget current command' -Description 'Remove the current line from Atuin/PSReadLine suggestions' -ScriptBlock {
            $line = ''
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$null)
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                Remove-NMJHistory -Command $line -Quiet
            }
        }
    }
    catch { }
}

function Invoke-NMJAtuinSearch {
    <#
    .SYNOPSIS
        Atuin interactive search that redraws the Oh My Posh prompt instead of leaving a leftover PS>.
    #>
    $resultFile = New-TemporaryFile
    $previousOutputEncoding = [System.Console]::OutputEncoding
    try {
        [System.Console]::OutputEncoding = [System.Text.Encoding]::UTF8

        $query = ''
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$query, [ref]$null)

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo.FileName = 'atuin'
        $process.StartInfo.Arguments = "search -i --result-file `"$($resultFile.FullName)`""
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.RedirectStandardError = $true
        $process.StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        $process.StartInfo.WorkingDirectory = (Get-Location -PSProvider FileSystem).ProviderPath
        $process.StartInfo.EnvironmentVariables['ATUIN_SHELL'] = 'powershell'
        $process.StartInfo.EnvironmentVariables['ATUIN_QUERY'] = $query

        $errorOutput = ''
        try {
            $process.Start() | Out-Null
            $errorOutput = $process.StandardError.ReadToEnd().Trim()
            $process.WaitForExit()
        }
        catch {
            $errorOutput = "$_"
        }

        if ($errorOutput) {
            Write-Host -ForegroundColor Red "Atuin error:"
            Write-Host -ForegroundColor DarkRed $errorOutput
        }

        $suggestion = ''
        if (Test-Path -LiteralPath $resultFile.FullName) {
            $suggestion = (Get-Content -LiteralPath $resultFile.FullName -Raw -Encoding UTF8 | Out-String).Trim()
        }

        # this changed: do not pass post-TUI cursor Y — that is what left a ghost `PS>` after Tab
        try {
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
        }
        catch { }
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt()

        if ([string]::IsNullOrWhiteSpace($suggestion)) { return }

        $acceptPrefix = '__atuin_accept__:'
        if ($suggestion.StartsWith($acceptPrefix)) {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($suggestion.Substring($acceptPrefix.Length))
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }
        else {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($suggestion)
        }
    }
    finally {
        [System.Console]::OutputEncoding = $previousOutputEncoding
        Remove-Item -LiteralPath $resultFile.FullName -Force -ErrorAction SilentlyContinue
    }
}

function Import-NMJAtuinHistoryIntoPSReadLine {
    if ($Global:NMJ_ATUIN_HISTORY_SEEDED) { return }
    if (-not (Get-Command atuin -ErrorAction SilentlyContinue)) { return }
    if (-not (Get-Command Get-PSReadLineOption -ErrorAction SilentlyContinue)) { return }

    try {
        $existing = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $histPath = $null
        try { $histPath = (Get-PSReadLineOption).HistorySavePath } catch { }
        if ($histPath -and (Test-Path -LiteralPath $histPath)) {
            foreach ($line in [System.IO.File]::ReadLines($histPath)) {
                if ($line) { [void]$existing.Add($line) }
            }
        }

        $cmds = @(atuin history list --cmd-only -r 2>$null)
        if (-not $cmds -or $cmds.Count -eq 0) {
            $cmds = @(atuin history list --format '{command}' 2>$null)
        }

        $maxImport = 2000
        $added = 0
        $forgotten = Get-NMJHistoryForgetSet
        foreach ($cmd in $cmds) {
            if ([string]::IsNullOrWhiteSpace($cmd)) { continue }
            if ($forgotten.Contains($cmd)) { continue }
            if ($existing.Add($cmd)) {
                [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($cmd)
                $added++
                if ($added -ge $maxImport) { break }
            }
        }

        $Global:NMJ_ATUIN_HISTORY_SEEDED = $true
    }
    catch {
        if ($env:PROFILE_DEBUG) {
            Write-Host "[NMJ.History] Atuin→PSReadLine history import failed: $_" -ForegroundColor DarkGray
        }
    }
}

function Initialize-NMJAtuin {
    if (Get-Module -Name Atuin -ErrorAction SilentlyContinue) {
        Restore-NMJPsReadLineHistoryKeys
        $env:ATUIN_POWERSHELL_PROMPT_OFFSET = '0'
        Register-NMJAtuinPredictor
        return
    }

    $atuinCmd = Get-Command atuin -ErrorAction SilentlyContinue
    if (-not $atuinCmd) { return }

    try {
        $initFile = $null
        if (Get-Command Get-NMJCachedInitPath -ErrorAction SilentlyContinue) {
            # this changed: cache key includes --disable-up-arrow so the old Up-bound script is not reused
            $initFile = Get-NMJCachedInitPath -Name 'atuin-ctrlr' -BinaryPath $atuinCmd.Source
            if (-not $initFile) {
                $script = atuin init powershell --disable-up-arrow 2>$null | Out-String
                if ([string]::IsNullOrWhiteSpace($script)) {
                    $script = atuin init powershell 2>$null | Out-String
                }
                $initFile = Set-NMJCachedInit -Name 'atuin-ctrlr' -Script $script
            }
        }
        if ($initFile) {
            . $initFile
        }
        else {
            Invoke-Expression (& { (atuin init powershell --disable-up-arrow 2>$null | Out-String) })
        }

        Restore-NMJPsReadLineHistoryKeys
        $env:ATUIN_POWERSHELL_PROMPT_OFFSET = '0'
        Register-NMJAtuinPredictor
        Import-NMJAtuinHistoryIntoPSReadLine
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

function Get-NMJHistoryForgetPath {
    $base = if ($env:NMJ_CONFIG) { $env:NMJ_CONFIG } else { Join-Path $HOME '.nmj' }
    $path = Join-Path $base 'history-forget.txt'
    $env:NMJ_HISTORY_FORGET = $path
    return $path
}

function Get-NMJHistoryForgetSet {
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $path = Get-NMJHistoryForgetPath
    if (-not (Test-Path -LiteralPath $path)) { return $set }
    try {
        foreach ($line in [System.IO.File]::ReadLines($path)) {
            if ($line) { [void]$set.Add($line) }
        }
    }
    catch { }
    return $set
}

function Save-NMJHistoryForgetSet {
    param([System.Collections.Generic.HashSet[string]]$Set)
    $path = Get-NMJHistoryForgetPath
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    $lines = @($Set)
    [System.IO.File]::WriteAllLines($path, $lines)
    if ('NMJ.History.AtuinPredictor' -as [type]) {
        [NMJ.History.AtuinPredictor]::InvalidateCache()
    }
}

function Remove-NMJHistoryFromPSReadLineFile {
    param([string]$Command)
    try {
        $histPath = (Get-PSReadLineOption).HistorySavePath
        if (-not $histPath -or -not (Test-Path -LiteralPath $histPath)) { return }
        $kept = [System.Collections.Generic.List[string]]::new()
        foreach ($line in [System.IO.File]::ReadLines($histPath)) {
            if ($line -ne $Command) { [void]$kept.Add($line) }
        }
        [System.IO.File]::WriteAllLines($histPath, $kept)
    }
    catch { }
}

function Remove-NMJHistoryFromAtuin {
    param([string]$Command)
    if (-not (Get-Command atuin -ErrorAction SilentlyContinue)) { return }

    $rows = @(atuin search --format '{command}' --limit 40 --search-mode prefix -- $Command 2>$null)
    $exact = @($rows | Where-Object { $_ -eq $Command })
    $other = @($rows | Where-Object { $_ -and $_ -ne $Command })
    if ($exact.Count -gt 0 -and $other.Count -eq 0) {
        atuin search --delete --limit 40 --search-mode prefix -- $Command 2>$null | Out-Null
    }
}

function Remove-NMJHistory {
    <#
    .SYNOPSIS
        Forget a command so it is never suggested again.
    .DESCRIPTION
        Adds the command to the forget list, removes it from the PSReadLine history file,
        and deletes it from Atuin when the match is exact.
        With no command, pick one (or more) from history with fzf.
    .EXAMPLE
        Remove-NMJHistory 'git statsu'
        nmj history forget
        Ctrl+Alt+D   (while the bad command is on the current line)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments)]
        [string[]]$Command,

        [Alias('c')]
        [switch]$Choose,

        [Alias('q')]
        [switch]$Quiet
    )

    $text = ($Command -join ' ').Trim()
    if ($Choose -or [string]::IsNullOrWhiteSpace($text)) {
        $candidates = @(atuin history list --cmd-only -r 2>$null)
        if (-not $candidates) {
            $candidates = @(atuin search --format '{command}' --limit 200 2>$null)
        }
        $candidates = @($candidates | Where-Object { $_ } | Select-Object -Unique)
        if (-not $candidates) {
            if (-not $Quiet) {
                Write-Host '[NMJ] No history to forget.' -ForegroundColor Yellow
            }
            return
        }
        if (Get-Command fzf -ErrorAction SilentlyContinue) {
            $picked = @($candidates | fzf -m --prompt='Forget command(s) > ' --height=40% --layout=reverse --border)
        }
        else {
            $i = 1
            foreach ($c in ($candidates | Select-Object -First 30)) {
                Write-Host ("  {0,2}  {1}" -f $i, $c)
                $i++
            }
            $raw = Read-Host 'Number or exact command to forget'
            $picked = @()
            $n = 0
            if ([int]::TryParse($raw, [ref]$n) -and $n -ge 1 -and $n -le [Math]::Min(30, $candidates.Count)) {
                $picked = @($candidates[$n - 1])
            }
            elseif ($raw) {
                $picked = @($raw.Trim())
            }
        }
        foreach ($item in @($picked)) {
            if ($item) { Remove-NMJHistory -Command $item -Quiet:$Quiet }
        }
        return
    }

    $set = Get-NMJHistoryForgetSet
    [void]$set.Add($text)
    Save-NMJHistoryForgetSet $set
    Remove-NMJHistoryFromPSReadLineFile $text
    Remove-NMJHistoryFromAtuin $text
    if (-not $Quiet) {
        Write-Host "[NMJ] Forgot: $text" -ForegroundColor DarkYellow
    }
}

function Invoke-NMJHistoryAction {
    param([object[]]$RawRest)

    $tokens = foreach ($a in @($RawRest)) {
        if ($null -ne $a -and "$a") { "$a" }
    }
    if (-not $tokens -or $tokens.Count -eq 0) {
        if (Get-Command Show-ProfileHelp -ErrorAction SilentlyContinue) {
            Show-ProfileHelp history
        }
        return
    }

    $verb = $tokens[0].Trim().TrimStart('-').ToLowerInvariant()
    $rest = if ($tokens.Count -gt 1) { ($tokens[1..($tokens.Count - 1)] -join ' ') } else { '' }

    switch -Regex ($verb) {
        '^(forget|delete|del|rm|f)$' {
            if ($rest) { Remove-NMJHistory -Command $rest } else { Remove-NMJHistory -Choose }
        }
        '^(search|s)$' { Invoke-NMJAtuinSearch }
        '^(list|l)$' { Get-AtuinHistory $rest }
        default {
            if (Get-Command Show-ProfileHelp -ErrorAction SilentlyContinue) {
                Show-ProfileHelp history
            }
        }
    }
}

function Register-NMJAtuinPredictor {
    if ($script:NMJAtuinPredictorRegistered) { return }
    if (-not (Get-Command atuin -ErrorAction SilentlyContinue)) { return }
    if (-not (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue)) { return }

    Get-NMJHistoryForgetPath | Out-Null

    try {
        if (-not ('NMJ.History.AtuinPredictor' -as [type])) {
            $cs = Join-Path $PSScriptRoot 'AtuinPredictor.cs'
            if (-not (Test-Path -LiteralPath $cs)) { return }
            $refDir = Join-Path $PSHOME 'ref'
            $refs = @(
                (Join-Path $PSHOME 'System.Management.Automation.dll')
                (Join-Path $refDir 'System.Runtime.dll')
                (Join-Path $refDir 'System.Collections.dll')
                (Join-Path $refDir 'netstandard.dll')
                (Join-Path $refDir 'System.Diagnostics.Process.dll')
                (Join-Path $refDir 'System.ComponentModel.Primitives.dll')
                (Join-Path $refDir 'System.IO.FileSystem.dll')
                (Join-Path $refDir 'System.Threading.dll')
            ) | Where-Object { Test-Path $_ }
            Add-Type -Path $cs -ReferencedAssemblies $refs -ErrorAction Stop
        }

        $existing = [System.Management.Automation.Subsystem.SubsystemManager]::GetSubsystems(
            [System.Management.Automation.Subsystem.SubsystemKind]::CommandPredictor
        )
        $id = [NMJ.History.AtuinPredictor]::PredictorId
        $already = $false
        foreach ($s in @($existing)) {
            if ($s.Id -eq $id) { $already = $true; break }
        }
        if (-not $already) {
            $predictor = [NMJ.History.AtuinPredictor]::new()
            [System.Management.Automation.Subsystem.SubsystemManager]::RegisterSubsystem(
                [System.Management.Automation.Subsystem.SubsystemKind]::CommandPredictor,
                $predictor
            )
        }

        Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction SilentlyContinue
        Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction SilentlyContinue
        $script:NMJAtuinPredictorRegistered = $true
    }
    catch {
        if ($env:PROFILE_DEBUG) {
            Write-Host "[NMJ.History] Atuin predictor not registered: $_" -ForegroundColor DarkGray
        }
    }
}

$ExecutionContext.SessionState.Module.OnRemove += {
    try {
        if ('NMJ.History.AtuinPredictor' -as [type]) {
            [System.Management.Automation.Subsystem.SubsystemManager]::UnregisterSubsystem(
                [System.Management.Automation.Subsystem.SubsystemKind]::CommandPredictor,
                [NMJ.History.AtuinPredictor]::PredictorId
            )
        }
    }
    catch { }
}

Set-Alias -Name forget -Value Remove-NMJHistory -Force -ErrorAction SilentlyContinue

Export-ModuleMember -Function Get-AtuinHistory, Initialize-NMJAtuin, Invoke-NMJAtuinSearch, Remove-NMJHistory, Invoke-NMJHistoryAction, Register-NMJAtuinPredictor -Alias forget

