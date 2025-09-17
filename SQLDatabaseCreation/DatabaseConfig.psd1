@{
    # SQL Server Configuration
    SqlInstance = "YourSQLServerInstance"

    # Database Configuration
    Database = {
        Name = "DB_MSS0_DEMO"
        DataDrive = "G"
        LogDrive = "L"
        NumberOfDataFiles = 4
    }

    # File Configuration
    FileSizes = {
        DataSize = "200MB"
        DataGrowth = "100MB"
        LogSize = "100MB"
        LogGrowth = "100MB"
        FileSizeThreshold = "10GB"
    }

    # Logging
    LogFile = "DatabaseCreation_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
}
