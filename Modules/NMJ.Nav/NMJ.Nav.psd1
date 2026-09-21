@{
    ModuleVersion     = '1.0.0'
    GUID              = 'f6a7b8c9-d0e1-2345-fa01-456789012345'
    Author            = 'NMJ'
    Description       = 'Fuzzy folder navigation using zoxide, Everything (es.exe), and fzf'
    PowerShellVersion = '7.0'
    RootModule        = 'NMJ.Nav.psm1'
    FunctionsToExport = @('Find-FuzzyFolder')
    AliasesToExport   = @('nf', 'Navigate-Fuzzy')
}
