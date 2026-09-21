# =====================================================================
# NMJ.AI — Local Ollama wrapper
# Commands: askai, fixit, aish
# Default model: qwen2.5-coder:7b  (configurable)
# =====================================================================

$script:DefaultModel   = 'qwen2.5-coder:7b'
$script:OllamaEndpoint = 'http://localhost:11434'

function Get-AIContext {
    <#
    .SYNOPSIS
        Builds a short context string (cwd, recent history, last error, shell version).
    #>
    $parts = @()
    try {
        $parts += "Current directory: $(Get-Location)"
        $parts += "Shell: PowerShell $($PSVersionTable.PSVersion)"

        # Last error
        if ($Error.Count -gt 0 -and $Error[0]) {
            $err = $Error[0]
            if ($err.Exception -and $err.Exception.Message) {
                $parts += "Last error: $($err.Exception.Message)"
            }
            if ($err.InvocationInfo -and $err.InvocationInfo.Line) {
                $parts += "Failed command: $($err.InvocationInfo.Line.Trim())"
            }
        }

        # Recent history
        $hist = Get-History -Count 10 -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty CommandLine -Unique |
                Select-Object -Last 6
        if ($hist) {
            $parts += "Recent commands:`n" + ($hist -join "`n")
        }
    }
    catch { }

    return ($parts -join "`n")
}

function Invoke-Ollama {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [string]$System = 'You are a helpful PowerShell and Windows terminal expert. Reply with concise, correct PowerShell code or explanations. Prefer pure PowerShell solutions.',
        [string]$Model = $script:DefaultModel,
        [switch]$Raw
    )

    if (-not (Assert-OllamaAvailable)) { return $null }

    $body = @{
        model  = $Model
        prompt = $Prompt
        system = $System
        stream = $false
    } | ConvertTo-Json -Depth 5

    try {
        $response = Invoke-RestMethod -Uri "$script:OllamaEndpoint/api/generate" `
                                      -Method Post `
                                      -Body $body `
                                      -ContentType 'application/json; charset=utf-8' `
                                      -TimeoutSec 120 `
                                      -ErrorAction Stop
        return $response.response
    }
    catch {
        if (-not $Raw) {
            $msg = $_.Exception.Message
            try {
                if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                    $jsonErr = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($jsonErr -and $jsonErr.error) { $msg = $jsonErr.error }
                }
            }
            catch { }

            Write-Host "`n[NMJ.AI] Ollama request failed: $msg" -ForegroundColor Yellow
            if ($msg -match 'not found') {
                Write-Host "  Model '$Model' is missing. Run: ollama pull $Model" -ForegroundColor DarkGray
            }
            elseif ($msg -match 'actively refused|connect|connection') {
                Write-Host "  Ollama service seems offline. Try: ollama serve" -ForegroundColor DarkGray
            }
        }
        return $null
    }
}

function Invoke-AskAI {
    <#
    .SYNOPSIS
        Ask a quick question. The answer is printed and code is optionally inserted into the buffer.
    .EXAMPLE
        askai "how do I find the largest 5 files in C:\Temp?"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$Query
    )

    $question = $Query -join ' '
    if ([string]::IsNullOrWhiteSpace($question)) {
        Write-Host "Usage: askai `"your question`"" -ForegroundColor Yellow
        return
    }

    $context = Get-AIContext
    $fullPrompt = @"
Context:
$context

User question:
$question

Answer with the most useful PowerShell command or short explanation. If you output code, put it in a single code block.
"@

    Write-Host "Thinking..." -ForegroundColor DarkGray
    $answer = Invoke-Ollama -Prompt $fullPrompt
    if (-not $answer) { return }

    Write-Host "`n$answer`n" -ForegroundColor Cyan

    # Try to extract code block and insert into PSReadLine buffer
    if ($answer -match '(?s)```(?:powershell|pwsh)?\s*(.+?)```') {
        $code = $Matches[1].Trim()
        try {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($code)
            Write-Host "(Code inserted into buffer – press Enter to run)" -ForegroundColor DarkGreen
        }
        catch { }
    }
}

function Invoke-FixIt {
    <#
    .SYNOPSIS
        Explain and suggest a fix for the last error.
    .EXAMPLE
        fixit
    #>
    [CmdletBinding()]
    param()

    if ($Error.Count -eq 0 -or -not $Error[0]) {
        Write-Host "No recent error found in this session." -ForegroundColor Yellow
        return
    }

    $context = Get-AIContext
    $prompt = @"
Context:
$context

The user just encountered this error. Explain what went wrong in plain language and give a corrected PowerShell command.
"@

    Write-Host "Analyzing last error..." -ForegroundColor DarkGray
    $answer = Invoke-Ollama -Prompt $prompt -System 'You are a PowerShell debugging expert. Be concise.'
    if ($answer) {
        Write-Host "`n$answer`n" -ForegroundColor Cyan
    }
}

function Start-AIShell {
    <#
    .SYNOPSIS
        Start an interactive chat session with Ollama.
    .EXAMPLE
        aish
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
        [string[]]$InitialPrompt
    )

    if (-not (Assert-OllamaAvailable)) { return }

    $model = $script:DefaultModel
    Write-Host "Starting interactive session with $model (type 'exit' or Ctrl+C to quit)`n" -ForegroundColor Green

    if ($InitialPrompt) {
        $first = $InitialPrompt -join ' '
        Write-Host "You: $first" -ForegroundColor White
        $answer = Invoke-Ollama -Prompt $first
        if ($answer) { Write-Host "AI: $answer`n" -ForegroundColor Cyan }
    }

    while ($true) {
        try {
            $userInput = Read-Host "You"
            if ([string]::IsNullOrWhiteSpace($userInput)) { continue }
            if ($userInput -match '^(exit|quit|q)$') { break }

            $answer = Invoke-Ollama -Prompt $userInput
            if ($answer) {
                Write-Host "AI: $answer`n" -ForegroundColor Cyan
            }
        }
        catch {
            break
        }
    }
}

Set-Alias -Name askai -Value Invoke-AskAI -Force -ErrorAction SilentlyContinue
Set-Alias -Name fixit -Value Invoke-FixIt -Force -ErrorAction SilentlyContinue
Set-Alias -Name aish  -Value Start-AIShell -Force -ErrorAction SilentlyContinue

Export-ModuleMember -Function Invoke-AskAI, Invoke-FixIt, Start-AIShell -Alias askai, fixit, aish
