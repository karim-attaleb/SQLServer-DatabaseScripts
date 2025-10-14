<#
.SYNOPSIS
    Converts a size string to an integer value in megabytes.

.DESCRIPTION
    Parses a size string with units (MB, GB, TB) and converts it to an integer
    value in megabytes for use with SQL Server file size parameters.

.PARAMETER SizeString
    A string representing a size value with units (e.g., "200MB", "10GB", "1TB").
    Must match the pattern: digits followed by MB, GB, or TB.

.EXAMPLE
    Convert-SizeToInt -SizeString "200MB"
    Returns: 200

.EXAMPLE
    Convert-SizeToInt -SizeString "10GB"
    Returns: 10240

.EXAMPLE
    Convert-SizeToInt -SizeString "1TB"
    Returns: 1048576

.OUTPUTS
    System.Int32
    The size value in megabytes.

.NOTES
    This function is used internally to convert configuration size strings
    into values that SQL Server commands can use.
#>
function Convert-SizeToInt {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidatePattern('^\d+(MB|GB|TB)$')]
        [string]$SizeString
    )

    process {
        if ($SizeString -match '^(\d+)(MB|GB|TB)$') {
            $size = [int]$matches[1]
            $unit = $matches[2]
            
            $result = switch ($unit) {
                'MB' { $size }
                'GB' { $size * 1024 }
                'TB' { $size * 1024 * 1024 }
                default { $size }
            }
            
            Write-Verbose "Converted $SizeString to $result MB"
            return $result
        }
        
        Write-Warning "Invalid size string format: $SizeString. Returning as-is."
        return $SizeString
    }
}

<#
.SYNOPSIS
    Writes a log message to both console and log file.

.DESCRIPTION
    Writes a timestamped log message with a severity level to both the console
    (with color coding) and a log file. Used for tracking script execution and
    troubleshooting.

.PARAMETER Message
    The log message to write.

.PARAMETER Level
    The severity level of the message. Valid values: Info, Warning, Error, Success.
    Default is Info.

.PARAMETER LogFile
    The path to the log file where the message will be appended.

.EXAMPLE
    Write-Log -Message "Database created successfully" -Level Success -LogFile "C:\Logs\db.log"
    Writes a success message to console (in green) and to the log file.

.EXAMPLE
    Write-Log -Message "Connection established" -LogFile "C:\Logs\db.log"
    Writes an info message to console (in white) and to the log file.

.NOTES
    Color coding:
    - Info: White
    - Warning: Yellow
    - Error: Red
    - Success: Green
#>
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info",
        
        [Parameter(Mandatory = $true)]
        [string]$LogFile,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableEventLog = $false,
        
        [Parameter(Mandatory = $false)]
        [string]$EventLogSource = "SQLDatabaseScripts"
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"
        
        $colorMap = @{
            "Info" = "White"
            "Warning" = "Yellow"
            "Error" = "Red"
            "Success" = "Green"
        }
        
        Write-Host $logEntry -ForegroundColor $colorMap[$Level]
        Add-Content -Path $LogFile -Value $logEntry -Encoding UTF8 -ErrorAction Stop
        
        if ($EnableEventLog) {
            try {
                if (-not [System.Diagnostics.EventLog]::SourceExists($EventLogSource)) {
                    New-EventLog -LogName Application -Source $EventLogSource -ErrorAction SilentlyContinue
                }
                
                $eventType = switch ($Level) {
                    "Error" { "Error" }
                    "Warning" { "Warning" }
                    default { "Information" }
                }
                
                $eventId = switch ($Level) {
                    "Error" { 1001 }
                    "Warning" { 2001 }
                    "Success" { 3001 }
                    default { 4001 }
                }
                
                Write-EventLog -LogName Application -Source $EventLogSource -EntryType $eventType -EventId $eventId -Message $Message -ErrorAction SilentlyContinue
            }
            catch {
                Write-Verbose "Could not write to Windows Event Log (may require admin privileges): $($_.Exception.Message)"
            }
        }
    }
    catch {
        Write-Warning "Failed to write to log file: $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Initializes directory structure for SQL Server data and log files.

.DESCRIPTION
    Creates the necessary directory structure for SQL Server database files if they
    don't already exist. Creates separate directories for data files and log files
    based on the SQL Server instance name.

.PARAMETER DataDrive
    The drive letter (without colon) where data files will be stored.

.PARAMETER LogDrive
    The drive letter (without colon) where log files will be stored.

.PARAMETER ServerInstanceName
    The SQL Server instance name, used to create instance-specific subdirectories.

.PARAMETER LogFile
    The path to the log file for recording directory creation operations.

.EXAMPLE
    Initialize-Directories -DataDrive "G" -LogDrive "L" -ServerInstanceName "MSSQLSERVER" -LogFile "C:\Logs\db.log"
    Creates G:\MSSQLSERVER\data and L:\MSSQLSERVER\log directories if they don't exist.

.NOTES
    This function is typically called automatically by the database creation script
    to ensure proper directory structure exists before creating database files.
#>
function Initialize-Directories {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Z]$')]
        [string]$DataDrive,
        
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Z]$')]
        [string]$LogDrive,
        
        [Parameter(Mandatory = $true)]
        [string]$ServerInstanceName,
        
        [Parameter(Mandatory = $true)]
        [string]$LogFile,
        
        [Parameter(Mandatory = $false)]
        [bool]$EnableEventLog = $false,
        
        [Parameter(Mandatory = $false)]
        [string]$EventLogSource = "SQLDatabaseScripts"
    )

    Write-Log -Message "Initializing directory structure for SQL Server instance: $ServerInstanceName" -Level Info -LogFile $LogFile -EnableEventLog $EnableEventLog -EventLogSource $EventLogSource
    Write-Log -Message "Data drive: ${DataDrive}:\, Log drive: ${LogDrive}:\" -Level Info -LogFile $LogFile -EnableEventLog $false

    $paths = @(
        "$DataDrive`:\$ServerInstanceName\data",
        "$LogDrive`:\$ServerInstanceName\log"
    )

    foreach ($path in $paths) {
        try {
            if (-not (Test-Path -Path $path)) {
                Write-Log -Message "Creating directory: $path" -Level Info -LogFile $LogFile -EnableEventLog $false
                New-Item -ItemType Directory -Path $path -Force -ErrorAction Stop | Out-Null
                Write-Log -Message "Successfully created directory: $path" -Level Success -LogFile $LogFile -EnableEventLog $EnableEventLog -EventLogSource $EventLogSource
                Write-Verbose "Successfully created directory: $path"
            }
            else {
                Write-Log -Message "Directory already exists: $path" -Level Info -LogFile $LogFile -EnableEventLog $false
                Write-Verbose "Directory already exists: $path"
            }
        }
        catch {
            Write-Log -Message "Failed to create directory $path`: $($_.Exception.Message)" -Level Error -LogFile $LogFile -EnableEventLog $EnableEventLog -EventLogSource $EventLogSource
            throw
        }
    }
}

<#
.SYNOPSIS
    Enables and configures Query Store for a SQL Server database.

.DESCRIPTION
    Enables Query Store on a SQL Server 2016+ database with optimized default settings.
    Query Store captures query execution plans and runtime statistics for performance
    analysis and troubleshooting.

.PARAMETER SqlInstance
    The SQL Server instance name where the database is located.

.PARAMETER Database
    The name of the database on which to enable Query Store.

.EXAMPLE
    Enable-QueryStore -SqlInstance "localhost" -Database "MyDatabase"
    Enables Query Store on MyDatabase with default settings.

.NOTES
    Query Store Configuration:
    - State: ReadWrite
    - Stale Query Threshold: 31 days
    - Capture Mode: Auto (captures relevant queries automatically)
    - Max Size: 100 MB
    - Flush Interval: 900 seconds (15 minutes)
    - Cleanup Mode: Auto (automatically removes old data)
    - Max Plans Per Query: 100

    Requires SQL Server 2016 or later.
    Requires dbatools module.
#>
function Enable-QueryStore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SqlInstance,
        
        [Parameter(Mandatory = $true)]
        [string]$Database
    )

    try {
        $queryStoreConfig = @{
            SqlInstance = $SqlInstance
            Database = $Database
            State = 'ReadWrite'
            StaleQueryThreshold = [timespan]::FromDays(31).Days
            CaptureMode = 'Auto'
            MaxSize = 100
            FlushInterval = [timespan]::FromSeconds(900).TotalSeconds
            CleanupMode = 'Auto'
            MaxPlansPerQuery = 100
        }

        Write-Verbose "Enabling Query Store for database: $Database"
        Set-DbaDbQueryStoreOption @queryStoreConfig -ErrorAction Stop
        Write-Verbose "Query Store enabled successfully"
    }
    catch {
        Write-Warning "Failed to enable Query Store: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Calculates the optimal number of data files based on expected database size and threshold.

.DESCRIPTION
    Determines the optimal number of data files to create for a database by dividing
    the expected database size by the file size threshold. The result is capped at a
    maximum of 8 files (SQL Server best practice for proportional fill algorithm
    efficiency) and has a minimum of 1 file.

.PARAMETER ExpectedDatabaseSize
    The expected total size of the database as a string with units (e.g., "50GB", "500MB", "1TB").
    Must match the pattern: digits followed by MB, GB, or TB.

.PARAMETER FileSizeThreshold
    The maximum desired size for each data file as a string with units (e.g., "10GB").
    Must match the pattern: digits followed by MB, GB, or TB.

.EXAMPLE
    Calculate-OptimalDataFiles -ExpectedDatabaseSize "50GB" -FileSizeThreshold "10GB"
    Returns: 5
    Calculates that 5 files are needed to keep each file at or below 10GB.

.EXAMPLE
    Calculate-OptimalDataFiles -ExpectedDatabaseSize "5GB" -FileSizeThreshold "10GB"
    Returns: 1
    Database size is below threshold, so only 1 file is needed.

.EXAMPLE
    Calculate-OptimalDataFiles -ExpectedDatabaseSize "100GB" -FileSizeThreshold "10GB"
    Returns: 8
    Would calculate 10 files, but is capped at 8 files (SQL Server best practice).

.OUTPUTS
    System.Int32
    The optimal number of data files to create (between 1 and 8).

.NOTES
    SQL Server uses a proportional fill algorithm across multiple data files in a filegroup.
    While you can have more than 8 files, performance benefits diminish and management
    complexity increases beyond 8 files for most workloads.

    Formula: NumberOfFiles = Ceiling(ExpectedDatabaseSize / FileSizeThreshold)
    Constraints: Min = 1, Max = 8
#>
function Calculate-OptimalDataFiles {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d+(MB|GB|TB)$')]
        [string]$ExpectedDatabaseSize,
        
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d+(MB|GB|TB)$')]
        [string]$FileSizeThreshold
    )

    try {
        $expectedSizeMB = Convert-SizeToInt -SizeString $ExpectedDatabaseSize
        $thresholdMB = Convert-SizeToInt -SizeString $FileSizeThreshold
        
        if ($thresholdMB -le 0) {
            throw "FileSizeThreshold must be greater than 0"
        }
        
        $calculatedFiles = [Math]::Ceiling($expectedSizeMB / $thresholdMB)
        
        $optimalFiles = [Math]::Max(1, [Math]::Min(8, $calculatedFiles))
        
        Write-Verbose "Expected size: $expectedSizeMB MB, Threshold: $thresholdMB MB"
        Write-Verbose "Calculated files: $calculatedFiles, Optimal files (capped 1-8): $optimalFiles"
        
        return $optimalFiles
    }
    catch {
        Write-Error "Failed to calculate optimal data files: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Validates that SQL Server host drives have sufficient disk space for database creation.

.DESCRIPTION
    Checks available disk space on specified drives using Get-DbaDiskSpace and compares
    against required space for database files. Ensures adequate capacity exists before
    attempting database creation to prevent out-of-space errors during operations.
    
    Required space is calculated as:
    - Data drive: NumberOfDataFiles × DataSize
    - Log drive: LogSize
    - Safety margin: Additional percentage buffer (default 10%)

.PARAMETER SqlInstance
    The SQL Server instance name to check disk space on.

.PARAMETER DataDrive
    The drive letter (without colon) where data files will be stored.

.PARAMETER LogDrive
    The drive letter (without colon) where log files will be stored.

.PARAMETER NumberOfDataFiles
    The number of data files that will be created.

.PARAMETER DataSize
    The initial size of each data file as a string (e.g., "200MB", "1GB").

.PARAMETER LogSize
    The initial size of the log file as a string (e.g., "100MB", "500MB").

.PARAMETER SafetyMarginPercent
    The percentage of additional free space to require as a buffer. Default is 10.
    For example, if required space is 1GB and safety margin is 10%, will require 1.1GB free.

.EXAMPLE
    Test-DbaSufficientDiskSpace -SqlInstance "localhost" -DataDrive "G" -LogDrive "L" -NumberOfDataFiles 4 -DataSize "200MB" -LogSize "100MB"
    Checks if G: has at least 880MB free (4×200MB + 10%) and L: has at least 110MB free (100MB + 10%).

.EXAMPLE
    Test-DbaSufficientDiskSpace -SqlInstance "SERVER01" -DataDrive "D" -LogDrive "E" -NumberOfDataFiles 8 -DataSize "1GB" -LogSize "500MB" -SafetyMarginPercent 20
    Checks with 20% safety margin instead of default 10%.

.OUTPUTS
    System.Boolean
    Returns $true if both drives have sufficient space, $false otherwise.

.NOTES
    This function requires dbatools module and appropriate permissions to query disk space
    on the target SQL Server host. Uses WMI/CIM to retrieve disk information.
#>
function Test-DbaSufficientDiskSpace {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SqlInstance,
        
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Z]$')]
        [string]$DataDrive,
        
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Z]$')]
        [string]$LogDrive,
        
        [Parameter(Mandatory = $true)]
        [int]$NumberOfDataFiles,
        
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d+(MB|GB|TB)$')]
        [string]$DataSize,
        
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^\d+(MB|GB|TB)$')]
        [string]$LogSize,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 100)]
        [int]$SafetyMarginPercent = 10
    )

    try {
        Write-Verbose "Checking disk space on SQL Server host: $SqlInstance"
        Write-Verbose "Parameters: DataDrive=${DataDrive}, LogDrive=${LogDrive}, NumberOfDataFiles=${NumberOfDataFiles}, DataSize=${DataSize}, LogSize=${LogSize}, SafetyMargin=${SafetyMarginPercent}%"
        
        $diskInfo = Get-DbaDiskSpace -ComputerName $SqlInstance -ErrorAction Stop
        Write-Verbose "Retrieved disk information for $($diskInfo.Count) drive(s)"
        
        $dataSizeMB = Convert-SizeToInt -SizeString $DataSize
        $logSizeMB = Convert-SizeToInt -SizeString $LogSize
        
        $requiredDataSpaceMB = $NumberOfDataFiles * $dataSizeMB
        $requiredLogSpaceMB = $logSizeMB
        
        $safetyMultiplier = 1 + ($SafetyMarginPercent / 100.0)
        $requiredDataSpaceWithMarginMB = [Math]::Ceiling($requiredDataSpaceMB * $safetyMultiplier)
        $requiredLogSpaceWithMarginMB = [Math]::Ceiling($requiredLogSpaceMB * $safetyMultiplier)
        
        Write-Verbose "Converted sizes: DataSize=${dataSizeMB}MB, LogSize=${logSizeMB}MB"
        Write-Verbose "Required space: Data drive = ${requiredDataSpaceWithMarginMB}MB (${NumberOfDataFiles} files × ${dataSizeMB}MB + ${SafetyMarginPercent}% margin)"
        Write-Verbose "Required space: Log drive = ${requiredLogSpaceWithMarginMB}MB (${logSizeMB}MB + ${SafetyMarginPercent}% margin)"
        
        $dataDriveName = "${DataDrive}:\"
        $dataDiskInfo = $diskInfo | Where-Object { $_.Name -eq $dataDriveName }
        
        if (-not $dataDiskInfo) {
            Write-Error "Data drive ${dataDriveName} not found on SQL Server host"
            Write-Verbose "Available drives: $($diskInfo | ForEach-Object { $_.Name } | Join-String -Separator ', ')"
            return $false
        }
        
        $dataAvailableMB = [Math]::Floor($dataDiskInfo.Free / 1MB)
        $dataTotalMB = [Math]::Floor($dataDiskInfo.Size / 1MB)
        $dataUsedMB = $dataTotalMB - $dataAvailableMB
        $dataUsedPercent = [Math]::Round(($dataUsedMB / $dataTotalMB) * 100, 2)
        
        Write-Verbose "Data drive ${dataDriveName} disk space: ${dataAvailableMB}MB free / ${dataTotalMB}MB total (${dataUsedPercent}% used)"
        
        if ($dataAvailableMB -lt $requiredDataSpaceWithMarginMB) {
            Write-Error "Insufficient space on data drive ${dataDriveName}: ${dataAvailableMB}MB available, ${requiredDataSpaceWithMarginMB}MB required (including ${SafetyMarginPercent}% safety margin)"
            return $false
        }
        
        if ($LogDrive -ne $DataDrive) {
            $logDriveName = "${LogDrive}:\"
            $logDiskInfo = $diskInfo | Where-Object { $_.Name -eq $logDriveName }
            
            if (-not $logDiskInfo) {
                Write-Error "Log drive ${logDriveName} not found on SQL Server host"
                Write-Verbose "Available drives: $($diskInfo | ForEach-Object { $_.Name } | Join-String -Separator ', ')"
                return $false
            }
            
            $logAvailableMB = [Math]::Floor($logDiskInfo.Free / 1MB)
            $logTotalMB = [Math]::Floor($logDiskInfo.Size / 1MB)
            $logUsedMB = $logTotalMB - $logAvailableMB
            $logUsedPercent = [Math]::Round(($logUsedMB / $logTotalMB) * 100, 2)
            
            Write-Verbose "Log drive ${logDriveName} disk space: ${logAvailableMB}MB free / ${logTotalMB}MB total (${logUsedPercent}% used)"
            
            if ($logAvailableMB -lt $requiredLogSpaceWithMarginMB) {
                Write-Error "Insufficient space on log drive ${logDriveName}: ${logAvailableMB}MB available, ${requiredLogSpaceWithMarginMB}MB required (including ${SafetyMarginPercent}% safety margin)"
                return $false
            }
        }
        else {
            $combinedRequiredMB = $requiredDataSpaceWithMarginMB + $requiredLogSpaceWithMarginMB
            Write-Verbose "Combined requirement for drive ${dataDriveName}: ${combinedRequiredMB}MB"
            
            if ($dataAvailableMB -lt $combinedRequiredMB) {
                Write-Error "Insufficient space on drive ${dataDriveName}: ${dataAvailableMB}MB available, ${combinedRequiredMB}MB required for both data and log (including ${SafetyMarginPercent}% safety margin)"
                return $false
            }
        }
        
        Write-Verbose "Disk space validation passed: Sufficient space available on all drives"
        return $true
    }
    catch {
        Write-Error "Failed to check disk space: $($_.Exception.Message)"
        throw
    }
}

Export-ModuleMember -Function Convert-SizeToInt, Write-Log, Initialize-Directories, Enable-QueryStore, Calculate-OptimalDataFiles, Test-DbaSufficientDiskSpace
