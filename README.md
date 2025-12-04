# SQL Server Database Creation Scripts

A PowerShell-based automation tool for creating and configuring SQL Server databases with automatic login/user provisioning and role-based security.

---

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Files in This Repository](#files-in-this-repository)
4. [How It Works (4-Step Idempotent Workflow)](#how-it-works-4-step-idempotent-workflow)
   - [Step 1: Create Database](#step-1-create-database)
   - [Step 2: Create Logins and Users](#step-2-create-logins-and-users)
   - [Step 3: Create db_executor Role](#step-3-create-db_executor-role)
   - [Step 4: Setup Security](#step-4-setup-security)
5. [Parameters](#parameters)
6. [Configuration File](#configuration-file)
   - [File Size Calculation](#file-size-calculation)
7. [Logins, Users and Roles](#logins-users-and-roles)
   - [Login Naming Convention](#login-naming-convention)
   - [Example: DEV with Datagroup "MSS"](#example-dev-with-datagroup-mss)
   - [Important: AD Groups Must Exist](#important-ad-groups-must-exist)
8. [Usage Examples](#usage-examples)
   - [Basic Usage (DEV Environment)](#basic-usage-dev-environment)
   - [Preview Mode (WhatIf)](#preview-mode-whatif)
   - [Verbose Output](#verbose-output)
   - [Production Environment](#production-environment)
9. [Idempotency and Reruns](#idempotency-and-reruns)
10. [Installation](#installation)
11. [Testing](#testing)
12. [Troubleshooting](#troubleshooting)
13. [Contributing](#contributing)
14. [License](#license)
15. [Author](#author)
16. [Links](#links)

---

## Overview

This script automates the creation of SQL Server databases with:

- Automatic calculation of optimal number of data files based on expected database size
- Automatic derivation of data and log paths from SQL Server instance defaults
- Windows login and database user creation based on environment (Pillar) and data group
- Custom `db_executor` role with EXECUTE permission
- Role-based security model with appropriate permissions per user type
- Query Store enablement for SQL Server 2016+
- Comprehensive logging with optional Windows Event Log integration
- Idempotent design: safe to run multiple times without errors

## Prerequisites

- **PowerShell**: Version 5.1 or higher
- **dbatools Module**: PowerShell module for SQL Server administration
- **SQL Server**: Access to a SQL Server instance (2016 or higher recommended for Query Store)
- **Permissions**: CREATE DATABASE, ALTER ANY LOGIN, and database-level permissions
- **Active Directory**: The Windows groups (logins) must already exist in AD before running the script
- **Domain-joined SQL Server**: The script creates Windows logins that require domain connectivity

## Files in This Repository

| File | Description |
|------|-------------|
| `SQLDatabaseCreation/pod_sql_invoke-databasecreation.ps1` | Main script - run this to create databases |
| `SQLDatabaseCreation/pod_sql_databaseutils.psm1` | Helper functions (disk space check, logging, etc.) |
| `SQLDatabaseCreation/pod_sql_databaseconfig.psd1` | Configuration file for file sizes and logging options |

## How It Works (4-Step Idempotent Workflow)

The script executes four steps in sequence. Each step exits immediately on failure, and all steps are idempotent (safe to rerun).

### Step 1: Create Database

1. Connect to the SQL Server instance
2. Exit early if the database already exists
3. Derive data and log paths from instance default paths
4. Calculate optimal number of data files based on ExpectedDatabaseSize and FileSizeThreshold
5. Validate sufficient disk space on data and log drives (exit if insufficient)
6. Create necessary directories
7. Create database with all data files in PRIMARY filegroup
8. Set database owner to 'sa'
9. Enable Query Store (SQL Server 2016+)

### Step 2: Create Logins and Users

Based on the `Pillar` and `Datagroup` parameters, the script creates Windows logins and maps them as database users. The login names follow a fixed naming convention (see "Logins, Users and Roles" section below). This step is idempotent: existing logins and users are detected and reused.

### Step 3: Create db_executor Role

Creates a custom database role named `db_executor` and grants it EXECUTE permission. This role allows users to execute stored procedures and functions without granting broader permissions.

### Step 4: Setup Security

Assigns database roles to users based on their type:

| User Type | Roles Assigned |
|-----------|----------------|
| `*_DEV_RW` (DEV pillar only) | db_owner |
| `*_RO` users | db_datareader |
| `*_RW` users (FNC_RW, PRS_RW) | db_datareader, db_datawriter, db_executor |

## Parameters

The script accepts the following parameters:

| Parameter | Required | Description | Example |
|-----------|----------|-------------|---------|
| `SqlInstance` | Yes | SQL Server instance (server name or server,port) | `"SQLSERVER01"` or `"SQLSERVER01,1433"` |
| `Database_Name` | Yes | Name of the database to create | `"DB_MSS0_DEMO"` |
| `ExpectedDatabaseSize` | Yes | Expected total size (MB, GB, or TB) | `"50GB"` |
| `Pillar` | Yes | Environment: DEV, ACC, or PROD | `"DEV"` |
| `Datagroup` | Yes | Data group identifier (used in login names) | `"MSS"` |
| `Collation` | No | Database collation (default: Latin1_General_CI_AS) | `"SQL_Latin1_General_CP1_CI_AS"` |

Common PowerShell switches are also supported: `-WhatIf` (preview without changes) and `-Verbose` (detailed output).

## Configuration File

The script automatically loads configuration from `pod_sql_databaseconfig.psd1` in the same directory. The script will exit early if this file is missing or invalid.

The configuration file controls file sizes and logging options only. Database identity and server connection are passed as script parameters.

```powershell
@{
    FileSizes = @{
        DataGrowth        = "512MB"    # Growth increment for data files
        LogSize           = "1024MB"   # Initial size for log file
        LogGrowth         = "512MB"    # Growth increment for log file
        FileSizeThreshold = "500MB"    # Max size per data file (used to calculate file count)
    }

    EnableEventLog = $true             # Write events to Windows Application Event Log
    EventLogSource = "SQLDatabaseScripts"
}
```

### File Size Calculation

The script automatically calculates the optimal number of data files:

- If `ExpectedDatabaseSize > FileSizeThreshold`: Number of files = Ceiling(ExpectedDatabaseSize / FileSizeThreshold)
- Otherwise: 1 file
- Maximum: 8 files (SQL Server best practice)
- All files are created in the PRIMARY filegroup

## Logins, Users and Roles

### Login Naming Convention

Login names are automatically generated based on `Pillar` and `Datagroup`:

**DEV Environment:**
- Domain prefix: `TDA001\`
- Login prefix: `1005_GS_`
- Logins created:
  - `TDA001\1005_GS_{Datagroup}0_DEV_RW` (gets db_owner)
  - `TDA001\1005_GS_{Datagroup}0_FNC_RW` (gets db_datareader, db_datawriter, db_executor)
  - `TDA001\1005_GS_{Datagroup}0_PRS_RO` (gets db_datareader)
  - `TDA001\1005_GS_{Datagroup}0_PRS_RW` (gets db_datareader, db_datawriter, db_executor)

**ACC Environment:**
- Domain prefix: `TDA001\`
- Login prefix: `0005_GS_`
- Logins created:
  - `TDA001\0005_GS_{Datagroup}0_FNC_RW`
  - `TDA001\0005_GS_{Datagroup}0_PRS_RO`
  - `TDA001\0005_GS_{Datagroup}0_PRS_RW`

**PROD Environment:**
- Domain prefix: `GLOW001\`
- Login prefix: `0005_GS_`
- Logins created:
  - `GLOW001\0005_GS_{Datagroup}0_FNC_RW`
  - `GLOW001\0005_GS_{Datagroup}0_PRS_RO`
  - `GLOW001\0005_GS_{Datagroup}0_PRS_RW`

### Example: DEV with Datagroup "MSS"

Running with `-Pillar DEV -Datagroup MSS` creates:

| Login | Database User | Roles |
|-------|---------------|-------|
| `TDA001\1005_GS_MSS0_DEV_RW` | Same | db_owner |
| `TDA001\1005_GS_MSS0_FNC_RW` | Same | db_datareader, db_datawriter, db_executor |
| `TDA001\1005_GS_MSS0_PRS_RO` | Same | db_datareader |
| `TDA001\1005_GS_MSS0_PRS_RW` | Same | db_datareader, db_datawriter, db_executor |

### Important: AD Groups Must Exist

The script creates SQL Server logins mapped to Windows groups. These AD groups must already exist before running the script. If a group does not exist, the login creation step will fail.

## Usage Examples

### Basic Usage (DEV Environment)

```powershell
.\SQLDatabaseCreation\pod_sql_invoke-databasecreation.ps1 `
    -SqlInstance "SQLSERVER01" `
    -Database_Name "DB_MSS0_DEMO" `
    -ExpectedDatabaseSize "50GB" `
    -Pillar "DEV" `
    -Datagroup "MSS"
```

This creates:
- Database `DB_MSS0_DEMO` with multiple data files (50GB / 500MB threshold = ~100 files, capped at 8)
- 4 Windows logins with `TDA001\1005_GS_MSS0_*` naming
- Database users mapped to those logins
- `db_executor` role with EXECUTE permission
- Role assignments per user type

### Preview Mode (WhatIf)

```powershell
.\SQLDatabaseCreation\pod_sql_invoke-databasecreation.ps1 `
    -SqlInstance "SQLSERVER01" `
    -Database_Name "DB_MSS0_DEMO" `
    -ExpectedDatabaseSize "50GB" `
    -Pillar "DEV" `
    -Datagroup "MSS" `
    -WhatIf
```

Shows what would be created without making any changes.

### Verbose Output

```powershell
.\SQLDatabaseCreation\pod_sql_invoke-databasecreation.ps1 `
    -SqlInstance "SQLSERVER01" `
    -Database_Name "DB_MSS0_DEMO" `
    -ExpectedDatabaseSize "50GB" `
    -Pillar "ACC" `
    -Datagroup "FIN" `
    -Verbose
```

### Production Environment

```powershell
.\SQLDatabaseCreation\pod_sql_invoke-databasecreation.ps1 `
    -SqlInstance "PRODSQL01" `
    -Database_Name "DB_FIN0_PROD" `
    -ExpectedDatabaseSize "100GB" `
    -Pillar "PROD" `
    -Datagroup "FIN" `
    -Collation "SQL_Latin1_General_CP1_CI_AS"
```

Note: PROD uses `GLOW001\` domain prefix instead of `TDA001\`.

## Idempotency and Reruns

The script is designed to be safely rerun:

- **Database exists**: Step 1 logs a warning and exits early (no error)
- **Login exists**: Step 2 detects and reuses existing logins
- **User exists**: Step 2 detects and reuses existing database users
- **Role exists**: Step 3 detects and reuses existing db_executor role
- **Role membership exists**: Step 4 checks before adding users to roles

This means you can run the script again after a partial failure or to verify the configuration.

## Installation

### 1. Install dbatools Module

```powershell
Install-Module -Name dbatools -Scope CurrentUser -Force -AllowClobber
```

### 2. Clone or Download Repository

```powershell
git clone https://github.com/karim-attaleb/SQLServer-DatabaseScripts.git
cd SQLServer-DatabaseScripts
```

### 3. Configure File Sizes (Optional)

Edit `SQLDatabaseCreation/pod_sql_databaseconfig.psd1` to adjust file sizes and logging options for your environment.

## Testing

The repository includes Pester tests for the utility functions.

```powershell
# Install Pester if not already installed
Install-Module -Name Pester -Force -SkipPublisherCheck

# Run tests
Invoke-Pester -Path .\Tests\ -Output Detailed
```

## Troubleshooting

### Configuration file not found

**Error**: `Configuration file not found at: ...\pod_sql_databaseconfig.psd1`

**Solution**: Ensure `pod_sql_databaseconfig.psd1` exists in the same directory as `pod_sql_invoke-databasecreation.ps1`.

### Cannot connect to SQL Server

**Solution**: Verify that:
- SQL Server service is running
- SQL Server instance name is correct (use `server,port` format if needed)
- You have network connectivity to the server
- Windows Firewall allows SQL Server connections

### Login creation fails / AD group does not exist

**Error**: `New-DbaLogin` fails with "Cannot find Windows NT group/user"

**Solution**: The AD group must exist before running the script. Verify with:
```powershell
Get-ADGroup -Identity "1005_GS_MSS0_DEV_RW"
```

### Access denied or permission errors

**Solution**: Ensure your Windows account has:
- `CREATE DATABASE` permission on the SQL Server instance
- `ALTER ANY LOGIN` permission for creating logins
- Write permissions on the data and log drive directories

### Insufficient disk space

**Error**: `Disk space validation failed. Exiting early.`

**Solution**: Free up space on the data or log drives, or reduce the `ExpectedDatabaseSize` parameter.

### Database already exists

**Behavior**: The script logs a warning and exits early. This is expected behavior for idempotency.

**To recreate**: Manually drop the existing database first, then run the script again.

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
