@{
    ModuleVersion     = '1.2.2'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'NMJ'
    Description       = 'Core bootstrap, shared helpers and help aggregator for NMJ modules'
    PowerShellVersion = '7.0'
    RootModule        = 'NMJ.Core.psm1'
    FunctionsToExport = @(
        'Update-ProfileDependencies'
        'Show-ProfileHelp'
        'Get-NMJConfigPath'
        'Expand-NMJPath'
        'Write-NMJWarning'
        'Assert-OllamaAvailable'
        'Test-OllamaInstalled'
        'Test-NMJInteractiveHost'
        'Get-NMJCachedInitPath'
        'Set-NMJCachedInit'
    )
    AliasesToExport   = @('myhelp', 'nmjhelp')
}
