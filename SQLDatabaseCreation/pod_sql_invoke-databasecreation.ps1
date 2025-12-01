<#
.SYNOPSIS
    Creates and configures SQL Server database.

.DESCRIPTION
    This script automates the creation of SQL Server databases with:
    - Automatic calculation of optimal number of data files based on expected size
    - Multi-file support with configurable sizes and growth settings
    - Automatic derivation of data and log drives from instance default paths
    - Query Store enablement for SQL Server 2016+
    - Comprehensive logging and error handling

.PARAMETER SqlInstance
    The SQL Server instance to connect to (e.g., "localhost,1433" or "SERVER\INSTANCE").

.PARAMETER Database_Name
    The name of the database to create.

.PARAMETER ExpectedDatabaseSize
    The expected size of the database (e.g., "50GB", "100GB").

.PARAMETER Pillar
    The environment pillar. Valid values are 'DEV', 'UAC', 'PROD'.

.PARAMETER Datagroup
    The data group identifier.

.PARAMETER Collation
    The database collation. Default is 'Latin1_General_CI_AS'.

.PARAMETER ConfigPath
    Optional path to a PowerShell data file (.psd1) containing additional configuration.
    If provided, FileSizes and Logging settings will be loaded from the config file.
    If not provided, default values will be used.

.EXAMPLE
    .\pod_sql_invoke-databasecreation.ps1 -SqlInstance "localhost,1433" -Database_Name "MyDatabase" -ExpectedDatabaseSize "50GB" -Pillar "DEV" -Datagroup "DG01"
    Creates a database with the specified parameters using instance default paths.

.EXAMPLE
    .\pod_sql_invoke-databasecreation.ps1 -SqlInstance "localhost,1433" -Database_Name "MyDatabase" -ExpectedDatabaseSize "50GB" -Pillar "PROD" -Datagroup "DG01" -WhatIf
    Shows what would happen without actually creating the database.

.EXAMPLE
    .\pod_sql_invoke-databasecreation.ps1 -SqlInstance "localhost,1433" -Database_Name "MyDatabase" -ExpectedDatabaseSize "50GB" -Pillar "UAC" -Datagroup "DG01" -Verbose
    Creates a database with verbose output showing detailed progress.

.NOTES
    Requirements:
    - PowerShell 5.1 or higher
    - dbatools module
    - Appropriate SQL Server permissions

    The script will:
    1. Validate SQL Server connection
    2. Check if database already exists (EXIT EARLY if exists)
    3. Derive data and log drive paths from instance default paths
    4. Calculate optimal number of data files based on ExpectedDatabaseSize
    5. Validate sufficient disk space on data and log drives (EXIT EARLY if insufficient)
    6. Create necessary directories
    7. Create database with specified files
    8. Set database owner to 'sa'
    9. Enable Query Store (SQL Server 2016+)
    10. Create logins and database users based on Pillar:
        - DEV: 1005_GS_{Datagroup}0_DEV_RW (with db_owner role), 1005_GS_{Datagroup}0_FNC_RW, 
               1005_GS_{Datagroup}0_PRS_RO, 1005_GS_{Datagroup}0_PRS_RW
        - UAC/PROD: 0005_GS_{Datagroup}0_FNC_RW, 0005_GS_{Datagroup}0_PRS_RO, 
                    0005_GS_{Datagroup}0_PRS_RW

.LINK
    https://github.com/karim-attaleb/sqlserver-databasescripts
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "SQL Server instance to connect to")]
    [string]$SqlInstance,
    
    [Parameter(Mandatory = $true, HelpMessage = "Name of the database to create")]
    [string]$Database_Name,
    
    [Parameter(Mandatory = $true, HelpMessage = "Expected size of the database (e.g., '50GB')")]
    [ValidatePattern('^\d+(MB|GB|TB)$')]
    [string]$ExpectedDatabaseSize,
    
    [Parameter(Mandatory = $true, HelpMessage = "Environment pillar (DEV, UAC, PROD)")]
    [ValidateSet('DEV', 'UAC', 'PROD')]
    [string]$Pillar,
    
    [Parameter(Mandatory = $true, HelpMessage = "Data group identifier")]
    [string]$Datagroup,
    
    [Parameter(Mandatory = $false, HelpMessage = "Database collation")]
    [string]$Collation = 'Latin1_General_CI_AS',
    
    [Parameter(Mandatory = $false, HelpMessage = "Optional path to configuration file for additional settings")]
    [ValidateScript({
        if ($_ -and -not (Test-Path $_)) {
            throw "Configuration file not found: $_"
        }
        if ($_ -and $_ -notmatch '\.psd1$') {
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
    
    $modulePath = Join-Path $PSScriptRoot "pod_sql_databaseutils.psm1"
    if (-not (Test-Path $modulePath)) {
        throw "pod_sql_databaseutils module not found at: $modulePath"
    }
    Import-Module $modulePath -ErrorAction Stop -Force
    
    Write-Verbose "All required modules loaded successfully"
}
catch {
    Write-Error "Failed to import required modules: $($_.Exception.Message)"
    exit 1
}

# Load configuration from file if provided, otherwise use defaults
try {
    if ($ConfigPath) {
        $config = Import-PowerShellDataFile -Path $ConfigPath -ErrorAction Stop
        Write-Verbose "Configuration loaded from: $ConfigPath"
    }
    else {
        # Use default configuration
        $config = @{
            FileSizes = @{
                DataSize = "200MB"
                DataGrowth = "100MB"
                LogSize = "100MB"
                LogGrowth = "100MB"
                FileSizeThreshold = "10GB"
            }
            EnableEventLog = $true
            EventLogSource = "SQLDatabaseScripts"
        }
        Write-Verbose "Using default configuration"
    }
    
    # Set log file path (use config if available, otherwise default)
    $logFile = if ($config.LogFile) { $config.LogFile } else { "$PSScriptRoot\DatabaseCreation.log" }
}
catch {
    Write-Error "Failed to load configuration: $($_.Exception.Message)"
    exit 1
}

try {
    $enableEventLog = if ($config.EnableEventLog) { $config.EnableEventLog } else { $false }
    $eventLogSource = if ($config.EventLogSource) { $config.EventLogSource } else { "SQLDatabaseScripts" }
    
    Write-Log -Message "Starting database creation process" -Level Info -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
    Write-Log -Message "Target SQL Instance: $SqlInstance, Database: $Database_Name" -Level Info -LogFile $logFile -EnableEventLog $false
    Write-Log -Message "Expected Database Size: $ExpectedDatabaseSize" -Level Info -LogFile $logFile -EnableEventLog $false
    Write-Log -Message "Pillar: $Pillar, Datagroup: $Datagroup" -Level Info -LogFile $logFile -EnableEventLog $false
    Write-Log -Message "Event Log integration: $(if ($enableEventLog) { 'Enabled' } else { 'Disabled' })" -Level Info -LogFile $logFile -EnableEventLog $false

    # Validate SQL connection
    Write-Log -Message "Connecting to SQL Server instance: $SqlInstance..." -Level Info -LogFile $logFile -EnableEventLog $false
    $connectParams = @{
        SqlInstance = $SqlInstance
        TrustServerCertificate = $true
    }
    $server = Connect-DbaInstance @connectParams
    Write-Log -Message "Successfully connected to SQL instance: $SqlInstance" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
    Write-Log -Message "SQL Server version: $($server.VersionString), Edition: $($server.Edition), Instance: $($server.InstanceName)" -Level Info -LogFile $logFile -EnableEventLog $false
    
    # EARLY EXIT CHECK 1: Check if database already exists (exit early to avoid unnecessary work)
    Write-Log -Message "Checking if database '$Database_Name' already exists..." -Level Info -LogFile $logFile -EnableEventLog $false
    $existingDb = Get-DbaDatabase -SqlInstance $SqlInstance -Database $Database_Name
    if ($existingDb) {
        Write-Log -Message "Database '$Database_Name' already exists. Exiting early." -Level Warning -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
        return $Database_Name
    }
    Write-Log -Message "Database '$Database_Name' does not exist. Proceeding with validation..." -Level Info -LogFile $logFile -EnableEventLog $false
    
    # Derive data and log drives from instance default paths
    Write-Log -Message "Retrieving instance default paths..." -Level Info -LogFile $logFile -EnableEventLog $false
    $defaultPaths = Get-DbaDefaultPath -SqlInstance $SqlInstance
    $dataDrivePath = $defaultPaths.Data
    $logDrivePath = $defaultPaths.Log
    
    # Extract drive letters from paths (e.g., "C:\SQLData" -> "C")
    # For Windows paths: Extract drive letter (e.g., "C:\SQLData" -> "C")
    # For Linux paths: Use "C" as default since the Initialize-Directories function expects a drive letter
    if ($dataDrivePath -match '^([A-Z]):') {
        $dataDrive = $matches[1]
        $logDrive = if ($logDrivePath -match '^([A-Z]):') { $matches[1] } else { $matches[1] }
    }
    else {
        # Linux/Unix path - use default drive letter "C" for compatibility
        $dataDrive = "C"
        $logDrive = "C"
        Write-Log -Message "Non-Windows path detected. Using default drive letter 'C' for compatibility." -Level Info -LogFile $logFile -EnableEventLog $false
    }
    
    Write-Log -Message "Instance default data path: $dataDrivePath (Drive: $dataDrive)" -Level Info -LogFile $logFile -EnableEventLog $false
    Write-Log -Message "Instance default log path: $logDrivePath (Drive: $logDrive)" -Level Info -LogFile $logFile -EnableEventLog $false

    # Determine number of data files (needed for disk space validation)
    Write-Log -Message "Calculating optimal number of data files based on expected database size..." -Level Info -LogFile $logFile -EnableEventLog $false
    $numberOfDataFiles = Calculate-OptimalDataFiles `
        -ExpectedDatabaseSize $ExpectedDatabaseSize `
        -FileSizeThreshold $config.FileSizes.FileSizeThreshold
    Write-Log -Message "Calculated optimal number of data files: $numberOfDataFiles (based on expected size: $ExpectedDatabaseSize, threshold: $($config.FileSizes.FileSizeThreshold))" -Level Info -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
    
    # Calculate per-file size based on ExpectedDatabaseSize (needed for disk space validation)
    $expectedSizeMB = Convert-SizeToInt -SizeString $ExpectedDatabaseSize
    $perFileSizeMB = [int][Math]::Ceiling($expectedSizeMB / $numberOfDataFiles)
    $perFileSizeString = "${perFileSizeMB}MB"
    Write-Log -Message "Calculated per-file size: $perFileSizeString (total expected: $ExpectedDatabaseSize / $numberOfDataFiles files)" -Level Info -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
    Write-Log -Message "File configuration: DataSize=$perFileSizeString, LogSize=$($config.FileSizes.LogSize), DataGrowth=$($config.FileSizes.DataGrowth), LogGrowth=$($config.FileSizes.LogGrowth)" -Level Info -LogFile $logFile -EnableEventLog $false

    # EARLY EXIT CHECK 2: Validate sufficient disk space (exit early if not enough space)
    Write-Log -Message "Validating disk space availability on data drive ${dataDrive}:\ and log drive ${logDrive}:\..." -Level Info -LogFile $logFile -EnableEventLog $false
    $hasSufficientSpace = Test-DbaSufficientDiskSpace `
        -SqlInstance $SqlInstance `
        -DataDrive $dataDrive `
        -LogDrive $logDrive `
        -NumberOfDataFiles $numberOfDataFiles `
        -DataSize $perFileSizeString `
        -LogSize $config.FileSizes.LogSize `
        -SafetyMarginPercent 10
    
    if (-not $hasSufficientSpace) {
        $errorMsg = "Disk space validation failed. Exiting early. Please free up space on the drives or reduce database file sizes."
        Write-Log -Message $errorMsg -Level Error -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
        throw $errorMsg
    }
    Write-Log -Message "Disk space validation passed - sufficient space available on all required drives" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource

    # Initialize directories (only after all early exit checks have passed)
    Initialize-Directories -DataDrive $dataDrive `
                          -LogDrive $logDrive `
                          -ServerInstanceName $server.InstanceName `
                          -LogFile $logFile `
                          -EnableEventLog $enableEventLog `
                          -EventLogSource $eventLogSource

    # Create database
    if ($PSCmdlet.ShouldProcess("$Database_Name", "Create database")) {
        $dataDirectory = "${dataDrive}:\$($server.InstanceName)\data"
        $logDirectory = "${logDrive}:\$($server.InstanceName)\log"
        
        Write-Log -Message "Preparing to create database '$Database_Name' with the following configuration:" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Data directory: $dataDirectory" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Log directory: $logDirectory" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Number of data files (all in PRIMARY filegroup): $numberOfDataFiles" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Data file size: $perFileSizeString each (total: $ExpectedDatabaseSize)" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Log file size: $($config.FileSizes.LogSize)" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Data file growth: $($config.FileSizes.DataGrowth)" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Log file growth: $($config.FileSizes.LogGrowth)" -Level Info -LogFile $logFile -EnableEventLog $false

        $newDbParams = @{
            SqlInstance = $SqlInstance
            Name = $Database_Name
            DataFilePath = $dataDirectory
            LogFilePath = $logDirectory
            PrimaryFileSize = $perFileSizeMB
            LogSize = (Convert-SizeToInt $config.FileSizes.LogSize)
            PrimaryFileGrowth = (Convert-SizeToInt $config.FileSizes.DataGrowth)
            LogGrowth = (Convert-SizeToInt $config.FileSizes.LogGrowth)
        }

        try {
            Write-Log -Message "Creating database '$Database_Name'..." -Level Info -LogFile $logFile -EnableEventLog $false
            $newDb = New-DbaDatabase @newDbParams -ErrorAction Stop
            
            # Verify database was actually created
            if (-not $newDb -or $newDb.Status -ne 'Normal') {
                $errorMsg = "Database creation failed. New-DbaDatabase did not return a valid database object."
                Write-Log -Message $errorMsg -Level Error -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
                throw $errorMsg
            }
            
            # Verify database exists on server
            $dbCheck = Get-DbaDatabase -SqlInstance $SqlInstance -Database $Database_Name -ErrorAction SilentlyContinue
            if (-not $dbCheck) {
                $errorMsg = "Database creation failed. Database '$Database_Name' does not exist on server after creation attempt."
                Write-Log -Message $errorMsg -Level Error -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
                throw $errorMsg
            }
            
            Write-Log -Message "Successfully created database: $Database_Name with PRIMARY data file" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
            
            # Add additional files to PRIMARY filegroup if needed
            if ($numberOfDataFiles -gt 1) {
                Write-Log -Message "Adding $(($numberOfDataFiles - 1)) additional data file(s) to PRIMARY filegroup..." -Level Info -LogFile $logFile -EnableEventLog $false
                
                $dataGrowthMB = Convert-SizeToInt $config.FileSizes.DataGrowth
                
                for ($i = 2; $i -le $numberOfDataFiles; $i++) {
                    $logicalFileName = "${Database_Name}_Data$i"
                    $physicalFileName = "$dataDirectory\${Database_Name}_Data$i.ndf"
                    
                    if ($PSCmdlet.ShouldProcess("$Database_Name", "Add data file $i to PRIMARY filegroup")) {
                        try {
                            Add-DbaDbFile -SqlInstance $SqlInstance `
                                -Database $Database_Name `
                                -FileGroup "PRIMARY" `
                                -FileName $logicalFileName `
                                -Path $physicalFileName `
                                -Size $perFileSizeMB `
                                -Growth $dataGrowthMB `
                                -ErrorAction Stop
                            Write-Log -Message "Added data file $i ($logicalFileName) to PRIMARY filegroup" -Level Info -LogFile $logFile -EnableEventLog $false
                        }
                        catch {
                            Write-Log -Message "Failed to add data file ${i}: $($_.Exception.Message)" -Level Error -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
                            throw
                        }
                    }
                    else {
                        Write-Log -Message "[WHATIF] Would add data file $i ($logicalFileName) to PRIMARY filegroup" -Level Info -LogFile $logFile -EnableEventLog $false
                    }
                }
                
                Write-Log -Message "Successfully added $(($numberOfDataFiles - 1)) additional data file(s) to PRIMARY filegroup" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
            }

            # Set database owner
            Write-Log -Message "Setting database owner to 'sa'..." -Level Info -LogFile $logFile -EnableEventLog $false
            $db = Get-DbaDatabase -SqlInstance $SqlInstance -Database $Database_Name -ErrorAction Stop
            if ($db.Owner -ne 'sa') {
                Set-DbaDbOwner -SqlInstance $SqlInstance -Database $Database_Name -TargetLogin 'sa' -ErrorAction Stop
                Write-Log -Message "Changed database owner from '$($db.Owner)' to 'sa'" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
            }
            else {
                Write-Log -Message "Database owner is already 'sa'" -Level Info -LogFile $logFile -EnableEventLog $false
            }

            # Enable Query Store if SQL 2016+
            if ($server.VersionMajor -ge 13) {
                try {
                    Write-Log -Message "Enabling Query Store for database '$Database_Name'..." -Level Info -LogFile $logFile -EnableEventLog $false
                    Enable-QueryStore -SqlInstance $SqlInstance -Database $Database_Name
                    Write-Log -Message "Enabled Query Store for database with optimized settings" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
                }
                catch {
                    Write-Log -Message "Warning: Failed to enable Query Store: $($_.Exception.Message)" -Level Warning -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
                }
            }
            else {
                Write-Log -Message "Query Store not available on SQL Server version $($server.VersionMajor) (requires version 13+)" -Level Info -LogFile $logFile -EnableEventLog $false
            }
            
            # Create logins and users based on Pillar
            Write-Log -Message "Creating logins and users based on Pillar '$Pillar' and Datagroup '$Datagroup'..." -Level Info -LogFile $logFile -EnableEventLog $false
            
            # Determine login names based on Pillar
            if ($Pillar -eq 'DEV') {
                $loginNames = @(
                    "1005_GS_${Datagroup}0_DEV_RW",
                    "1005_GS_${Datagroup}0_FNC_RW",
                    "1005_GS_${Datagroup}0_PRS_RO",
                    "1005_GS_${Datagroup}0_PRS_RW"
                )
            }
            else {
                # UAC or PROD
                $loginNames = @(
                    "0005_GS_${Datagroup}0_FNC_RW",
                    "0005_GS_${Datagroup}0_PRS_RO",
                    "0005_GS_${Datagroup}0_PRS_RW"
                )
            }
            
            Write-Log -Message "Login names to create: $($loginNames -join ', ')" -Level Info -LogFile $logFile -EnableEventLog $false
            
            # Create logins and map as users
            foreach ($loginName in $loginNames) {
                if ($PSCmdlet.ShouldProcess("$loginName", "Create login and database user")) {
                    try {
                        # Check if login already exists
                        $existingLogin = Get-DbaLogin -SqlInstance $SqlInstance -Login $loginName -ErrorAction SilentlyContinue
                        if (-not $existingLogin) {
                            # Create Windows login (assuming these are Windows/AD groups)
                            New-DbaLogin -SqlInstance $SqlInstance -Login $loginName -LoginType WindowsGroup -ErrorAction Stop
                            Write-Log -Message "Created login: $loginName" -Level Info -LogFile $logFile -EnableEventLog $false
                        }
                        else {
                            Write-Log -Message "Login '$loginName' already exists, skipping creation" -Level Info -LogFile $logFile -EnableEventLog $false
                        }
                        
                        # Check if user already exists in database
                        $existingUser = Get-DbaDbUser -SqlInstance $SqlInstance -Database $Database_Name -User $loginName -ErrorAction SilentlyContinue
                        if (-not $existingUser) {
                            # Create database user mapped to login
                            New-DbaDbUser -SqlInstance $SqlInstance -Database $Database_Name -Login $loginName -Username $loginName -ErrorAction Stop
                            Write-Log -Message "Created database user: $loginName in database $Database_Name" -Level Info -LogFile $logFile -EnableEventLog $false
                        }
                        else {
                            Write-Log -Message "User '$loginName' already exists in database, skipping creation" -Level Info -LogFile $logFile -EnableEventLog $false
                        }
                        
                        # If Pillar is DEV and this is the DEV_RW login, add user to db_owner role
                        if ($Pillar -eq 'DEV' -and $loginName -like '*_DEV_RW') {
                            Add-DbaDbRoleMember -SqlInstance $SqlInstance -Database $Database_Name -Role 'db_owner' -User $loginName -ErrorAction Stop
                            Write-Log -Message "Added user '$loginName' to db_owner role" -Level Info -LogFile $logFile -EnableEventLog $false
                        }
                    }
                    catch {
                        Write-Log -Message "Failed to create login/user '$loginName': $($_.Exception.Message)" -Level Warning -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
                        # Continue with other logins even if one fails
                    }
                }
                else {
                    Write-Log -Message "[WHATIF] Would create login and user: $loginName" -Level Info -LogFile $logFile -EnableEventLog $false
                }
            }
            
            Write-Log -Message "Completed login and user creation for Pillar '$Pillar'" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
            
            Write-Log -Message "Database '$Database_Name' configuration summary:" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Total data files in PRIMARY filegroup: $numberOfDataFiles" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Data file location: $dataDirectory" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Log file location: $logDirectory" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Owner: sa" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Query Store: $(if ($server.VersionMajor -ge 13) { 'Enabled' } else { 'Not Available' })" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Pillar: $Pillar, Datagroup: $Datagroup" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Logins/Users created: $($loginNames -join ', ')" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Database role: $(if ($Pillar -eq 'DEV') { 'db_owner (DEV_RW only)' } else { 'None (default)' })" -Level Info -LogFile $logFile -EnableEventLog $false
        }
        catch {
            Write-Log -Message "Failed to create database: $($_.Exception.Message)" -Level Error -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
            throw
        }
    }
    else {
        Write-Log -Message "[WHATIF] Would create database: $Database_Name" -Level Info -LogFile $logFile -EnableEventLog $false
    }

    Write-Log -Message "Database creation completed successfully!" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
    return $Database_Name
}
catch {
    Write-Log -Message "Script execution failed: $($_.Exception.Message)" -Level Error -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
    Write-Log -Message "Stack trace: $($_.ScriptStackTrace)" -Level Error -LogFile $logFile -EnableEventLog $false
    exit 1
}
