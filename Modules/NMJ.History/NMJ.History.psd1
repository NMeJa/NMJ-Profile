@{
    ModuleVersion     = '1.1.1'
    GUID              = 'b2c3d4e5-f6a7-8901-bcde-f12345678901'
    Author            = 'NMJ'
    Description       = 'Atuin-based history manager for NMJ'
    PowerShellVersion = '7.0'
    RequiredModules   = @('NMJ.Core')
    RootModule        = 'NMJ.History.psm1'
    FunctionsToExport = @('Get-AtuinHistory', 'Initialize-NMJAtuin')
    AliasesToExport   = @()
}
