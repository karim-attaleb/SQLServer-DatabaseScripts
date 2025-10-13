@{
    # SQL Server Configuration
    SqlInstance = "YourSQLServerInstance"

    # Database Configuration
    Database = @{
        Name = "DB_MSS0_DEMO"
        DataDrive = "G"
        LogDrive = "L"
        
        # Optional: Specify expected total database size to automatically calculate
        # the optimal number of data files based on FileSizeThreshold.
        # If not provided, NumberOfDataFiles below will be used.
        # Examples: "50GB", "500MB", "1TB"
        ExpectedDatabaseSize = $null
        
        # Number of data files to create.
        # This value is used only when ExpectedDatabaseSize is not specified.
        NumberOfDataFiles = 4
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
}
