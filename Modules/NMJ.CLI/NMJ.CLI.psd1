@{
    ModuleVersion     = '1.1.0'
    GUID              = 'a5b6c7d8-e9f0-1234-bcde-567890123456'
    Author            = 'NMJ'
    Description       = 'Modern CLI enhancements, completions (uv), tool aliases (eza, bat, gsudo), and PSReadLine setup'
    PowerShellVersion = '7.0'
    RootModule        = 'NMJ.CLI.psm1'
    FunctionsToExport = @('ll', 'lt', 'Initialize-NMJUvCompletions')
    AliasesToExport   = @('ls', 'cat', 'sudo')
}
