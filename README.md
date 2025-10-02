# SQL Server Database Creation Scripts

A PowerShell-based automation tool for creating and configuring SQL Server databases with optimal file distribution and professional logging.

## Overview

This repository provides PowerShell scripts to automate the creation of SQL Server databases with:
- Automatic calculation of optimal number of data files based on expected database size
- Configurable file sizes and growth settings
- Multi-drive support for data and log files
- Query Store enablement for SQL Server 2016+
- Comprehensive logging
- Error handling and validation

## Prerequisites

- **PowerShell**: Version 5.1 or higher
- **dbatools Module**: PowerShell module for SQL Server administration
- **SQL Server**: Access to a SQL Server instance (2012 or higher)
- **Permissions**: Appropriate permissions to create databases on the target SQL Server instance

## Installation

### 1. Install dbatools Module

```powershell
Install-Module -Name dbatools -Scope CurrentUser -Force -AllowClobber
```

### 2. Clone or Download Repository

```powershell
git clone https://github.com/karim-attaleb/sqlserver-databasescripts.git
cd sqlserver-databasescripts
```

## Configuration

Edit the `SQLDatabaseCreation/DatabaseConfig.psd1` file to customize your database settings:

```powershell
@{
    # SQL Server instance name (e.g., "localhost", "SERVER\INSTANCE")
    SqlInstance = "YourSQLServerInstance"

    # Database settings
    Database = @{
        Name = "DB_MSS0_DEMO"
        DataDrive = "G"  # Drive letter for data files
        LogDrive = "L"   # Drive letter for log files
        
        # Optional: Expected total database size for automatic file calculation
        # If specified, the number of data files will be calculated automatically
        # based on the FileSizeThreshold value
        ExpectedDatabaseSize = $null  # e.g., "50GB", "500MB", "1TB"
        
        # Used when ExpectedDatabaseSize is not specified
        NumberOfDataFiles = 4
    }

    # File size configuration
    FileSizes = @{
        DataSize = "200MB"        # Initial size of each data file
        DataGrowth = "100MB"      # Growth increment for data files
        LogSize = "100MB"         # Initial size of log file
        LogGrowth = "100MB"       # Growth increment for log file
        FileSizeThreshold = "10GB" # Maximum size per data file (used for auto-calculation)
    }

    # Logging
    LogFile = "DatabaseCreation_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
}
```

### Configuration Parameters Explained

#### SqlInstance
The name of your SQL Server instance. Examples:
- `"localhost"` - Default instance on local machine
- `"SERVER01"` - Named server
- `"SERVER01\INSTANCE01"` - Named instance

#### Database Settings
- **Name**: The name of the database to create
- **DataDrive**: Drive letter where data files will be stored (without colon)
- **LogDrive**: Drive letter where log files will be stored (without colon)
- **ExpectedDatabaseSize**: (Optional) Expected total size of the database. When specified, the script will automatically calculate the optimal number of data files to keep each file under the `FileSizeThreshold`
- **NumberOfDataFiles**: Number of data files to create. Used only when `ExpectedDatabaseSize` is not specified

#### FileSizes Settings
- **DataSize**: Initial size of each data file (e.g., "200MB", "1GB")
- **DataGrowth**: How much each data file grows when space is needed
- **LogSize**: Initial size of the transaction log file
- **LogGrowth**: How much the log file grows when space is needed
- **FileSizeThreshold**: Maximum desired size for each data file. Used to calculate the optimal number of files when `ExpectedDatabaseSize` is specified

### Automatic File Count Calculation

When you specify `ExpectedDatabaseSize` in the configuration, the script automatically calculates the optimal number of data files:

- **Formula**: `NumberOfFiles = Ceiling(ExpectedDatabaseSize / FileSizeThreshold)`
- **Minimum**: 1 file
- **Maximum**: 8 files (SQL Server best practice)

#### Examples:
- Expected: 5GB, Threshold: 10GB → 1 file
- Expected: 50GB, Threshold: 10GB → 5 files
- Expected: 100GB, Threshold: 10GB → 8 files (capped at maximum)

## Usage

### Basic Usage

```powershell
# Run the database creation script
.\SQLDatabaseCreation\Invoke-DatabaseCreation.ps1 -ConfigPath .\SQLDatabaseCreation\DatabaseConfig.psd1
```

### WhatIf Mode

Preview what would happen without actually creating the database:

```powershell
.\SQLDatabaseCreation\Invoke-DatabaseCreation.ps1 -ConfigPath .\SQLDatabaseCreation\DatabaseConfig.psd1 -WhatIf
```

### With Verbose Output

```powershell
.\SQLDatabaseCreation\Invoke-DatabaseCreation.ps1 -ConfigPath .\SQLDatabaseCreation\DatabaseConfig.psd1 -Verbose
```

## Examples

### Example 1: Create Database with Manual File Count

```powershell
# DatabaseConfig.psd1
@{
    SqlInstance = "localhost"
    Database = @{
        Name = "MyDatabase"
        DataDrive = "D"
        LogDrive = "E"
        ExpectedDatabaseSize = $null
        NumberOfDataFiles = 4
    }
    FileSizes = @{
        DataSize = "500MB"
        DataGrowth = "250MB"
        LogSize = "250MB"
        LogGrowth = "100MB"
        FileSizeThreshold = "10GB"
    }
    LogFile = "DatabaseCreation.log"
}

# Run
.\SQLDatabaseCreation\Invoke-DatabaseCreation.ps1 -ConfigPath .\SQLDatabaseCreation\DatabaseConfig.psd1
```

### Example 2: Create Database with Automatic File Count

```powershell
# DatabaseConfig.psd1
@{
    SqlInstance = "localhost"
    Database = @{
        Name = "LargeDatabase"
        DataDrive = "D"
        LogDrive = "E"
        ExpectedDatabaseSize = "50GB"  # Automatically calculates 5 files with 10GB threshold
        NumberOfDataFiles = 4          # Ignored when ExpectedDatabaseSize is set
    }
    FileSizes = @{
        DataSize = "1GB"
        DataGrowth = "500MB"
        LogSize = "500MB"
        LogGrowth = "250MB"
        FileSizeThreshold = "10GB"
    }
    LogFile = "DatabaseCreation.log"
}

# Run
.\SQLDatabaseCreation\Invoke-DatabaseCreation.ps1 -ConfigPath .\SQLDatabaseCreation\DatabaseConfig.psd1
```

## Features

### Automatic Directory Creation
The script automatically creates the necessary directories on the data and log drives if they don't exist.

### Query Store Enablement
For SQL Server 2016 and later, Query Store is automatically enabled with optimized settings:
- State: ReadWrite
- Capture Mode: Auto
- Max Size: 100 MB
- Cleanup Mode: Auto

### Comprehensive Logging
All operations are logged to a timestamped log file with:
- Timestamp for each operation
- Log level (Info, Warning, Error, Success)
- Detailed error messages and stack traces

### Error Handling
Robust error handling ensures:
- Connection validation before operations
- Graceful handling of existing databases
- Detailed error reporting
- Non-zero exit codes on failure

## Testing

The repository includes comprehensive Pester tests for all functions.

### Run All Tests

```powershell
# Install Pester if not already installed
Install-Module -Name Pester -Force -SkipPublisherCheck

# Run tests
Invoke-Pester -Path .\Tests\ -Output Detailed
```

### Run Specific Test File

```powershell
Invoke-Pester -Path .\Tests\DatabaseUtils.Tests.ps1 -Output Detailed
```

## Module Functions

The `DatabaseUtils.psm1` module provides the following functions:

### Convert-SizeToInt
Converts size strings (e.g., "100MB", "10GB") to integer values in MB.

### Calculate-OptimalDataFiles
Calculates the optimal number of data files based on expected database size and threshold.

### Initialize-Directories
Creates necessary directories for data and log files if they don't exist.

### Write-Log
Writes log messages to both console and log file with different severity levels.

### Enable-QueryStore
Enables and configures Query Store for SQL Server 2016+.

Use `Get-Help <FunctionName> -Full` to see detailed help for each function.

## Troubleshooting

### Issue: "Cannot connect to SQL Server"
**Solution**: Verify that:
- SQL Server service is running
- SQL Server instance name is correct
- You have network connectivity to the server
- Windows Firewall allows SQL Server connections

### Issue: "Access denied" or permission errors
**Solution**: Ensure your Windows account or SQL login has:
- `CREATE DATABASE` permission on the SQL Server instance
- Write permissions on the data and log drive directories

### Issue: "Drive not found"
**Solution**: 
- Verify the drive letters exist on the target server
- Ensure the drives have sufficient free space
- Check that the SQL Server service account has access to the drives

### Issue: Database already exists
**Solution**: The script will skip creation and log a warning. To recreate:
1. Manually drop the existing database
2. Run the script again

## Contributing

Contributions are welcome! Please ensure:
- Code follows PowerShell best practices
- All functions have comment-based help
- New features include Pester tests
- Tests pass before submitting PR

## License

This project is provided as-is for database administration purposes.

## Author

Created by karim-attaleb (karim_attaleb01@yahoo.fr)

## Links

- [dbatools Documentation](https://dbatools.io/)
- [SQL Server Best Practices](https://learn.microsoft.com/en-us/sql/relational-databases/databases/database-files-and-filegroups)
- [Pester Testing Framework](https://pester.dev/)
