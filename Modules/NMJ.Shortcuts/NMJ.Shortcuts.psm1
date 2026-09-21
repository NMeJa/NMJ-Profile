# =====================================================================
# NMJ.Shortcuts — JSON-driven custom commands / aliases
# File: $HOME\.nmj\shortcuts.json
# Supports: dotted names, spaced subcommands (e.g. ollama logs / ollama.logs),
#           argument forwarding, help flags (-?, -help), and native command proxying.
# =====================================================================

$script:ShortcutsFile = Get-NMJConfigPath 'shortcuts.json'
$script:ShortcutCache = $null

function Initialize-ShortcutsFile {
    if (-not (Test-Path $script:ShortcutsFile)) {
        try {
            $dir = Split-Path $script:ShortcutsFile -Parent
            if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
            $default = @{
                version   = '1.0'
                shortcuts = @()
            }
            $default | ConvertTo-Json -Depth 5 | Set-Content -Path $script:ShortcutsFile -Encoding utf8
        }
        catch { }
    }
}

function Read-Shortcuts {
    Initialize-ShortcutsFile
    try {
        $raw = Get-Content -Path $script:ShortcutsFile -Raw -ErrorAction Stop
        $data = $raw | ConvertFrom-Json
        if (-not $data.shortcuts) {
            $data.shortcuts = @()
        }
        else {
            $data.shortcuts = @($data.shortcuts)
        }
        $script:ShortcutCache = $data
        return $data
    }
    catch {
        if ($env:PROFILE_DEBUG) {
            Write-Host "[NMJ.Shortcuts] Failed to read shortcuts.json: $_" -ForegroundColor DarkGray
        }
        return @{ version = '1.0'; shortcuts = @() }
    }
}

function Save-Shortcuts {
    param($Data)
    try {
        if (-not $Data.shortcuts) { $Data.shortcuts = @() }
        $Data | ConvertTo-Json -Depth 6 | Set-Content -Path $script:ShortcutsFile -Encoding utf8
        $script:ShortcutCache = $Data
    }
    catch {
        Write-Host "[NMJ.Shortcuts] Failed to save shortcuts: $_" -ForegroundColor Red
    }
}

function Expand-ShortcutPath {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    if (Get-Command Expand-NMJPath -ErrorAction SilentlyContinue) {
        return (Expand-NMJPath $Value)
    }
    return $Value
}

function Show-SingleShortcutHelp {
    param($Entry)
    $desc = if ($Entry.description) { $Entry.description } else { '(no description)' }
    Write-Host "`nShortcut: $($Entry.name)" -ForegroundColor Cyan
    Write-Host "Description: $desc"
    if ($Entry.alias) {
        $aliasList = @($Entry.alias) -join ', '
        Write-Host "Aliases: $aliasList"
    }
    if ($Entry.path)    { Write-Host "Path: $($Entry.path)" }
    if ($Entry.command) { Write-Host "Command: $($Entry.command)" }
    Write-Host ""
}

function Invoke-NMJShortcutEntry {
    param(
        [Parameter(Mandatory)]
        $Entry,
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$Arguments = @()
    )

    if ($Arguments -contains '-?' -or $Arguments -contains '-help' -or $Arguments -contains '--help') {
        Show-SingleShortcutHelp $Entry
        return
    }

    if ($Entry.path) {
        $exe = Expand-ShortcutPath $Entry.path
        if (-not (Test-Path $exe)) {
            Write-Host "[NMJ.Shortcuts] Executable not found: $exe" -ForegroundColor Red
            return
        }
        try {
            & $exe @Arguments
        }
        catch {
            Write-Host "[NMJ.Shortcuts] Failed to execute '$exe': $_" -ForegroundColor Red
        }
    }
    elseif ($Entry.command) {
        $cmd = Expand-ShortcutPath $Entry.command
        try {
            $sb = [ScriptBlock]::Create($cmd)
            & $sb @Arguments
        }
        catch {
            Write-Host "[NMJ.Shortcuts] Command execution failed: $_" -ForegroundColor Red
        }
    }
}

function Find-NMJShortcutBySubcommand {
    param(
        [string]$Prefix,
        [string]$SubCommand
    )
    $data = Read-Shortcuts
    foreach ($entry in $data.shortcuts) {
        $names = @($entry.name) + @($entry.alias)
        foreach ($name in $names) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            $cleanName = $name.Trim()

            # Matches e.g. "ollama.logs" -> Prefix: "ollama", SubCommand: "logs"
            if ($cleanName -match "^$([regex]::Escape($Prefix))[.\-\s]+$([regex]::Escape($SubCommand))`$") {
                return $entry
            }
            # Or if alias is simply the subcommand itself
            if ($cleanName -eq $SubCommand) {
                return $entry
            }
        }
    }
    return $null
}

function Register-PrefixProxy {
    param([string]$Prefix)
    if ([string]::IsNullOrWhiteSpace($Prefix) -or $Prefix -match '\s') { return }

    $proxyBlock = {
        param(
            [Parameter(ValueFromRemainingArguments = $true)]
            [object[]]$ProxyArgs
        )

        if ($ProxyArgs -and $ProxyArgs.Count -gt 0) {
            $sub = [string]$ProxyArgs[0]
            $matchedEntry = Find-NMJShortcutBySubcommand -Prefix $Prefix -SubCommand $sub
            if ($matchedEntry) {
                $rest = if ($ProxyArgs.Count -gt 1) { $ProxyArgs[1..($ProxyArgs.Count - 1)] } else { @() }
                Invoke-NMJShortcutEntry -Entry $matchedEntry -Arguments $rest
                return
            }
        }

        # Check if a native executable exists with this prefix name (e.g. ollama.exe)
        $nativeApp = (Get-Command -Name "$Prefix.exe", $Prefix -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($nativeApp) {
            & $nativeApp.Source @ProxyArgs
            return
        }

        if ($ProxyArgs -and $ProxyArgs.Count -gt 0) {
            Write-Host "[NMJ.Shortcuts] Unknown subcommand '$($ProxyArgs[0])' for '$Prefix'." -ForegroundColor Yellow
            Write-Host "Type 'myhelp shortcuts' to view all available custom shortcuts." -ForegroundColor DarkGray
        }
        else {
            Write-Host "[NMJ.Shortcuts] '$Prefix' invoked without subcommands, and no native '$Prefix' binary was found in PATH." -ForegroundColor Yellow
        }
    }.GetNewClosure()

    Set-Item -Path "Function:global:$Prefix" -Value $proxyBlock -Force
}

function Register-Shortcut {
    param($Entry)

    $allNames = @($Entry.name) + @($Entry.alias)
    $prefixesToRegister = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($n in $allNames) {
        if ([string]::IsNullOrWhiteSpace($n)) { continue }
        $n = $n.Trim()

        # Track prefixes for names like 'ollama.logs', 'ollama-logs', 'ollama logs'
        if ($n -match '^([a-zA-Z0-9_]+)[.\-\s]([a-zA-Z0-9_\-]+)$') {
            $prefix = $Matches[1]
            [void]$prefixesToRegister.Add($prefix)
        }

        # For space-separated names like 'ollama logs', they will be handled by prefix dispatcher
        if ($n -match '\s') { continue }

        $scriptBlock = {
            param(
                [Parameter(ValueFromRemainingArguments = $true)]
                [object[]]$CallArgs
            )
            Invoke-NMJShortcutEntry -Entry $Entry -Arguments $CallArgs
        }.GetNewClosure()

        # In PowerShell, functions can have dots, underscores, dashes, etc.
        # Direct registration allows running `ollama.logs` or `ollama-logs` directly from the prompt!
        Set-Item -Path "Function:global:$n" -Value $scriptBlock -Force

        # Also register dotted/dashed alternatives
        if ($n -contains '.' -or $n -match '\.') {
            $dashed = $n -replace '\.', '-'
            Set-Item -Path "Function:global:$dashed" -Value $scriptBlock -Force
        }
        elseif ($n -contains '-' -or $n -match '-') {
            $dotted = $n -replace '-', '.'
            Set-Item -Path "Function:global:$dotted" -Value $scriptBlock -Force
        }
    }

    # Register root prefix dispatchers
    foreach ($prefix in $prefixesToRegister) {
        Register-PrefixProxy -Prefix $prefix
    }
}

function New-Shortcut {
    <#
    .SYNOPSIS
        Create a new shortcut (executable or arbitrary command script).
    .DESCRIPTION
        Adds an entry to $HOME\.nmj\shortcuts.json and registers functions and prefix dispatchers immediately.
    .EXAMPLE
        New-Shortcut -Name 'ollama.logs' -Command 'Get-Content $env:LOCALAPPDATA\Ollama\server.log -Tail 50 -Wait' -Alias @('ollama.debugs', 'ollama logs', 'ollama debugs', 'olog') -Description 'Tail Ollama server log'
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
    $existing = @($data.shortcuts) | Where-Object { $_.name -eq $Name -or ($_.alias -contains $Name) }
    if ($existing -and -not $Force) {
        Write-Host "Shortcut '$Name' already exists. Use -Force to overwrite." -ForegroundColor Yellow
        return
    }

    if ($existing) {
        $data.shortcuts = @(@($data.shortcuts) | Where-Object { $_.name -ne $Name })
    }

    $entry = [ordered]@{
        name        = $Name
        path        = $Path
        command     = $Command
        alias       = @($Alias)
        description = $Description
    }

    $data.shortcuts = @($data.shortcuts) + $entry
    Save-Shortcuts $data
    Register-Shortcut $entry
    Write-Host "Shortcut '$Name' created." -ForegroundColor Green
}

function Get-Shortcut {
    <#
    .SYNOPSIS
        List or retrieve shortcuts by name or alias.
    #>
    param([string]$Name)
    $data = Read-Shortcuts
    if ($Name) {
        return @($data.shortcuts) | Where-Object {
            $_.name -eq $Name -or ($_.alias -contains $Name)
        }
    }
    return @($data.shortcuts)
}

function Remove-Shortcut {
    <#
    .SYNOPSIS
        Remove a shortcut by name or alias.
    #>
    param(
        [Parameter(Mandatory)][string]$Name
    )
    $data = Read-Shortcuts
    $before = @($data.shortcuts).Count
    $data.shortcuts = @(@($data.shortcuts) | Where-Object {
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

function Invoke-NMJShortcut {
    <#
    .SYNOPSIS
        Programmatically invoke a shortcut with arguments.
    #>
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$Rest
    )

    $data = Read-Shortcuts
    $entry = @($data.shortcuts) | Where-Object {
        $_.name -eq $Name -or
        ($_.alias -contains $Name) -or
        $_.name -eq ($Name -replace '-', '.') -or
        $_.name -eq ($Name -replace '\.', '-')
    } | Select-Object -First 1

    if (-not $entry) {
        Write-Host "Shortcut '$Name' not found. Use Get-Shortcut or myhelp shortcuts." -ForegroundColor Yellow
        return
    }

    Invoke-NMJShortcutEntry -Entry $entry -Arguments $Rest
}

function Get-NMJShortcutHelp {
    <#
    .SYNOPSIS
        Display all registered shortcuts formatted cleanly.
    #>
    $data = Read-Shortcuts
    $shortcuts = @($data.shortcuts)
    if (-not $shortcuts -or $shortcuts.Count -eq 0) {
        Write-Host "No shortcuts defined yet. Use New-Shortcut to create one." -ForegroundColor Yellow
        return
    }
    Write-Host "`n=== NMJ Shortcuts ===" -ForegroundColor Cyan
    foreach ($s in $shortcuts) {
        $aliases = if ($s.alias) { "  (aliases: $($s.alias -join ', '))" } else { '' }
        $desc = if ($s.description) { $s.description } else { '(no description)' }
        Write-Host ("  {0,-25} {1}{2}" -f $s.name, $desc, $aliases)
    }
    Write-Host ""
}

# Register all shortcuts on module import
$initData = Read-Shortcuts
foreach ($entry in @($initData.shortcuts)) {
    Register-Shortcut $entry
}

Export-ModuleMember -Function New-Shortcut, Get-Shortcut, Remove-Shortcut, Get-NMJShortcutHelp, Invoke-NMJShortcut, Find-NMJShortcutBySubcommand, Invoke-NMJShortcutEntry
