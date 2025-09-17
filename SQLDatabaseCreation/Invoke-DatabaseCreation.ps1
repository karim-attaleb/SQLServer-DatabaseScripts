<#
.SYNOPSIS
    Creates and configures SQL Server database using configuration file
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath
)

# Import required modules
if (-not (Get-Module -Name dbatools -ListAvailable)) {
    Install-Module -Name dbatools -Force -AllowClobber -Scope CurrentUser -SkipPublisherCheck
}
Import-Module dbatools -ErrorAction Stop
Import-Module .\DatabaseUtils.psm1 -ErrorAction Stop

# Load configuration
$config = Import-PowerShellDataFile -Path $ConfigPath
$logFile = $config.LogFile

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
            SecondaryFileCount = [Math]::Max(0, $config.Database.NumberOfDataFiles - 1)
            SecondaryFileGrowth = (Convert-SizeToInt $config.FileSizes.DataGrowth)
        }

        try {
            $newDb = New-DbaDatabase @newDbParams
            Write-Log -Message "Successfully created database: $($config.Database.Name)" -Level Success -LogFile $logFile

            # Set database owner
            $db = Get-DbaDatabase -SqlInstance $config.SqlInstance -Database $config.Database.Name
            if ($db.Owner -ne 'sa') {
                Set-DbaDbOwner -SqlInstance $config.SqlInstance -Database $config.Database.Name -TargetLogin 'sa'
                Write-Log -Message "Changed database owner to SA" -Level Success -LogFile $logFile
            }

            # Enable Query Store if SQL 2016+
            if ($server.VersionMajor -ge 13) {
                Enable-QueryStore -SqlInstance $config.SqlInstance -Database $config.Database.Name
                Write-Log -Message "Enabled Query Store for database" -Level Success -LogFile $logFile
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
