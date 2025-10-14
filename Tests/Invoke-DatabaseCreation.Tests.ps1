BeforeAll {
    Mock Connect-DbaInstance {
        return [PSCustomObject]@{
            InstanceName = "MSSQLSERVER"
            VersionMajor = 15
        }
    }
    
    Mock Get-DbaDatabase { $null }
    Mock New-DbaDatabase {
        return [PSCustomObject]@{
            Name = "TestDB"
        }
    }
    Mock Set-DbaDbOwner { }
    Mock Set-DbaDbQueryStoreOption { }
    Mock Initialize-Directories { }
    Mock Write-Log { }
    Mock Calculate-OptimalDataFiles { return 4 }
}

Describe "Invoke-DatabaseCreation Integration Tests" {
    Context "Script validation" {
        It "Should have valid PowerShell syntax" {
            $scriptPath = Join-Path $PSScriptRoot "..\SQLDatabaseCreation\Invoke-DatabaseCreation.ps1"
            $errors = $null
            $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $scriptPath -Raw), [ref]$errors)
            $errors.Count | Should -Be 0
        }
    }
    
    Context "When configuration file is missing" {
        It "Should throw error for non-existent config file" {
            $scriptPath = Join-Path $PSScriptRoot "..\SQLDatabaseCreation\Invoke-DatabaseCreation.ps1"
            { & $scriptPath -ConfigPath "NonExistent.psd1" } | Should -Throw
        }
    }
    
    Context "When configuration file has wrong extension" {
        It "Should throw error for non-psd1 file" {
            $scriptPath = Join-Path $PSScriptRoot "..\SQLDatabaseCreation\Invoke-DatabaseCreation.ps1"
            $tempFile = New-TemporaryFile
            { & $scriptPath -ConfigPath $tempFile.FullName } | Should -Throw
            Remove-Item $tempFile.FullName -Force
        }
    }
}

Describe "Database Creation Logic" {
    Context "When ExpectedDatabaseSize exceeds threshold" {
        It "Should calculate multiple data files" {
            Mock Import-PowerShellDataFile {
                return @{
                    SqlInstance = "localhost"
                    Database = @{
                        Name = "TestDB"
                        DataDrive = "G"
                        LogDrive = "L"
                        ExpectedDatabaseSize = "50GB"
                    }
                    FileSizes = @{
                        DataSize = "200MB"
                        DataGrowth = "100MB"
                        LogSize = "100MB"
                        LogGrowth = "100MB"
                        FileSizeThreshold = "10GB"
                    }
                    LogFile = "test.log"
                }
            }
        }
    }
    
    Context "When ExpectedDatabaseSize is below threshold" {
        It "Should create a single data file" {
            Mock Import-PowerShellDataFile {
                return @{
                    SqlInstance = "localhost"
                    Database = @{
                        Name = "TestDB"
                        DataDrive = "G"
                        LogDrive = "L"
                        ExpectedDatabaseSize = "5GB"
                    }
                    FileSizes = @{
                        DataSize = "200MB"
                        DataGrowth = "100MB"
                        LogSize = "100MB"
                        LogGrowth = "100MB"
                        FileSizeThreshold = "10GB"
                    }
                    LogFile = "test.log"
                }
            }
        }
    }
}
