BeforeAll {
    $modulePath = Join-Path $PSScriptRoot "..\SQLDatabaseCreation\DatabaseUtils.psm1"
    Import-Module $modulePath -Force
}

Describe "Convert-SizeToInt" {
    Context "When converting MB values" {
        It "Should convert '200MB' to 200" {
            Convert-SizeToInt -SizeString "200MB" | Should -Be 200
        }
        
        It "Should convert '1MB' to 1" {
            Convert-SizeToInt -SizeString "1MB" | Should -Be 1
        }
        
        It "Should convert '1000MB' to 1000" {
            Convert-SizeToInt -SizeString "1000MB" | Should -Be 1000
        }
    }
    
    Context "When converting GB values" {
        It "Should convert '10GB' to 10240" {
            Convert-SizeToInt -SizeString "10GB" | Should -Be 10240
        }
        
        It "Should convert '1GB' to 1024" {
            Convert-SizeToInt -SizeString "1GB" | Should -Be 1024
        }
        
        It "Should convert '5GB' to 5120" {
            Convert-SizeToInt -SizeString "5GB" | Should -Be 5120
        }
    }
    
    Context "When converting TB values" {
        It "Should convert '1TB' to 1048576" {
            Convert-SizeToInt -SizeString "1TB" | Should -Be 1048576
        }
        
        It "Should convert '2TB' to 2097152" {
            Convert-SizeToInt -SizeString "2TB" | Should -Be 2097152
        }
    }
    
    Context "When input validation fails" {
        It "Should throw error for invalid format" {
            { Convert-SizeToInt -SizeString "InvalidFormat" } | Should -Throw
        }
        
        It "Should throw error for missing units" {
            { Convert-SizeToInt -SizeString "100" } | Should -Throw
        }
        
        It "Should throw error for unsupported units" {
            { Convert-SizeToInt -SizeString "100KB" } | Should -Throw
        }
    }
}

Describe "Calculate-OptimalDataFiles" {
    Context "When database size is less than threshold" {
        It "Should return 1 file when size is 5GB and threshold is 10GB" {
            Calculate-OptimalDataFiles -ExpectedDatabaseSize "5GB" -FileSizeThreshold "10GB" | Should -Be 1
        }
        
        It "Should return 1 file when size is 1GB and threshold is 10GB" {
            Calculate-OptimalDataFiles -ExpectedDatabaseSize "1GB" -FileSizeThreshold "10GB" | Should -Be 1
        }
        
        It "Should return 1 file when size is 500MB and threshold is 1GB" {
            Calculate-OptimalDataFiles -ExpectedDatabaseSize "500MB" -FileSizeThreshold "1GB" | Should -Be 1
        }
    }
    
    Context "When database size equals threshold" {
        It "Should return 1 file when size equals threshold" {
            Calculate-OptimalDataFiles -ExpectedDatabaseSize "10GB" -FileSizeThreshold "10GB" | Should -Be 1
        }
    }
    
    Context "When database size exceeds threshold" {
        It "Should return 5 files when size is 50GB and threshold is 10GB" {
            Calculate-OptimalDataFiles -ExpectedDatabaseSize "50GB" -FileSizeThreshold "10GB" | Should -Be 5
        }
        
        It "Should return 2 files when size is 15GB and threshold is 10GB" {
            Calculate-OptimalDataFiles -ExpectedDatabaseSize "15GB" -FileSizeThreshold "10GB" | Should -Be 2
        }
        
        It "Should return 3 files when size is 25GB and threshold is 10GB" {
            Calculate-OptimalDataFiles -ExpectedDatabaseSize "25GB" -FileSizeThreshold "10GB" | Should -Be 3
        }
    }
    
    Context "When calculation exceeds maximum" {
        It "Should return 10 files when size is 100GB and threshold is 10GB" {
            Calculate-OptimalDataFiles -ExpectedDatabaseSize "100GB" -FileSizeThreshold "10GB" | Should -Be 10
        }
        
        It "Should return 103 files when size is 1TB and threshold is 10GB" {
            Calculate-OptimalDataFiles -ExpectedDatabaseSize "1TB" -FileSizeThreshold "10GB" | Should -Be 103
        }
        
        It "Should return 20 files when size is 200GB and threshold is 10GB" {
            Calculate-OptimalDataFiles -ExpectedDatabaseSize "200GB" -FileSizeThreshold "10GB" | Should -Be 20
        }
    }
    
    Context "When using different units" {
        It "Should handle MB to GB calculations correctly" {
            Calculate-OptimalDataFiles -ExpectedDatabaseSize "5000MB" -FileSizeThreshold "1GB" | Should -Be 5
        }
        
        It "Should handle GB to TB calculations correctly" {
            Calculate-OptimalDataFiles -ExpectedDatabaseSize "500GB" -FileSizeThreshold "1TB" | Should -Be 1
        }
        
        It "Should handle mixed unit calculations" {
            Calculate-OptimalDataFiles -ExpectedDatabaseSize "2048MB" -FileSizeThreshold "1GB" | Should -Be 2
        }
    }
    
    Context "When rounding is needed" {
        It "Should round up 11GB / 10GB to 2 files" {
            Calculate-OptimalDataFiles -ExpectedDatabaseSize "11GB" -FileSizeThreshold "10GB" | Should -Be 2
        }
        
        It "Should round up 21GB / 10GB to 3 files" {
            Calculate-OptimalDataFiles -ExpectedDatabaseSize "21GB" -FileSizeThreshold "10GB" | Should -Be 3
        }
    }
    
    Context "When input validation fails" {
        It "Should throw error for invalid ExpectedDatabaseSize format" {
            { Calculate-OptimalDataFiles -ExpectedDatabaseSize "InvalidSize" -FileSizeThreshold "10GB" } | Should -Throw
        }
        
        It "Should throw error for invalid FileSizeThreshold format" {
            { Calculate-OptimalDataFiles -ExpectedDatabaseSize "50GB" -FileSizeThreshold "InvalidThreshold" } | Should -Throw
        }
    }
}

Describe "Initialize-Directories" {
    Context "When directories do not exist" {
        BeforeAll {
            Mock Test-Path { $false }
            Mock New-Item { }
            Mock Write-Log { }
        }
        
        It "Should attempt to create both data and log directories" {
            Initialize-Directories -DataDrive "G" -LogDrive "L" -ServerInstanceName "MSSQLSERVER" -LogFile "test.log"
            Should -Invoke New-Item -Times 2
        }
        
        It "Should log directory creation" {
            Initialize-Directories -DataDrive "G" -LogDrive "L" -ServerInstanceName "MSSQLSERVER" -LogFile "test.log"
            Should -Invoke Write-Log -Times 2
        }
    }
    
    Context "When directories already exist" {
        BeforeAll {
            Mock Test-Path { $true }
            Mock New-Item { }
            Mock Write-Log { }
        }
        
        It "Should not create directories if they exist" {
            Initialize-Directories -DataDrive "G" -LogDrive "L" -ServerInstanceName "MSSQLSERVER" -LogFile "test.log"
            Should -Invoke New-Item -Times 0
        }
        
        It "Should not log directory creation if directories exist" {
            Initialize-Directories -DataDrive "G" -LogDrive "L" -ServerInstanceName "MSSQLSERVER" -LogFile "test.log"
            Should -Invoke Write-Log -Times 0
        }
    }

Describe "Test-DbaSufficientDiskSpace" {
    Context "When drives have sufficient space" {
        BeforeAll {
            Mock Get-DbaDiskSpace {
                return @(
                    [PSCustomObject]@{
                        Name = "G:\\"
                        Free = 50GB
                        Capacity = 100GB
                    },
                    [PSCustomObject]@{
                        Name = "L:\\"
                        Free = 20GB
                        Capacity = 50GB
                    }
                )
            }
        }
        
        It "Should return true when both drives have enough space" {
            Test-DbaSufficientDiskSpace -SqlInstance "localhost" -DataDrive "G" -LogDrive "L" -NumberOfDataFiles 4 -DataSize "200MB" -LogSize "100MB" | Should -Be $true
        }
        
        It "Should return true with custom safety margin" {
            Test-DbaSufficientDiskSpace -SqlInstance "localhost" -DataDrive "G" -LogDrive "L" -NumberOfDataFiles 4 -DataSize "200MB" -LogSize "100MB" -SafetyMarginPercent 20 | Should -Be $true
        }
    }
    
    Context "When drives have insufficient space" {
        BeforeAll {
            Mock Get-DbaDiskSpace {
                return @(
                    [PSCustomObject]@{
                        Name = "G:\\"
                        Free = 500MB
                        Capacity = 100GB
                    },
                    [PSCustomObject]@{
                        Name = "L:\\"
                        Free = 50MB
                        Capacity = 50GB
                    }
                )
            }
        }
        
        It "Should return false when data drive has insufficient space" {
            Test-DbaSufficientDiskSpace -SqlInstance "localhost" -DataDrive "G" -LogDrive "L" -NumberOfDataFiles 4 -DataSize "200MB" -LogSize "100MB" -ErrorAction SilentlyContinue | Should -Be $false
        }
        
        It "Should return false when log drive has insufficient space" {
            Mock Get-DbaDiskSpace {
                return @(
                    [PSCustomObject]@{
                        Name = "G:\\"
                        Free = 50GB
                        Capacity = 100GB
                    },
                    [PSCustomObject]@{
                        Name = "L:\\"
                        Free = 50MB
                        Capacity = 50GB
                    }
                )
            }
            Test-DbaSufficientDiskSpace -SqlInstance "localhost" -DataDrive "G" -LogDrive "L" -NumberOfDataFiles 4 -DataSize "200MB" -LogSize "500MB" -ErrorAction SilentlyContinue | Should -Be $false
        }
    }
    
    Context "When data and log share the same drive" {
        BeforeAll {
            Mock Get-DbaDiskSpace {
                return @(
                    [PSCustomObject]@{
                        Name = "G:\\"
                        Free = 2GB
                        Capacity = 100GB
                    }
                )
            }
        }
        
        It "Should check combined space requirement for same drive" {
            Test-DbaSufficientDiskSpace -SqlInstance "localhost" -DataDrive "G" -LogDrive "G" -NumberOfDataFiles 4 -DataSize "200MB" -LogSize "100MB" | Should -Be $true
        }
        
        It "Should return false if combined requirement exceeds available" {
            Mock Get-DbaDiskSpace {
                return @(
                    [PSCustomObject]@{
                        Name = "G:\\"
                        Free = 800MB
                        Capacity = 100GB
                    }
                )
            }
            Test-DbaSufficientDiskSpace -SqlInstance "localhost" -DataDrive "G" -LogDrive "G" -NumberOfDataFiles 4 -DataSize "200MB" -LogSize "100MB" -ErrorAction SilentlyContinue | Should -Be $false
        }
    }
    
    Context "When drive is not found" {
        BeforeAll {
            Mock Get-DbaDiskSpace {
                return @(
                    [PSCustomObject]@{
                        Name = "C:\\"
                        Free = 50GB
                        Capacity = 100GB
                    }
                )
            }
        }
        
        It "Should return false and write error when data drive not found" {
            Test-DbaSufficientDiskSpace -SqlInstance "localhost" -DataDrive "G" -LogDrive "L" -NumberOfDataFiles 4 -DataSize "200MB" -LogSize "100MB" -ErrorAction SilentlyContinue | Should -Be $false
        }
    }
    
    Context "When Get-DbaDiskSpace fails" {
        BeforeAll {
            Mock Get-DbaDiskSpace {
                throw "Access denied"
            }
        }
        
        It "Should throw error when disk space check fails" {
            { Test-DbaSufficientDiskSpace -SqlInstance "localhost" -DataDrive "G" -LogDrive "L" -NumberOfDataFiles 4 -DataSize "200MB" -LogSize "100MB" } | Should -Throw
        }
    }
}

    
    Context "When directory creation fails" {
        BeforeAll {
            Mock Test-Path { $false }
            Mock New-Item { throw "Access denied" }
            Mock Write-Log { }
        }
        
        It "Should throw error if directory creation fails" {
            { Initialize-Directories -DataDrive "G" -LogDrive "L" -ServerInstanceName "MSSQLSERVER" -LogFile "test.log" } | Should -Throw
        }
    }
    
    Context "When input validation fails" {
        It "Should throw error for invalid DataDrive format" {
            { Initialize-Directories -DataDrive "GG" -LogDrive "L" -ServerInstanceName "MSSQLSERVER" -LogFile "test.log" } | Should -Throw
        }
        
        It "Should throw error for invalid LogDrive format" {
            { Initialize-Directories -DataDrive "G" -LogDrive "LL" -ServerInstanceName "MSSQLSERVER" -LogFile "test.log" } | Should -Throw
        }
    }
}

Describe "Write-Log" {
    BeforeAll {
        $testLogFile = Join-Path $TestDrive "test.log"
    }
    
    Context "When writing log messages" {
        It "Should write Info level message" {
            Write-Log -Message "Test info message" -Level Info -LogFile $testLogFile
            $content = Get-Content $testLogFile -Raw
            $content | Should -Match "Info.*Test info message"
        }
        
        It "Should write Warning level message" {
            Write-Log -Message "Test warning message" -Level Warning -LogFile $testLogFile
            $content = Get-Content $testLogFile -Raw
            $content | Should -Match "Warning.*Test warning message"
        }
        
        It "Should write Error level message" {
            Write-Log -Message "Test error message" -Level Error -LogFile $testLogFile
            $content = Get-Content $testLogFile -Raw
            $content | Should -Match "Error.*Test error message"
        }
        
        It "Should write Success level message" {
            Write-Log -Message "Test success message" -Level Success -LogFile $testLogFile
            $content = Get-Content $testLogFile -Raw
            $content | Should -Match "Success.*Test success message"
        }
        
        It "Should include timestamp in log entry" {
            Write-Log -Message "Test message" -LogFile $testLogFile
            $content = Get-Content $testLogFile -Raw
            $content | Should -Match "\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]"
        }
    }
}

Describe "Enable-QueryStore" {
    Context "When Query Store is enabled successfully" {
        BeforeAll {
            Mock Set-DbaDbQueryStoreOption { }
        }
        
        It "Should call Set-DbaDbQueryStoreOption with correct parameters" {
            Enable-QueryStore -SqlInstance "localhost" -Database "TestDB"
            Should -Invoke Set-DbaDbQueryStoreOption -Times 1
        }
    }
    
    Context "When Query Store enablement fails" {
        BeforeAll {
            Mock Set-DbaDbQueryStoreOption { throw "Query Store not supported" }
        }
        
        It "Should throw error if enablement fails" {
            { Enable-QueryStore -SqlInstance "localhost" -Database "TestDB" } | Should -Throw
        }
    }
}
