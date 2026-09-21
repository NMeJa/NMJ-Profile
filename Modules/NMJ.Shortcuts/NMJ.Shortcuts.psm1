# =====================================================================
# NMJ.Shortcuts — JSON-driven custom commands / aliases
# File: $HOME\.nmj\shortcuts.json
# Supports: path (exe), command (script), aliases, description, hierarchical names
# =====================================================================

$script:ShortcutsFile = Get-NMJConfigPath 'shortcuts.json'
$script:ShortcutCache = $null

function Initialize-ShortcutsFile {
    if (-not (Test-Path $script:ShortcutsFile)) {
        $dir = Split-Path $script:ShortcutsFile -Parent
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        $default = @{
            version   = '1.0'
            shortcuts = @()
        }
        $default | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ShortcutsFile -Encoding utf8
    }
}

function Read-Shortcuts {
    Initialize-ShortcutsFile
    try {
        $json = Get-Content -Path $script:ShortcutsFile -Raw -ErrorAction Stop
        $data = $json | ConvertFrom-Json
        $script:ShortcutCache = $data
        return $data
    }
    catch {
        Write-Host "[NMJ.Shortcuts] Failed to read shortcuts.json: $_" -ForegroundColor Red
        return @{ version = '1.0'; shortcuts = @() }
    }
}

function Save-Shortcuts {
    param($Data)
    $Data | ConvertTo-Json -Depth 6 | Set-Content -Path $script:ShortcutsFile -Encoding utf8
    $script:ShortcutCache = $Data
}

function Expand-ShortcutPath {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    return (Expand-NMJPath $Value)
}

function New-Shortcut {
    <#
    .SYNOPSIS
        Create a new shortcut (exe or arbitrary command).
    .DESCRIPTION
        Adds an entry to $HOME\.nmj\shortcuts.json and registers it immediately.
    .PARAMETER Name
        Primary name (e.g. ollama.log or unity66). Dots and dashes are allowed.
    .PARAMETER Path
        Path to an executable. Supports $HOME$, $LOCALAPPDATA$, etc.
    .PARAMETER Command
        Arbitrary PowerShell command string (or scriptblock as string).
    .PARAMETER Alias
        One or more additional names that also trigger this shortcut.
    .PARAMETER Description
        Shown by -? / -help and in myhelp shortcuts.
    .EXAMPLE
        New-Shortcut -Name ollama.log -Command 'Get-Content $env:LOCALAPPDATA\Ollama\server.log -Tail 50 -Wait' -Description 'Tail Ollama server log'
    .EXAMPLE
        New-Shortcut -Name unity66 -Path 'C:\Program Files\Unity\Hub\Editor\6000.6.0f1\Editor\Unity.exe' -Alias @('u66') -Description 'Launch Unity 6.6'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [string]$Path,
        [string]$Command,

        [string[]]$Alias = @(),
        [string]$Description = '',
        [switch]$Force
    )

    if (-not $Path -and -not $Command) {
        Write-Host "You must supply either -Path or -Command." -ForegroundColor Red
        return
    }

    $data = Read-Shortcuts
    $existing = $data.shortcuts | Where-Object { $_.name -eq $Name -or ($_.alias -contains $Name) }
    if ($existing -and -not $Force) {
        Write-Host "Shortcut '$Name' already exists. Use -Force to overwrite." -ForegroundColor Yellow
        return
    }

    # Remove old entry if forcing
    if ($existing) {
        $data.shortcuts = @($data.shortcuts | Where-Object { $_.name -ne $Name })
    }

    $entry = [ordered]@{
        name        = $Name
        path        = $Path
        command     = $Command
        alias       = @($Alias)
        description = $Description
    }

    $data.shortcuts += $entry
    Save-Shortcuts $data
    Register-Shortcut $entry
    Write-Host "Shortcut '$Name' created." -ForegroundColor Green
}

function Get-Shortcut {
    <#
    .SYNOPSIS
        List or retrieve shortcuts.
    #>
    param([string]$Name)
    $data = Read-Shortcuts
    if ($Name) {
        return $data.shortcuts | Where-Object {
            $_.name -eq $Name -or ($_.alias -contains $Name)
        }
    }
    return $data.shortcuts
}

function Remove-Shortcut {
    <#
    .SYNOPSIS
        Remove a shortcut by name.
    #>
    param(
        [Parameter(Mandatory)][string]$Name
    )
    $data = Read-Shortcuts
    $before = $data.shortcuts.Count
    $data.shortcuts = @($data.shortcuts | Where-Object {
        $_.name -ne $Name -and -not ($_.alias -contains $Name)
    })
    if ($data.shortcuts.Count -lt $before) {
        Save-Shortcuts $data
        Write-Host "Shortcut '$Name' removed." -ForegroundColor Green
    }
    else {
        Write-Host "Shortcut '$Name' not found." -ForegroundColor Yellow
    }
}

function Register-Shortcut {
    param($Entry)

    $allNames = @($Entry.name) + @($Entry.alias)
    foreach ($n in $allNames) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }

        # Create a function with a safe name
        $safeName = $n -replace '[^a-zA-Z0-9_]', '_'
        $funcName = "Invoke-NMJ_$safeName"

        $scriptBlock = {
            param(
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$Args
            )

            # Help handling
            if ($Args -contains '-?' -or $Args -contains '-help' -or $Args -contains '--help') {
                $desc = $Entry.description
                if (-not $desc) { $desc = '(no description)' }
                Write-Host "`nShortcut: $($Entry.name)" -ForegroundColor Cyan
                Write-Host "Description: $desc"
                if ($Entry.alias) { Write-Host "Aliases: $($Entry.alias -join ', ')" }
                if ($Entry.path)    { Write-Host "Path: $($Entry.path)" }
                if ($Entry.command) { Write-Host "Command: $($Entry.command)" }
                Write-Host ""
                return
            }

            if ($Entry.path) {
                $exe = Expand-ShortcutPath $Entry.path
                if (-not (Test-Path $exe)) {
                    Write-Host "[NMJ] Executable not found: $exe" -ForegroundColor Red
                    return
                }
                & $exe @Args
            }
            elseif ($Entry.command) {
                $cmd = Expand-ShortcutPath $Entry.command
                # Allow both string commands and simple scriptblocks stored as strings
                Invoke-Expression $cmd
            }
        }.GetNewClosure()

        # Register as a function in the global scope so it is callable
        Set-Item -Path "Function:global:$funcName" -Value $scriptBlock -Force

        # Also create a simple alias / function with the original name when possible
        # For names with dots we rely on the dispatcher below
        if ($n -notmatch '[.\s-]') {
            Set-Alias -Name $n -Value $funcName -Scope Global -Force -ErrorAction SilentlyContinue
        }
    }
}

# Hierarchical / dotted / dashed dispatcher
# Allows: ollama.log, ollama log, ollama-debug, ollama.debug
function Invoke-NMJShortcut {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$Rest
    )

    $data = Read-Shortcuts
    $entry = $data.shortcuts | Where-Object {
        $_.name -eq $Name -or
        ($_.alias -contains $Name) -or
        $_.name -eq ($Name -replace '-', '.') -or
        $_.name -eq ($Name -replace '\.', '-')
    } | Select-Object -First 1

    if (-not $entry) {
        # Try splitting "ollama log" style
        Write-Host "Shortcut '$Name' not found. Use Get-Shortcut or myhelp shortcuts." -ForegroundColor Yellow
        return
    }

    # Re-use the same logic as Register-Shortcut
    if ($Rest -contains '-?' -or $Rest -contains '-help' -or $Rest -contains '--help') {
        $desc = $entry.description
        if (-not $desc) { $desc = '(no description)' }
        Write-Host "`nShortcut: $($entry.name)" -ForegroundColor Cyan
        Write-Host "Description: $desc"
        if ($entry.alias) { Write-Host "Aliases: $($entry.alias -join ', ')" }
        if ($entry.path)    { Write-Host "Path: $($entry.path)" }
        if ($entry.command) { Write-Host "Command: $($entry.command)" }
        Write-Host ""
        return
    }

    if ($entry.path) {
        $exe = Expand-ShortcutPath $entry.path
        if (-not (Test-Path $exe)) {
            Write-Host "[NMJ] Executable not found: $exe" -ForegroundColor Red
            return
        }
        & $exe @Rest
    }
    elseif ($entry.command) {
        $cmd = Expand-ShortcutPath $entry.command
        Invoke-Expression $cmd
    }
}

function Get-NMJShortcutHelp {
    $data = Read-Shortcuts
    if (-not $data.shortcuts -or $data.shortcuts.Count -eq 0) {
        Write-Host "No shortcuts defined yet. Use New-Shortcut to create some." -ForegroundColor Yellow
        return
    }
    Write-Host "`n=== NMJ Shortcuts ===" -ForegroundColor Cyan
    foreach ($s in $data.shortcuts) {
        $aliases = if ($s.alias) { "  (aliases: $($s.alias -join ', '))" } else { '' }
        $desc = if ($s.description) { $s.description } else { '(no description)' }
        Write-Host ("  {0,-25} {1}{2}" -f $s.name, $desc, $aliases)
    }
    Write-Host ""
}

# Load and register everything on module import
$data = Read-Shortcuts
foreach ($entry in $data.shortcuts) {
    Register-Shortcut $entry
}

# Make a top-level dispatcher available for dotted names
# Users can call:  Invoke-NMJShortcut ollama.log
# or we can later add a more sophisticated parser if needed.

Export-ModuleMember -Function New-Shortcut, Get-Shortcut, Remove-Shortcut, Get-NMJShortcutHelp, Invoke-NMJShortcut
