@{
    RootModule = 'DatabaseUtils.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'karim-attaleb'
    CompanyName = 'Unknown'
    Copyright = '(c) 2025. All rights reserved.'
    Description = 'Utility functions for SQL Server database creation and management with automatic file count calculation based on thresholds'
    PowerShellVersion = '5.1'
    RequiredModules = @('dbatools')
    FunctionsToExport = @(
        'Convert-SizeToInt',
        'Write-Log',
        'Initialize-Directories',
        'Enable-QueryStore',
        'Calculate-OptimalDataFiles',
        'Test-DbaSufficientDiskSpace'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('SQL', 'SQLServer', 'Database', 'Administration', 'dbatools')
            ProjectUri = 'https://github.com/karim-attaleb/sqlserver-databasescripts'
            ReleaseNotes = 'Initial release with automatic threshold-based file count calculation'
        }
    }
}
