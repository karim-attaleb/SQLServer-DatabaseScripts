@{
    # File Configuration
    # These values control database file sizes and growth settings
    FileSizes = @{
        # Growth increment for data files
        DataGrowth = "512MB"
        
        # Initial size for log file
        LogSize = "1024MB"
        
        # Growth increment for log file
        LogGrowth = "512MB"
        
        # Maximum desired size for each data file.
        # Used to calculate optimal number of files when ExpectedDatabaseSize is specified.
        FileSizeThreshold = "500MB"
    }

    # Windows Event Log integration (requires administrative privileges)
    # Set to $true to write important events to Windows Application Event Log
    EnableEventLog = $true
    EventLogSource = "SQLDatabaseScripts"
}
