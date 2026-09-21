@{
    ModuleVersion     = '1.0.0'
    GUID              = 'e5f6a7b8-c9d0-1234-ef01-345678901234'
    Author            = 'NMJ'
    Description       = 'Oh My Posh + FastFetch theme management'
    PowerShellVersion = '7.0'
    RootModule        = 'NMJ.Themes.psm1'
    FunctionsToExport = @('Set-Theme', 'Set-FastFetchIconTheme', 'Invoke-FastFetch')
    AliasesToExport   = @('ff', 'set-icon', 'Set-Icon')
}
