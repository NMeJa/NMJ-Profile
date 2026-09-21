# =====================================================================
# NMJ.AI — Local Ollama wrapper
# Commands: askai, fixit, aish
# Default model: qwen2.5-coder:7b  (configurable)
# =====================================================================

$script:DefaultModel = 'qwen2.5-coder:7b'
$script:OllamaEndpoint = 'http://localhost:11434'

function Get-AIContext {
    <#
    .SYNOPSIS
        Builds a short context string (cwd, recent history, last error, loaded modules).
    #>
    $parts = @()
    $parts += "Current directory: $(Get-Location)"
    $parts += "Shell: PowerShell $($PSVersionTable.PSVersion)"

    # Last error
    if ($Error.Count -gt 0 -and $Error[0]) {
        $err = $Error[0]
        $parts += "Last error: $($err.Exception.Message)"
        if ($err.InvocationInfo.Line) {
            $parts += "Failed command: $($err.InvocationInfo.Line.Trim())"
        }
    }

    # Recent history (last 8 unique)
    try {
        $hist = Get-History -Count 12 -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty CommandLine -Unique |
                Select-Object -Last 8
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
                                      -ContentType 'application/json' `
                                      -TimeoutSec 120
        return $response.response
    }
    catch {
        Write-Host "[NMJ.AI] Ollama request failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Is the Ollama service running? Try: ollama serve" -ForegroundColor DarkYellow
        return $null
    }
}

function Invoke-AskAI {
    <#
    .SYNOPSIS
        Ask a quick question. The answer is printed and also inserted into the buffer when possible.
    .EXAMPLE
        askai "how do I list the 5 processes using the most CPU?"
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

    # Try to extract a code block and offer to insert it
    if ($answer -match '(?s)```(?:powershell|pwsh)?\s*(.+?)```') {
        $code = $Matches[1].Trim()
        try {
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($code)
            Write-Host "(code inserted into buffer – press Enter to run)" -ForegroundColor DarkGreen
        }
        catch {
            # non-interactive or PSReadLine not available
        }
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

    if ($Error.Count -eq 0) {
        Write-Host "No recent error found." -ForegroundColor Yellow
        return
    }

    $err = $Error[0]
    $context = Get-AIContext
    $prompt = @"
Context:
$context

The user just hit this error. Explain what went wrong in plain language and give a corrected PowerShell command if possible.
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
        Start an interactive chat session with the current Ollama model.
    .EXAMPLE
        aish
        aish "explain pipelines"
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
        $userInput = Read-Host "You"
        if ([string]::IsNullOrWhiteSpace($userInput)) { continue }
        if ($userInput -match '^(exit|quit|q)$') { break }

        $answer = Invoke-Ollama -Prompt $userInput
        if ($answer) {
            Write-Host "AI: $answer`n" -ForegroundColor Cyan
        }
    }
}

# Aliases
Set-Alias -Name askai -Value Invoke-AskAI -Force -ErrorAction SilentlyContinue
Set-Alias -Name fixit -Value Invoke-FixIt -Force -ErrorAction SilentlyContinue
Set-Alias -Name aish  -Value Start-AIShell -Force -ErrorAction SilentlyContinue

Export-ModuleMember -Function Invoke-AskAI, Invoke-FixIt, Start-AIShell -Alias askai, fixit, aish
