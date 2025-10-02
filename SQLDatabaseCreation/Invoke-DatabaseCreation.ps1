<#
.SYNOPSIS
    Creates and configures SQL Server database using configuration file.

.DESCRIPTION
    This script automates the creation of SQL Server databases with:
    - Automatic calculation of optimal number of data files based on expected size
    - Multi-file support with configurable sizes and growth settings
    - Multi-drive support for data and log files
    - Query Store enablement for SQL Server 2016+
    - Comprehensive logging and error handling

.PARAMETER ConfigPath
    The path to the PowerShell data file (.psd1) containing the database configuration.
    The configuration file should define SqlInstance, Database settings, FileSizes, and LogFile.

.EXAMPLE
    .\Invoke-DatabaseCreation.ps1 -ConfigPath .\DatabaseConfig.psd1
    Creates a database using the settings in DatabaseConfig.psd1.

.EXAMPLE
    .\Invoke-DatabaseCreation.ps1 -ConfigPath .\DatabaseConfig.psd1 -WhatIf
    Shows what would happen without actually creating the database.

.EXAMPLE
    .\Invoke-DatabaseCreation.ps1 -ConfigPath .\DatabaseConfig.psd1 -Verbose
    Creates a database with verbose output showing detailed progress.

.NOTES
    Requirements:
    - PowerShell 5.1 or higher
    - dbatools module
    - Appropriate SQL Server permissions

    The script will:
    1. Validate SQL Server connection
    2. Create necessary directories
    3. Calculate optimal number of data files (if ExpectedDatabaseSize is specified)
    4. Validate sufficient disk space on data and log drives
    5. Check if database already exists
    6. Create database with specified files
    7. Set database owner to 'sa'
    8. Enable Query Store (SQL Server 2016+)

.LINK
    https://github.com/karim-attaleb/sqlserver-databasescripts
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Path to the database configuration file (.psd1)")]
    [ValidateScript({
        if (-not (Test-Path $_)) {
            throw "Configuration file not found: $_"
        }
        if ($_ -notmatch '\.psd1$') {
            throw "Configuration file must be a PowerShell data file (.psd1)"
        }
        return $true
    })]
    [string]$ConfigPath
)

# Import required modules
try {
    if (-not (Get-Module -Name dbatools -ListAvailable)) {
        Write-Host "Installing dbatools module..." -ForegroundColor Yellow
        Install-Module -Name dbatools -Force -AllowClobber -Scope CurrentUser -SkipPublisherCheck
    }
    Import-Module dbatools -ErrorAction Stop
    
    $modulePath = Join-Path $PSScriptRoot "DatabaseUtils.psm1"
    if (-not (Test-Path $modulePath)) {
        throw "DatabaseUtils module not found at: $modulePath"
    }
    Import-Module $modulePath -ErrorAction Stop -Force
    
    Write-Verbose "All required modules loaded successfully"
}
catch {
    Write-Error "Failed to import required modules: $($_.Exception.Message)"
    exit 1
}

# Load configuration
try {
    $config = Import-PowerShellDataFile -Path $ConfigPath -ErrorAction Stop
    $logFile = $config.LogFile
    
    Write-Verbose "Configuration loaded from: $ConfigPath"
}
catch {
    Write-Error "Failed to load configuration file: $($_.Exception.Message)"
    exit 1
}

try {
    Write-Log -Message "Starting database creation process" -Level Info -LogFile $logFile

    # Validate SQL connection
    $connectParams = @{
        SqlInstance = $config.SqlInstance
        TrustServerCertificate = $true
    }
    $server = Connect-DbaInstance @connectParams
    Write-Log -Message "Successfully connected to SQL instance: $($config.SqlInstance)" -Level Success -LogFile $logFile

    # Initialize directories
    Initialize-Directories -DataDrive $config.Database.DataDrive `
                          -LogDrive $config.Database.LogDrive `
                          -ServerInstanceName $server.InstanceName `
                          -LogFile $logFile

    # Determine number of data files
    if ($config.Database.ExpectedDatabaseSize) {
        $numberOfDataFiles = Calculate-OptimalDataFiles `
            -ExpectedDatabaseSize $config.Database.ExpectedDatabaseSize `
            -FileSizeThreshold $config.FileSizes.FileSizeThreshold
        Write-Log -Message "Calculated optimal number of data files: $numberOfDataFiles (based on expected size: $($config.Database.ExpectedDatabaseSize), threshold: $($config.FileSizes.FileSizeThreshold))" -Level Info -LogFile $logFile
    }
    else {
        $numberOfDataFiles = $config.Database.NumberOfDataFiles
        Write-Log -Message "Using configured number of data files: $numberOfDataFiles" -Level Info -LogFile $logFile
    }

    # Validate sufficient disk space
    Write-Log -Message "Validating disk space availability..." -Level Info -LogFile $logFile
    $hasSufficientSpace = Test-DbaSufficientDiskSpace `
        -SqlInstance $config.SqlInstance `
        -DataDrive $config.Database.DataDrive `
        -LogDrive $config.Database.LogDrive `
        -NumberOfDataFiles $numberOfDataFiles `
        -DataSize $config.FileSizes.DataSize `
        -LogSize $config.FileSizes.LogSize `
        -SafetyMarginPercent 10
    
    if (-not $hasSufficientSpace) {
        $errorMsg = "Disk space validation failed. Please free up space on the drives or reduce database file sizes."
        Write-Log -Message $errorMsg -Level Error -LogFile $logFile
        throw $errorMsg
    }
    Write-Log -Message "Disk space validation passed - sufficient space available" -Level Success -LogFile $logFile

    # Check if database already exists
    $existingDb = Get-DbaDatabase -SqlInstance $config.SqlInstance -Database $config.Database.Name
    if ($existingDb) {
        Write-Log -Message "Database '$($config.Database.Name)' already exists. Skipping creation." -Level Warning -LogFile $logFile
        return $config.Database.Name
    }

    # Create database
    if ($PSCmdlet.ShouldProcess("$($config.Database.Name)", "Create database")) {
        $primaryDataPath = "$($config.Database.DataDrive):\$($server.InstanceName)\data\$($config.Database.Name).mdf"
        $logPath = "$($config.Database.LogDrive):\$($server.InstanceName)\log\$($config.Database.Name)_log.ldf"

        $newDbParams = @{
            SqlInstance = $config.SqlInstance
            Name = $config.Database.Name
            DataFilePath = $primaryDataPath
            LogFilePath = $logPath
            PrimaryFileSize = (Convert-SizeToInt $config.FileSizes.DataSize)
            LogSize = (Convert-SizeToInt $config.FileSizes.LogSize)
            PrimaryFileGrowth = (Convert-SizeToInt $config.FileSizes.DataGrowth)
            LogGrowth = (Convert-SizeToInt $config.FileSizes.LogGrowth)
            SecondaryFileCount = [Math]::Max(0, $numberOfDataFiles - 1)
            SecondaryFileGrowth = (Convert-SizeToInt $config.FileSizes.DataGrowth)
        }

        try {
            $newDb = New-DbaDatabase @newDbParams -ErrorAction Stop
            Write-Log -Message "Successfully created database: $($config.Database.Name) with $numberOfDataFiles data file(s)" -Level Success -LogFile $logFile

            # Set database owner
            $db = Get-DbaDatabase -SqlInstance $config.SqlInstance -Database $config.Database.Name -ErrorAction Stop
            if ($db.Owner -ne 'sa') {
                Set-DbaDbOwner -SqlInstance $config.SqlInstance -Database $config.Database.Name -TargetLogin 'sa' -ErrorAction Stop
                Write-Log -Message "Changed database owner to SA" -Level Success -LogFile $logFile
            }
            else {
                Write-Log -Message "Database owner is already SA" -Level Info -LogFile $logFile
            }

            # Enable Query Store if SQL 2016+
            if ($server.VersionMajor -ge 13) {
                try {
                    Enable-QueryStore -SqlInstance $config.SqlInstance -Database $config.Database.Name
                    Write-Log -Message "Enabled Query Store for database" -Level Success -LogFile $logFile
                }
                catch {
                    Write-Log -Message "Warning: Failed to enable Query Store: $($_.Exception.Message)" -Level Warning -LogFile $logFile
                }
            }
            else {
                Write-Log -Message "Query Store not available on SQL Server version $($server.VersionMajor) (requires version 13+)" -Level Info -LogFile $logFile
            }
        }
        catch {
            Write-Log -Message "Failed to create database: $($_.Exception.Message)" -Level Error -LogFile $logFile
            throw
        }
    }
    else {
        Write-Log -Message "[WHATIF] Would create database: $($config.Database.Name)" -Level Info -LogFile $logFile
    }

    Write-Log -Message "Database creation completed successfully!" -Level Success -LogFile $logFile
    return $config.Database.Name
}
catch {
    Write-Log -Message "Script execution failed: $($_.Exception.Message)" -Level Error -LogFile $logFile
    Write-Log -Message "Stack trace: $($_.ScriptStackTrace)" -Level Error -LogFile $logFile
    exit 1
}
