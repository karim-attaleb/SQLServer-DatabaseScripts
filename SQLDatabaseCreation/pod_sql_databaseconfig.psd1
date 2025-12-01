@{
    # SQL Server Configuration
    SqlInstance = "YourSQLServerInstance"

    # Database Configuration
    Database = @{
        Name = "DB_MSS0_DEMO"
        DataDrive = "G"
        LogDrive = "L"
        
        # Expected total database size used to automatically calculate
        # the optimal number of data files based on FileSizeThreshold.
        # If size > threshold, multiple files will be created.
        # Otherwise, a single file will be used.
        # Examples: "50GB", "500MB", "1TB"
        ExpectedDatabaseSize = "5GB"
    }

    # File Configuration
    FileSizes = @{
        DataSize = "200MB"
        DataGrowth = "100MB"
        LogSize = "100MB"
        LogGrowth = "100MB"
        
        # Maximum desired size for each data file.
        # Used to calculate optimal number of files when ExpectedDatabaseSize is specified.
        FileSizeThreshold = "10GB"
    }

    # Logging
    LogFile = "DatabaseCreation.log"
    
    # Windows Event Log integration (requires administrative privileges)
    # Set to $true to write important events to Windows Application Event Log
    EnableEventLog = $true
    EventLogSource = "SQLDatabaseScripts"
}
