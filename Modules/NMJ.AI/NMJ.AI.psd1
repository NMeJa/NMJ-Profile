@{
    ModuleVersion     = '1.0.0'
    GUID              = 'c3d4e5f6-a7b8-9012-cdef-123456789012'
    Author            = 'NMJ'
    Description       = 'Local Ollama AI assistant (askai / fixit / aish)'
    PowerShellVersion = '7.0'
    RootModule        = 'NMJ.AI.psm1'
    FunctionsToExport = @('Invoke-AskAI', 'Invoke-FixIt', 'Start-AIShell')
    AliasesToExport   = @('askai', 'fixit', 'aish')
}
