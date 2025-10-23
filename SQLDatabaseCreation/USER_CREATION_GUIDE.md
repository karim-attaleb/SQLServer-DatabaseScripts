# Database User Creation Guide

## Overview

The database creation scripts now support automatic creation of database users during the database creation process. This feature allows you to:

- Create database users mapped to existing SQL Server logins
- Assign users to multiple database roles (permissions)
- Support both SQL Authentication and Windows Authentication
- Configure custom usernames and schemas

## Prerequisites

Before creating database users, ensure that:

1. **SQL Server logins must already exist** - The script does not create logins, only database users
2. You have appropriate permissions to create users and assign roles in the target database
3. The dbatools PowerShell module is installed

## Configuration

### Adding Users to DatabaseConfig.psd1

Add a `Users` array to your configuration file with user definitions:

```powershell
@{
    # ... other configuration ...
    
    Users = @(
        @{
            LoginName = "AppUser"
            DatabaseRoles = @("db_datareader", "db_datawriter")
        },
        @{
            LoginName = "DOMAIN\ServiceAccount"
            DatabaseRoles = @("db_owner")
        }
    )
}
```

### User Configuration Options

Each user entry supports the following properties:

| Property | Required | Description | Example |
|----------|----------|-------------|---------|
| `LoginName` | Yes | Existing SQL Server login name | `"AppUser"` or `"DOMAIN\User"` |
| `UserName` | No | Database username (defaults to LoginName) | `"WebAppUser"` |
| `DatabaseRoles` | No | Array of database roles to assign | `@("db_datareader", "db_datawriter")` |
| `DefaultSchema` | No | Default schema for the user (defaults to "dbo") | `"app"` |

### Common Database Roles

| Role | Permissions |
|------|-------------|
| `db_owner` | Full control over the database |
| `db_datareader` | Read all data from all tables |
| `db_datawriter` | Add, update, or delete data from all tables |
| `db_ddladmin` | Create, alter, or drop objects |
| `db_securityadmin` | Manage roles and permissions |
| `db_accessadmin` | Add or remove database users |
| `db_backupoperator` | Backup the database |
| `db_denydatareader` | Cannot read any data |
| `db_denydatawriter` | Cannot write any data |

## Examples

### Example 1: Simple SQL Authentication User

```powershell
@{
    LoginName = "AppUser"
    DatabaseRoles = @("db_datareader", "db_datawriter")
}
```

Creates a user `AppUser` with read/write permissions.

### Example 2: Windows Authentication User

```powershell
@{
    LoginName = "CONTOSO\ServiceAccount"
    DatabaseRoles = @("db_owner")
}
```

Creates a user mapped to the Windows account with full database control.

### Example 3: Custom Username and Schema

```powershell
@{
    LoginName = "DOMAIN\AppPool"
    UserName = "WebAppUser"
    DatabaseRoles = @("db_datareader", "db_datawriter")
    DefaultSchema = "app"
}
```

Creates a user named `WebAppUser` (different from login name) with a custom schema.

### Example 4: Read-Only User

```powershell
@{
    LoginName = "ReportingUser"
    DatabaseRoles = @("db_datareader")
}
```

Creates a user with read-only access.

### Example 5: Minimal Permissions User

```powershell
@{
    LoginName = "BasicUser"
}
```

Creates a user with only public role permissions (minimal access).

## Complete Configuration Example

```powershell
@{
    SqlInstance = "SQLSERVER\INSTANCE01"
    
    Database = @{
        Name = "MyAppDB"
        DataDrive = "G"
        LogDrive = "L"
        ExpectedDatabaseSize = "50GB"
    }
    
    FileSizes = @{
        DataSize = "1GB"
        DataGrowth = "100MB"
        LogSize = "500MB"
        LogGrowth = "100MB"
        FileSizeThreshold = "10GB"
    }
    
    Users = @(
        # Application user with read/write access
        @{
            LoginName = "AppUser"
            DatabaseRoles = @("db_datareader", "db_datawriter")
        },
        
        # Service account with full control
        @{
            LoginName = "DOMAIN\ServiceAccount"
            DatabaseRoles = @("db_owner")
        },
        
        # Read-only reporting user
        @{
            LoginName = "ReportUser"
            DatabaseRoles = @("db_datareader")
            DefaultSchema = "reporting"
        },
        
        # Web application pool identity
        @{
            LoginName = "IIS APPPOOL\MyAppPool"
            UserName = "WebUser"
            DatabaseRoles = @("db_datareader", "db_datawriter", "db_ddladmin")
        }
    )
    
    LogFile = "DatabaseCreation.log"
    EnableEventLog = $true
    EventLogSource = "SQLDatabaseScripts"
}
```

## Usage

Run the database creation script as usual:

```powershell
.\Invoke-DatabaseCreation.ps1 -ConfigPath .\DatabaseConfig.psd1
```

The script will:
1. Create the database
2. Set the database owner
3. Enable Query Store (if SQL 2016+)
4. **Create all configured users and assign their roles**
5. Log all operations

## Logging

User creation is logged with detailed information:

```
[2025-10-23 09:27:31] [Info] Processing database user creation...
[2025-10-23 09:27:31] [Info] Creating database user 'AppUser' for database 'MyAppDB'
[2025-10-23 09:27:31] [Success] Successfully created database user 'AppUser' in database 'MyAppDB'
[2025-10-23 09:27:31] [Info] Assigning database roles to user 'AppUser': db_datareader, db_datawriter
[2025-10-23 09:27:31] [Success] Successfully assigned roles to user 'AppUser'
```

## Error Handling

### Login Doesn't Exist

If the specified login doesn't exist on the SQL Server instance:

```
[2025-10-23 09:27:31] [Error] Login 'NonExistentUser' does not exist on SQL Server instance 'SERVER\INSTANCE'. Create the login first before adding database user.
```

**Solution**: Create the SQL Server login first using:
```sql
-- For SQL Authentication
CREATE LOGIN AppUser WITH PASSWORD = 'SecurePassword123!';

-- For Windows Authentication
CREATE LOGIN [DOMAIN\ServiceAccount] FROM WINDOWS;
```

### User Already Exists

If the user already exists in the database:

```
[2025-10-23 09:27:31] [Warning] User 'AppUser' already exists in database 'MyAppDB'. Skipping creation.
```

This is non-fatal and the script continues.

### Role Assignment Failed

If role assignment fails (e.g., invalid role name):

```
[2025-10-23 09:27:31] [Warning] Failed to add user 'AppUser' to role 'invalid_role': Cannot find the role 'invalid_role'.
```

The user is still created but without that specific role.

## Best Practices

1. **Create logins first**: Always create SQL Server logins before running the database creation script
2. **Principle of least privilege**: Only assign the minimum roles needed for the user's function
3. **Use Windows Authentication**: Prefer Windows Authentication over SQL Authentication when possible
4. **Document users**: Keep track of which users need access and their required permissions
5. **Test first**: Use `-WhatIf` parameter to preview what will be created:
   ```powershell
   .\Invoke-DatabaseCreation.ps1 -ConfigPath .\DatabaseConfig.psd1 -WhatIf
   ```

## Troubleshooting

### Issue: "Login does not exist"
- Verify the login exists: `Get-DbaLogin -SqlInstance SERVER -Login LoginName`
- Create the login before running the script

### Issue: "Permission denied"
- Ensure you have `ALTER ANY USER` permission on the database
- Ensure you have `ALTER ANY ROLE` permission for role assignments

### Issue: User created but roles not assigned
- Check that the role names are spelled correctly
- Verify you have permission to assign users to roles
- Review the log file for detailed error messages

## Additional Resources

- [SQL Server Database Roles](https://docs.microsoft.com/en-us/sql/relational-databases/security/authentication-access/database-level-roles)
- [dbatools New-DbaDbUser](https://docs.dbatools.io/#New-DbaDbUser)
- [dbatools Add-DbaDbRoleMember](https://docs.dbatools.io/#Add-DbaDbRoleMember)
