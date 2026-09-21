@{
    ModuleVersion     = '1.1.0'
    GUID              = 'd4e5f6a7-b8c9-0123-def0-234567890123'
    Author            = 'NMJ'
    Description       = 'JSON-based custom shortcuts and command dispatching supporting dotted and spaced subcommands'
    PowerShellVersion = '7.0'
    RequiredModules   = @('NMJ.Core')
    RootModule        = 'NMJ.Shortcuts.psm1'
    FunctionsToExport = @(
        'New-Shortcut'
        'Get-Shortcut'
        'Remove-Shortcut'
        'Get-NMJShortcutHelp'
        'Invoke-NMJShortcut'
        'Find-NMJShortcutBySubcommand'
        'Invoke-NMJShortcutEntry'
    )
    AliasesToExport   = @()
}
