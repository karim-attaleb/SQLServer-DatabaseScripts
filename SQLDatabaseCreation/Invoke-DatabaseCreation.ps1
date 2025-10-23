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
    3. Calculate optimal number of data files based on ExpectedDatabaseSize
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
    Import-Module dbatools -ErrorAction Stop -DisableNameChecking
    
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
    $enableEventLog = if ($config.EnableEventLog) { $config.EnableEventLog } else { $false }
    $eventLogSource = if ($config.EventLogSource) { $config.EventLogSource } else { "SQLDatabaseScripts" }
    
    Write-Log -Message "Starting database creation process" -Level Info -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
    Write-Log -Message "Configuration loaded from: $ConfigPath" -Level Info -LogFile $logFile -EnableEventLog $false
    Write-Log -Message "Target SQL Instance: $($config.SqlInstance), Database: $($config.Database.Name)" -Level Info -LogFile $logFile -EnableEventLog $false
    Write-Log -Message "Event Log integration: $(if ($enableEventLog) { 'Enabled' } else { 'Disabled' })" -Level Info -LogFile $logFile -EnableEventLog $false

    # Validate SQL connection
    Write-Log -Message "Connecting to SQL Server instance: $($config.SqlInstance)..." -Level Info -LogFile $logFile -EnableEventLog $false
    $connectParams = @{
        SqlInstance = $config.SqlInstance
        TrustServerCertificate = $true
    }
    $server = Connect-DbaInstance @connectParams
    Write-Log -Message "Successfully connected to SQL instance: $($config.SqlInstance)" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
    Write-Log -Message "SQL Server version: $($server.VersionString), Edition: $($server.Edition), Instance: $($server.InstanceName)" -Level Info -LogFile $logFile -EnableEventLog $false

    # Create SQL Server logins if specified in configuration
    if ($config.Logins -and $config.Logins.Count -gt 0) {
        Write-Log -Message "Processing SQL Server login creation..." -Level Info -LogFile $logFile -EnableEventLog $false
        
        foreach ($loginConfig in $config.Logins) {
            try {
                $loginParams = @{
                    SqlInstance = $config.SqlInstance
                    LoginName = $loginConfig.LoginName
                    LoginType = $loginConfig.LoginType
                    LogFile = $logFile
                    EnableEventLog = $enableEventLog
                    EventLogSource = $eventLogSource
                }
                
                # Add SQL Auth password if specified
                if ($loginConfig.LoginType -eq "SqlLogin") {
                    if ($loginConfig.Password) {
                        # Password should be a SecureString
                        if ($loginConfig.Password -is [SecureString]) {
                            $loginParams.Password = $loginConfig.Password
                        }
                        elseif ($loginConfig.Password -is [string]) {
                            # Convert plain text to SecureString (for backward compatibility)
                            $loginParams.Password = ConvertTo-SecureString $loginConfig.Password -AsPlainText -Force
                        }
                    }
                    else {
                        Write-Log -Message "Warning: SQL Login '$($loginConfig.LoginName)' requires a password. Skipping creation." -Level Warning -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
                        continue
                    }
                }
                
                # Add optional parameters if specified
                if ($loginConfig.ServerRoles) {
                    $loginParams.ServerRoles = $loginConfig.ServerRoles
                }
                if ($loginConfig.DisablePasswordPolicy) {
                    $loginParams.DisablePasswordPolicy = $true
                }
                if ($loginConfig.MustChangePassword) {
                    $loginParams.MustChangePassword = $true
                }
                
                $result = Add-SqlServerLogin @loginParams
                
                if (-not $result) {
                    Write-Log -Message "Warning: Failed to create login '$($loginConfig.LoginName)'. See previous error messages." -Level Warning -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
                }
            }
            catch {
                Write-Log -Message "Warning: Exception during login creation for '$($loginConfig.LoginName)': $($_.Exception.Message)" -Level Warning -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
            }
        }
        
        Write-Log -Message "SQL Server login creation processing completed" -Level Info -LogFile $logFile -EnableEventLog $false
    }
    else {
        Write-Log -Message "No SQL Server logins configured for creation" -Level Info -LogFile $logFile -EnableEventLog $false
    }

    # Initialize directories
    Initialize-Directories -DataDrive $config.Database.DataDrive `
                          -LogDrive $config.Database.LogDrive `
                          -ServerInstanceName $server.InstanceName `
                          -LogFile $logFile `
                          -EnableEventLog $enableEventLog `
                          -EventLogSource $eventLogSource

    # Determine number of data files
    Write-Log -Message "Calculating optimal number of data files based on expected database size..." -Level Info -LogFile $logFile -EnableEventLog $false
    $numberOfDataFiles = Calculate-OptimalDataFiles `
        -ExpectedDatabaseSize $config.Database.ExpectedDatabaseSize `
        -FileSizeThreshold $config.FileSizes.FileSizeThreshold
    Write-Log -Message "Calculated optimal number of data files: $numberOfDataFiles (based on expected size: $($config.Database.ExpectedDatabaseSize), threshold: $($config.FileSizes.FileSizeThreshold))" -Level Info -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
    Write-Log -Message "File configuration: DataSize=$($config.FileSizes.DataSize), LogSize=$($config.FileSizes.LogSize), DataGrowth=$($config.FileSizes.DataGrowth), LogGrowth=$($config.FileSizes.LogGrowth)" -Level Info -LogFile $logFile -EnableEventLog $false

    # Validate sufficient disk space
    Write-Log -Message "Validating disk space availability on data drive ${($config.Database.DataDrive)}:\ and log drive ${($config.Database.LogDrive)}:\..." -Level Info -LogFile $logFile -EnableEventLog $false
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
        Write-Log -Message $errorMsg -Level Error -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
        throw $errorMsg
    }
    Write-Log -Message "Disk space validation passed - sufficient space available on all required drives" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource

    # Check if database already exists
    Write-Log -Message "Checking if database '$($config.Database.Name)' already exists..." -Level Info -LogFile $logFile -EnableEventLog $false
    $existingDb = Get-DbaDatabase -SqlInstance $config.SqlInstance -Database $config.Database.Name
    if ($existingDb) {
        Write-Log -Message "Database '$($config.Database.Name)' already exists. Skipping creation." -Level Warning -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
        return $config.Database.Name
    }
    Write-Log -Message "Database '$($config.Database.Name)' does not exist. Proceeding with creation..." -Level Info -LogFile $logFile -EnableEventLog $false

    # Create database
    if ($PSCmdlet.ShouldProcess("$($config.Database.Name)", "Create database")) {
        $dataDirectory = "$($config.Database.DataDrive):\$($server.InstanceName)\data"
        $logDirectory = "$($config.Database.LogDrive):\$($server.InstanceName)\log"
        
        Write-Log -Message "Preparing to create database '$($config.Database.Name)' with the following configuration:" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Data directory: $dataDirectory" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Log directory: $logDirectory" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Number of data files: $numberOfDataFiles" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Primary file size: $($config.FileSizes.DataSize)" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Secondary file size: $($config.FileSizes.DataSize)" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Log file size: $($config.FileSizes.LogSize)" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Data file growth: $($config.FileSizes.DataGrowth)" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Log file growth: $($config.FileSizes.LogGrowth)" -Level Info -LogFile $logFile -EnableEventLog $false

        $newDbParams = @{
            SqlInstance = $config.SqlInstance
            Name = $config.Database.Name
            DataFilePath = $dataDirectory
            LogFilePath = $logDirectory
            PrimaryFileSize = (Convert-SizeToInt $config.FileSizes.DataSize)
            LogSize = (Convert-SizeToInt $config.FileSizes.LogSize)
            PrimaryFileGrowth = (Convert-SizeToInt $config.FileSizes.DataGrowth)
            LogGrowth = (Convert-SizeToInt $config.FileSizes.LogGrowth)
            SecondaryFileCount = [Math]::Max(0, $numberOfDataFiles - 1)
            SecondaryFilesize = (Convert-SizeToInt $config.FileSizes.DataSize)
            SecondaryFileGrowth = (Convert-SizeToInt $config.FileSizes.DataGrowth)
        }

        try {
            Write-Log -Message "Creating database '$($config.Database.Name)'..." -Level Info -LogFile $logFile -EnableEventLog $false
            $newDb = New-DbaDatabase @newDbParams -ErrorAction Stop
            
            # Verify database was actually created
            if (-not $newDb -or $newDb.Status -ne 'Normal') {
                $errorMsg = "Database creation failed. New-DbaDatabase did not return a valid database object."
                Write-Log -Message $errorMsg -Level Error -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
                throw $errorMsg
            }
            
            # Verify database exists on server
            $dbCheck = Get-DbaDatabase -SqlInstance $config.SqlInstance -Database $config.Database.Name -ErrorAction SilentlyContinue
            if (-not $dbCheck) {
                $errorMsg = "Database creation failed. Database '$($config.Database.Name)' does not exist on server after creation attempt."
                Write-Log -Message $errorMsg -Level Error -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
                throw $errorMsg
            }
            
            Write-Log -Message "Successfully created database: $($config.Database.Name) with $numberOfDataFiles data file(s)" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource

            # Set database owner
            Write-Log -Message "Setting database owner to 'sa'..." -Level Info -LogFile $logFile -EnableEventLog $false
            $db = Get-DbaDatabase -SqlInstance $config.SqlInstance -Database $config.Database.Name -ErrorAction Stop
            if ($db.Owner -ne 'sa') {
                Set-DbaDbOwner -SqlInstance $config.SqlInstance -Database $config.Database.Name -TargetLogin 'sa' -ErrorAction Stop
                Write-Log -Message "Changed database owner from '$($db.Owner)' to 'sa'" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
            }
            else {
                Write-Log -Message "Database owner is already 'sa'" -Level Info -LogFile $logFile -EnableEventLog $false
            }

            # Enable Query Store if SQL 2016+
            if ($server.VersionMajor -ge 13) {
                try {
                    Write-Log -Message "Enabling Query Store for database '$($config.Database.Name)'..." -Level Info -LogFile $logFile -EnableEventLog $false
                    Enable-QueryStore -SqlInstance $config.SqlInstance -Database $config.Database.Name
                    Write-Log -Message "Enabled Query Store for database with optimized settings" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
                }
                catch {
                    Write-Log -Message "Warning: Failed to enable Query Store: $($_.Exception.Message)" -Level Warning -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
                }
            }
            else {
                Write-Log -Message "Query Store not available on SQL Server version $($server.VersionMajor) (requires version 13+)" -Level Info -LogFile $logFile -EnableEventLog $false
            }
            
            # Create database users if specified in configuration
            if ($config.Users -and $config.Users.Count -gt 0) {
                Write-Log -Message "Processing database user creation..." -Level Info -LogFile $logFile -EnableEventLog $false
                
                foreach ($userConfig in $config.Users) {
                    try {
                        $userParams = @{
                            SqlInstance = $config.SqlInstance
                            Database = $config.Database.Name
                            LoginName = $userConfig.LoginName
                            LogFile = $logFile
                            EnableEventLog = $enableEventLog
                            EventLogSource = $eventLogSource
                        }
                        
                        # Add optional parameters if specified
                        if ($userConfig.UserName) {
                            $userParams.UserName = $userConfig.UserName
                        }
                        if ($userConfig.DatabaseRoles) {
                            $userParams.DatabaseRoles = $userConfig.DatabaseRoles
                        }
                        if ($userConfig.DefaultSchema) {
                            $userParams.DefaultSchema = $userConfig.DefaultSchema
                        }
                        
                        $result = Add-DatabaseUser @userParams
                        
                        if (-not $result) {
                            Write-Log -Message "Warning: Failed to create user '$($userConfig.LoginName)'. See previous error messages." -Level Warning -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
                        }
                    }
                    catch {
                        Write-Log -Message "Warning: Exception during user creation for '$($userConfig.LoginName)': $($_.Exception.Message)" -Level Warning -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
                    }
                }
                
                Write-Log -Message "Database user creation processing completed" -Level Info -LogFile $logFile -EnableEventLog $false
            }
            else {
                Write-Log -Message "No database users configured for creation" -Level Info -LogFile $logFile -EnableEventLog $false
            }
            
            Write-Log -Message "Database '$($config.Database.Name)' configuration summary:" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Total data files: $numberOfDataFiles" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Data file location: $dataDirectory" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Log file location: $logDirectory" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Owner: sa" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Query Store: $(if ($server.VersionMajor -ge 13) { 'Enabled' } else { 'Not Available' })" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Database Users: $(if ($config.Users -and $config.Users.Count -gt 0) { $config.Users.Count } else { 'None' })" -Level Info -LogFile $logFile -EnableEventLog $false
        }
        catch {
            Write-Log -Message "Failed to create database: $($_.Exception.Message)" -Level Error -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
            throw
        }
    }
    else {
        Write-Log -Message "[WHATIF] Would create database: $($config.Database.Name)" -Level Info -LogFile $logFile -EnableEventLog $false
        if ($config.Users -and $config.Users.Count -gt 0) {
            Write-Log -Message "[WHATIF] Would create $($config.Users.Count) database user(s)" -Level Info -LogFile $logFile -EnableEventLog $false
        }
    }

    Write-Log -Message "Database creation completed successfully!" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
    return $config.Database.Name
}
catch {
    Write-Log -Message "Script execution failed: $($_.Exception.Message)" -Level Error -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
    Write-Log -Message "Stack trace: $($_.ScriptStackTrace)" -Level Error -LogFile $logFile -EnableEventLog $false
    exit 1
}
