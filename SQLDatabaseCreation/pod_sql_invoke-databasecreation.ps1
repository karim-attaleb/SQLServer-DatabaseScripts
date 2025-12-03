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
    The environment pillar. Valid values are 'DEV', 'ACC', 'PROD'.

.PARAMETER Datagroup
    The data group identifier.

.PARAMETER Collation
    The database collation. Default is 'Latin1_General_CI_AS'.

.EXAMPLE
    .\pod_sql_invoke-databasecreation.ps1 -SqlInstance "localhost,1433" -Database_Name "MyDatabase" -ExpectedDatabaseSize "50GB" -Pillar "DEV" -Datagroup "DG01"
    Creates a database with the specified parameters using instance default paths.

.EXAMPLE
    .\pod_sql_invoke-databasecreation.ps1 -SqlInstance "localhost,1433" -Database_Name "MyDatabase" -ExpectedDatabaseSize "50GB" -Pillar "PROD" -Datagroup "DG01" -WhatIf
    Shows what would happen without actually creating the database.

.EXAMPLE
    .\pod_sql_invoke-databasecreation.ps1 -SqlInstance "localhost,1433" -Database_Name "MyDatabase" -ExpectedDatabaseSize "50GB" -Pillar "ACC" -Datagroup "DG01" -Verbose
    Creates a database with verbose output showing detailed progress.

.NOTES
    Requirements:
    - PowerShell 5.1 or higher
    - dbatools module
    - Appropriate SQL Server permissions

    The script is idempotent and follows these steps (exits on failure at each step):
    
    STEP 1: Create Database
    1. Validate SQL Server connection
    2. Check if database already exists (skip creation if exists)
    3. Derive data and log drive paths from instance default paths
    4. Calculate optimal number of data files based on ExpectedDatabaseSize
    5. Validate sufficient disk space on data and log drives (EXIT if insufficient)
    6. Create necessary directories
    7. Create database with specified files
    8. Set database owner to 'sa'
    9. Enable Query Store (SQL Server 2016+)
    
    STEP 2: Create Logins and Users (EXIT on failure)
    Create logins and database users based on Pillar:
        - DEV: TDA001\1005_GS_{Datagroup}0_DEV_RW, TDA001\1005_GS_{Datagroup}0_FNC_RW, 
               TDA001\1005_GS_{Datagroup}0_PRS_RO, TDA001\1005_GS_{Datagroup}0_PRS_RW
        - ACC: TDA001\0005_GS_{Datagroup}0_FNC_RW, TDA001\0005_GS_{Datagroup}0_PRS_RO, 
               TDA001\0005_GS_{Datagroup}0_PRS_RW
        - PROD: GLOW001\0005_GS_{Datagroup}0_FNC_RW, GLOW001\0005_GS_{Datagroup}0_PRS_RO, 
                GLOW001\0005_GS_{Datagroup}0_PRS_RW
    
    STEP 3: Create db_executor Role (EXIT on failure)
    Create the db_executor database role and grant EXECUTE permission
    
    STEP 4: Setup Security (EXIT on failure)
    Assign database roles to users:
        - DEV_RW (DEV pillar only): db_owner
        - *_RO users: db_datareader
        - *_RW users (FNC_RW, PRS_RW): db_datareader, db_datawriter, db_executor

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
    
    [Parameter(Mandatory = $true, HelpMessage = "Environment pillar (DEV, ACC, PROD)")]
    [ValidateSet('DEV', 'ACC', 'PROD')]
    [string]$Pillar,
    
    [Parameter(Mandatory = $true, HelpMessage = "Data group identifier")]
    [string]$Datagroup,
    
    [Parameter(Mandatory = $false, HelpMessage = "Database collation")]
    [string]$Collation = 'Latin1_General_CI_AS'
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

# Load configuration from psd1 file (must be in same location as script)
$configPath = Join-Path $PSScriptRoot "pod_sql_databaseconfig.psd1"
if (-not (Test-Path $configPath)) {
    Write-Error "Configuration file not found at: $configPath"
    exit 1
}

try {
    $config = Import-PowerShellDataFile -Path $configPath -ErrorAction Stop
}
catch {
    Write-Error "Failed to load configuration file: $($_.Exception.Message)"
    exit 1
}

# Extract configuration values
$dataGrowth = $config.FileSizes.DataGrowth
$logSize = $config.FileSizes.LogSize
$logGrowth = $config.FileSizes.LogGrowth
$fileSizeThreshold = $config.FileSizes.FileSizeThreshold
$logFile = "$PSScriptRoot\DatabaseCreation.log"
$enableEventLog = $config.EnableEventLog
$eventLogSource = $config.EventLogSource

try {
    
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
        -FileSizeThreshold $fileSizeThreshold
    Write-Log -Message "Calculated optimal number of data files: $numberOfDataFiles (based on expected size: $ExpectedDatabaseSize, threshold: $fileSizeThreshold)" -Level Info -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
    
    # Calculate per-file size based on ExpectedDatabaseSize (needed for disk space validation)
    $expectedSizeMB = Convert-SizeToInt -SizeString $ExpectedDatabaseSize
    $perFileSizeMB = [int][Math]::Ceiling($expectedSizeMB / $numberOfDataFiles)
    $perFileSizeString = "${perFileSizeMB}MB"
    Write-Log -Message "Calculated per-file size: $perFileSizeString (total expected: $ExpectedDatabaseSize / $numberOfDataFiles files)" -Level Info -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
    Write-Log -Message "File configuration: DataSize=$perFileSizeString, LogSize=$logSize, DataGrowth=$dataGrowth, LogGrowth=$logGrowth" -Level Info -LogFile $logFile -EnableEventLog $false

    # EARLY EXIT CHECK 2: Validate sufficient disk space (exit early if not enough space)
    Write-Log -Message "Validating disk space availability on data drive ${dataDrive}:\ and log drive ${logDrive}:\..." -Level Info -LogFile $logFile -EnableEventLog $false
    $hasSufficientSpace = Test-DbaSufficientDiskSpace `
        -SqlInstance $SqlInstance `
        -DataDrive $dataDrive `
        -LogDrive $logDrive `
        -NumberOfDataFiles $numberOfDataFiles `
        -DataSize $perFileSizeString `
        -LogSize $logSize `
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
        Write-Log -Message "  - Log file size: $logSize" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Data file growth: $dataGrowth" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Log file growth: $logGrowth" -Level Info -LogFile $logFile -EnableEventLog $false
        Write-Log -Message "  - Collation: $Collation" -Level Info -LogFile $logFile -EnableEventLog $false

        $newDbParams = @{
            SqlInstance = $SqlInstance
            Name = $Database_Name
            DataFilePath = $dataDirectory
            LogFilePath = $logDirectory
            PrimaryFileSize = $perFileSizeMB
            LogSize = (Convert-SizeToInt $logSize)
            PrimaryFileGrowth = (Convert-SizeToInt $dataGrowth)
            LogGrowth = (Convert-SizeToInt $logGrowth)
            Collation = $Collation
        }
        
        # Add secondary file parameters if more than one data file is needed
        if ($numberOfDataFiles -gt 1) {
            $newDbParams.SecondaryFileCount = $numberOfDataFiles - 1
            $newDbParams.SecondaryFilesize = $perFileSizeMB
            $newDbParams.SecondaryFileGrowth = (Convert-SizeToInt $dataGrowth)
        }

        try {
            Write-Log -Message "Creating database '$Database_Name' with $numberOfDataFiles data file(s)..." -Level Info -LogFile $logFile -EnableEventLog $false
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
            
            Write-Log -Message "Successfully created database: $Database_Name with $numberOfDataFiles data file(s) in PRIMARY filegroup" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource

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
            
            # ============================================================
            # STEP 2: Create Logins and Users (EXIT on failure)
            # ============================================================
            Write-Log -Message "STEP 2: Creating logins and users based on Pillar '$Pillar' and Datagroup '$Datagroup'..." -Level Info -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
            
            # Determine domain prefix based on Pillar
            if ($Pillar -eq 'PROD') {
                $domainPrefix = 'GLOW001\'
            }
            else {
                # DEV or ACC
                $domainPrefix = 'TDA001\'
            }
            
            # Determine login names based on Pillar
            if ($Pillar -eq 'DEV') {
                $loginNames = @(
                    "${domainPrefix}1005_GS_${Datagroup}0_DEV_RW",
                    "${domainPrefix}1005_GS_${Datagroup}0_FNC_RW",
                    "${domainPrefix}1005_GS_${Datagroup}0_PRS_RO",
                    "${domainPrefix}1005_GS_${Datagroup}0_PRS_RW"
                )
            }
            else {
                # ACC or PROD
                $loginNames = @(
                    "${domainPrefix}0005_GS_${Datagroup}0_FNC_RW",
                    "${domainPrefix}0005_GS_${Datagroup}0_PRS_RO",
                    "${domainPrefix}0005_GS_${Datagroup}0_PRS_RW"
                )
            }
            
            Write-Log -Message "Login names to create: $($loginNames -join ', ')" -Level Info -LogFile $logFile -EnableEventLog $false
            
            # Create logins and map as users (exit on failure)
            foreach ($loginName in $loginNames) {
                if ($PSCmdlet.ShouldProcess("$loginName", "Create login and database user")) {
                    # Check if login already exists (idempotent)
                    $existingLogin = Get-DbaLogin -SqlInstance $SqlInstance -Login $loginName -ErrorAction SilentlyContinue
                    if (-not $existingLogin) {
                        # Create login
                        New-DbaLogin -SqlInstance $SqlInstance -Login $loginName -ErrorAction Stop
                        Write-Log -Message "Created login: $loginName" -Level Info -LogFile $logFile -EnableEventLog $false
                    }
                    else {
                        Write-Log -Message "Login '$loginName' already exists (idempotent)" -Level Info -LogFile $logFile -EnableEventLog $false
                    }
                    
                    # Check if user already exists in database (idempotent)
                    $existingUser = Get-DbaDbUser -SqlInstance $SqlInstance -Database $Database_Name -User $loginName -ErrorAction SilentlyContinue
                    if (-not $existingUser) {
                        # Create database user mapped to login
                        New-DbaDbUser -SqlInstance $SqlInstance -Database $Database_Name -Login $loginName -Username $loginName -ErrorAction Stop
                        Write-Log -Message "Created database user: $loginName in database $Database_Name" -Level Info -LogFile $logFile -EnableEventLog $false
                    }
                    else {
                        Write-Log -Message "User '$loginName' already exists in database (idempotent)" -Level Info -LogFile $logFile -EnableEventLog $false
                    }
                }
                else {
                    Write-Log -Message "[WHATIF] Would create login and user: $loginName" -Level Info -LogFile $logFile -EnableEventLog $false
                }
            }
            
            Write-Log -Message "STEP 2 completed: All logins and users created successfully" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
            
            # ============================================================
            # STEP 3: Create db_executor Role (EXIT on failure)
            # ============================================================
            Write-Log -Message "STEP 3: Creating db_executor database role..." -Level Info -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
            
            if ($PSCmdlet.ShouldProcess("db_executor", "Create database role")) {
                # Check if db_executor role already exists (idempotent)
                $existingRole = Get-DbaDbRole -SqlInstance $SqlInstance -Database $Database_Name -Role 'db_executor' -ErrorAction SilentlyContinue
                if (-not $existingRole) {
                    # Create db_executor role
                    New-DbaDbRole -SqlInstance $SqlInstance -Database $Database_Name -Role 'db_executor' -ErrorAction Stop
                    Write-Log -Message "Created database role: db_executor" -Level Info -LogFile $logFile -EnableEventLog $false
                    
                    # Grant EXECUTE permission to db_executor role
                    Invoke-DbaQuery -SqlInstance $SqlInstance -Database $Database_Name -Query "GRANT EXECUTE TO [db_executor]" -ErrorAction Stop
                    Write-Log -Message "Granted EXECUTE permission to db_executor role" -Level Info -LogFile $logFile -EnableEventLog $false
                }
                else {
                    Write-Log -Message "Role 'db_executor' already exists (idempotent)" -Level Info -LogFile $logFile -EnableEventLog $false
                }
            }
            else {
                Write-Log -Message "[WHATIF] Would create db_executor role and grant EXECUTE permission" -Level Info -LogFile $logFile -EnableEventLog $false
            }
            
            Write-Log -Message "STEP 3 completed: db_executor role created successfully" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
            
            # ============================================================
            # STEP 4: Setup Security (EXIT on failure)
            # ============================================================
            Write-Log -Message "STEP 4: Setting up security for users..." -Level Info -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
            
            foreach ($loginName in $loginNames) {
                if ($PSCmdlet.ShouldProcess("$loginName", "Assign database roles")) {
                    # DEV_RW (DEV pillar only): db_owner
                    if ($Pillar -eq 'DEV' -and $loginName -like '*_DEV_RW') {
                        # Check if already member of db_owner (idempotent)
                        $existingMember = Get-DbaDbRoleMember -SqlInstance $SqlInstance -Database $Database_Name -Role 'db_owner' -ErrorAction SilentlyContinue | Where-Object { $_.UserName -eq $loginName }
                        if (-not $existingMember) {
                            Add-DbaDbRoleMember -SqlInstance $SqlInstance -Database $Database_Name -Role 'db_owner' -Member $loginName -Confirm:$false -ErrorAction Stop
                            Write-Log -Message "Added user '$loginName' to db_owner role" -Level Info -LogFile $logFile -EnableEventLog $false
                        }
                        else {
                            Write-Log -Message "User '$loginName' already member of db_owner (idempotent)" -Level Info -LogFile $logFile -EnableEventLog $false
                        }
                    }
                    # *_RO users: db_datareader
                    elseif ($loginName -like '*_RO') {
                        # Check if already member of db_datareader (idempotent)
                        $existingMember = Get-DbaDbRoleMember -SqlInstance $SqlInstance -Database $Database_Name -Role 'db_datareader' -ErrorAction SilentlyContinue | Where-Object { $_.UserName -eq $loginName }
                        if (-not $existingMember) {
                            Add-DbaDbRoleMember -SqlInstance $SqlInstance -Database $Database_Name -Role 'db_datareader' -Member $loginName -Confirm:$false -ErrorAction Stop
                            Write-Log -Message "Added user '$loginName' to db_datareader role" -Level Info -LogFile $logFile -EnableEventLog $false
                        }
                        else {
                            Write-Log -Message "User '$loginName' already member of db_datareader (idempotent)" -Level Info -LogFile $logFile -EnableEventLog $false
                        }
                    }
                    # *_RW users (FNC_RW, PRS_RW): db_datareader, db_datawriter, db_executor
                    elseif ($loginName -like '*_RW') {
                        # db_datareader
                        $existingMember = Get-DbaDbRoleMember -SqlInstance $SqlInstance -Database $Database_Name -Role 'db_datareader' -ErrorAction SilentlyContinue | Where-Object { $_.UserName -eq $loginName }
                        if (-not $existingMember) {
                            Add-DbaDbRoleMember -SqlInstance $SqlInstance -Database $Database_Name -Role 'db_datareader' -Member $loginName -Confirm:$false -ErrorAction Stop
                            Write-Log -Message "Added user '$loginName' to db_datareader role" -Level Info -LogFile $logFile -EnableEventLog $false
                        }
                        else {
                            Write-Log -Message "User '$loginName' already member of db_datareader (idempotent)" -Level Info -LogFile $logFile -EnableEventLog $false
                        }
                        
                        # db_datawriter
                        $existingMember = Get-DbaDbRoleMember -SqlInstance $SqlInstance -Database $Database_Name -Role 'db_datawriter' -ErrorAction SilentlyContinue | Where-Object { $_.UserName -eq $loginName }
                        if (-not $existingMember) {
                            Add-DbaDbRoleMember -SqlInstance $SqlInstance -Database $Database_Name -Role 'db_datawriter' -Member $loginName -Confirm:$false -ErrorAction Stop
                            Write-Log -Message "Added user '$loginName' to db_datawriter role" -Level Info -LogFile $logFile -EnableEventLog $false
                        }
                        else {
                            Write-Log -Message "User '$loginName' already member of db_datawriter (idempotent)" -Level Info -LogFile $logFile -EnableEventLog $false
                        }
                        
                        # db_executor
                        $existingMember = Get-DbaDbRoleMember -SqlInstance $SqlInstance -Database $Database_Name -Role 'db_executor' -ErrorAction SilentlyContinue | Where-Object { $_.UserName -eq $loginName }
                        if (-not $existingMember) {
                            Add-DbaDbRoleMember -SqlInstance $SqlInstance -Database $Database_Name -Role 'db_executor' -Member $loginName -Confirm:$false -ErrorAction Stop
                            Write-Log -Message "Added user '$loginName' to db_executor role" -Level Info -LogFile $logFile -EnableEventLog $false
                        }
                        else {
                            Write-Log -Message "User '$loginName' already member of db_executor (idempotent)" -Level Info -LogFile $logFile -EnableEventLog $false
                        }
                    }
                }
                else {
                    Write-Log -Message "[WHATIF] Would assign database roles to: $loginName" -Level Info -LogFile $logFile -EnableEventLog $false
                }
            }
            
            Write-Log -Message "STEP 4 completed: Security setup completed successfully" -Level Success -LogFile $logFile -EnableEventLog $enableEventLog -EventLogSource $eventLogSource
            
            # ============================================================
            # Configuration Summary
            # ============================================================
            Write-Log -Message "Database '$Database_Name' configuration summary:" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Total data files in PRIMARY filegroup: $numberOfDataFiles" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Data file location: $dataDirectory" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Log file location: $logDirectory" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Owner: sa" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Collation: $Collation" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Query Store: $(if ($server.VersionMajor -ge 13) { 'Enabled' } else { 'Not Available' })" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Pillar: $Pillar, Datagroup: $Datagroup" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Logins/Users: $($loginNames -join ', ')" -Level Info -LogFile $logFile -EnableEventLog $false
            Write-Log -Message "  - Database roles: db_executor (custom), plus standard roles assigned per user type" -Level Info -LogFile $logFile -EnableEventLog $false
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
