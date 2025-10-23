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

    # Database Users (optional)
    # List of users to create in the database after it's created.
    # Each user must be mapped to an existing SQL Server login.
    # Make sure the logins exist before running this script.
    Users = @(
        # Example 1: SQL Authentication user with read/write permissions
        # @{
        #     LoginName = "AppUser"           # Existing SQL Server login name
        #     UserName = "AppUser"            # Database username (optional, defaults to LoginName)
        #     DatabaseRoles = @("db_datareader", "db_datawriter")  # Database roles to assign
        #     DefaultSchema = "dbo"           # Default schema (optional, defaults to "dbo")
        # }
        
        # Example 2: Windows Authentication user with full control
        # @{
        #     LoginName = "DOMAIN\ServiceAccount"
        #     DatabaseRoles = @("db_owner")
        # }
        
        # Example 3: Read-only user
        # @{
        #     LoginName = "ReadOnlyUser"
        #     DatabaseRoles = @("db_datareader")
        # }
        
        # Example 4: Custom username different from login
        # @{
        #     LoginName = "DOMAIN\AppPool"
        #     UserName = "WebAppUser"
        #     DatabaseRoles = @("db_datareader", "db_datawriter")
        #     DefaultSchema = "app"
        # }
    )

    # Logging
    LogFile = "DatabaseCreation.log"
    
    # Windows Event Log integration (requires administrative privileges)
    # Set to $true to write important events to Windows Application Event Log
    EnableEventLog = $true
    EventLogSource = "SQLDatabaseScripts"
}
