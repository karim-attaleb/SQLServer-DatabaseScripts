# Sybase ASE & Replication Server - Senior DBA Knowledge Guide

## Executive Summary

This document provides comprehensive knowledge for Sybase Adaptive Server Enterprise (ASE) and Replication Server administration, with a focus on migration to SQL Server. SAP Sybase ASE (formerly Sybase SQL Server) is an enterprise-class relational database management system that shares historical roots with Microsoft SQL Server but has diverged significantly in architecture and features.

---

## Part 1: Sybase ASE Architecture

### 1.1 System Databases

Sybase ASE maintains several critical system databases:

| Database | Purpose |
|----------|---------|
| **master** | Contains server-wide system tables, logins, configuration settings, and references to all user databases |
| **model** | Template database used when creating new databases |
| **tempdb** | Temporary storage for worktables, temporary tables, and intermediate query results |
| **sybsystemprocs** | Contains system stored procedures |
| **sybsystemdb** | Coordinates distributed transactions (two-phase commit) |
| **sybsecurity** | Audit trail storage (if auditing enabled) |

### 1.2 Storage Architecture: Devices and Segments

**This is a KEY architectural difference from SQL Server.**

#### Devices
- **Definition**: Raw disk partitions or operating system files that provide physical storage
- **Creation**: `disk init` command creates devices
- **Types**: 
  - Database devices (for data and logs)
  - Dump devices (for backups)
- **Management**: `sp_helpdevice` shows device information

```sql
-- Create a device
disk init 
    name = 'data_dev1',
    physname = '/sybase/data/data_dev1.dat',
    size = '500M'

-- View devices
sp_helpdevice
```

#### Segments
- **Definition**: Named collections of disk pieces (portions of devices) used to control object placement
- **Purpose**: Performance optimization, administrative control, and space management
- **Default Segments**: 
  - `system` - System tables
  - `default` - User objects without explicit segment
  - `logsegment` - Transaction log

```sql
-- View segments in a database
sp_helpsegment

-- Create a segment
sp_addsegment 'fast_segment', 'mydb', 'fast_device'

-- Place a table on a specific segment
CREATE TABLE orders (
    order_id int,
    order_date datetime
) ON fast_segment
```

#### Storage Hierarchy
```
Server
└── Devices (physical storage)
    └── Databases (logical containers)
        └── Segments (object placement groups)
            └── Tables, Indexes, Logs
```

### 1.3 Memory Architecture

ASE uses a sophisticated memory management system:

#### Data Cache
- Caches data and index pages
- Can be divided into named caches for specific objects
- Uses LRU (Least Recently Used) algorithm

#### Procedure Cache
- Stores compiled query plans
- Shared across connections

#### Statement Cache
- Caches ad-hoc SQL statements
- Reduces compilation overhead

```sql
-- View cache configuration
sp_cacheconfig

-- Create a named cache
sp_cacheconfig 'order_cache', '100M'

-- Bind a table to a cache
sp_bindcache 'order_cache', 'mydb.dbo.orders'
```

### 1.4 Locking and Concurrency

ASE supports multiple locking schemes:

#### All-Pages Locking (APL)
- Traditional Sybase locking
- Locks entire data pages
- Lower overhead but more contention
- Default for tables created before ASE 11.9

#### Data-Only Locking (DOL)
- Row-level locking capability
- Two sub-types:
  - **Datarows**: Row-level locks on data pages
  - **Datapages**: Page-level locks but only on data pages (not index)

```sql
-- Create table with datarows locking
CREATE TABLE orders (
    order_id int,
    order_date datetime
) LOCK DATAROWS

-- Change locking scheme
ALTER TABLE orders LOCK DATAROWS

-- Check locking scheme
sp_help orders
```

### 1.5 Transaction Log Management

The transaction log in ASE is stored in the `syslogs` system table:

#### Key Characteristics
- Can reside on same device as data or separate device (recommended)
- Truncated via `dump transaction` or `dump transaction with truncate_only`
- Threshold procedures can automate log management

```sql
-- Check log space
dbcc checktable(syslogs)

-- Dump transaction log
dump transaction mydb to '/backup/mydb_log.dmp'

-- Truncate log (no backup)
dump transaction mydb with truncate_only

-- Set threshold for automatic action
sp_addthreshold mydb, logsegment, 500, sp_thresholdaction
```

### 1.6 Key System Stored Procedures

| Procedure | Purpose |
|-----------|---------|
| `sp_helpdb` | Database information |
| `sp_helpdevice` | Device information |
| `sp_helpsegment` | Segment information |
| `sp_spaceused` | Space usage statistics |
| `sp_who` | Active processes |
| `sp_lock` | Current locks |
| `sp_sysmon` | Performance monitoring |
| `sp_configure` | Server configuration |
| `sp_helpindex` | Index information |
| `sp_help` | Object information |

### 1.7 Performance Monitoring

#### sp_sysmon
The primary performance monitoring tool:

```sql
-- Start monitoring
sp_sysmon '00:05:00'  -- 5 minute sample

-- Key sections to analyze:
-- - Kernel Utilization
-- - Task Management
-- - Data Cache Management
-- - Procedure Cache Management
-- - Lock Management
-- - Disk I/O Management
```

#### Monitoring Tables (mon_* tables)
ASE 15.0+ includes monitoring tables:
- `monProcessActivity` - Process statistics
- `monSysStatement` - Statement statistics
- `monOpenDatabases` - Database activity
- `monDeviceIO` - Device I/O statistics

```sql
-- Enable monitoring
sp_configure 'enable monitoring', 1

-- Query process activity
SELECT * FROM master..monProcessActivity
WHERE SPID = @@spid
```

---

## Part 2: Sybase Replication Server Architecture

### 2.1 Replication Topology

```
┌─────────────────┐     ┌─────────────────────┐     ┌─────────────────┐
│  Primary Data   │     │   Replication       │     │  Replicate Data │
│  Server (PDS)   │────▶│   Server (RS)       │────▶│  Server (RDS)   │
│  (Source ASE)   │     │                     │     │  (Target)       │
└─────────────────┘     └─────────────────────┘     └─────────────────┘
        │                        │
        │                        │
   ┌────┴────┐              ┌────┴────┐
   │RepAgent │              │  RSSD   │
   │(in ASE) │              │         │
   └─────────┘              └─────────┘
```

### 2.2 Core Components

#### Primary Data Server (PDS)
- Source database server (ASE)
- Contains the primary data
- Runs RepAgent thread

#### Replication Server (RS)
- Middleware component
- Routes transactions between servers
- Manages stable queues
- Applies transactions to replicate sites

#### Replicate Data Server (RDS)
- Target database server
- Can be ASE, SQL Server, Oracle, or other DBMS
- Receives replicated transactions

#### RepAgent (Replication Agent)
- Thread running inside ASE
- Reads transaction log
- Sends transactions to Replication Server
- Configured per database

```sql
-- Enable RepAgent
sp_config_rep_agent mydb, 'enable', 'rs_name', 'rs_user', 'rs_password'

-- Start RepAgent
sp_start_rep_agent mydb

-- Check RepAgent status
sp_help_rep_agent mydb
```

#### RSSD (Replication Server System Database)
- Stores Replication Server metadata
- Contains:
  - Connection definitions
  - Replication definitions
  - Subscriptions
  - Route information
- Can be ASE or SQL Anywhere database

#### Stable Queues
- Persistent message storage
- Ensures no data loss during failures
- Types:
  - Inbound queue (from PDS)
  - Outbound queue (to RDS)

### 2.3 Replication Definitions and Subscriptions

#### Replication Definition
Defines what data to replicate:

```sql
-- Create replication definition
create replication definition orders_rep
    with primary at PDS.mydb
    with all tables named 'orders'
    (order_id int,
     customer_id int,
     order_date datetime,
     total money)
    primary key (order_id)
```

#### Subscription
Defines where to replicate:

```sql
-- Create subscription
create subscription orders_sub
    for orders_rep
    with replicate at RDS.mydb
    without materialization
```

### 2.4 Data Server Interface (DSI)

The DSI is responsible for:
- Connecting to replicate databases
- Applying transactions
- Handling errors and retries
- Managing commit control

```sql
-- Check DSI status
admin who, dsi

-- Suspend DSI
suspend connection to RDS.mydb

-- Resume DSI
resume connection to RDS.mydb
```

### 2.5 Warm Standby Configuration

Warm standby provides high availability:

```sql
-- Create logical connection
create logical connection to LOGICAL_DS.mydb

-- Configure active database
create connection to ACTIVE_DS.mydb
    set error class rs_sqlserver_error_class
    set function string class rs_sqlserver_function_class
    set username 'maint_user'
    set password 'password'
    as active for LOGICAL_DS.mydb

-- Configure standby database
create connection to STANDBY_DS.mydb
    set error class rs_sqlserver_error_class
    set function string class rs_sqlserver_function_class
    set username 'maint_user'
    set password 'password'
    as standby for LOGICAL_DS.mydb
    use dump marker
```

### 2.6 Heterogeneous Replication

Replication Server can replicate to non-Sybase databases:

#### To SQL Server
- Uses Enterprise Connect Data Access (ECDA) or
- Replication Server Options for Microsoft SQL Server
- Requires function string class mapping

```sql
-- Create connection to SQL Server
create connection to SQLSERVER.mydb
    set error class rs_msss_error_class
    set function string class rs_msss_function_class
    set username 'sa'
    set password 'password'
    with log transfer off
```

---

## Part 3: ASE Administration Tasks

### 3.1 Database Creation

```sql
-- Create database with specific devices
CREATE DATABASE mydb
    ON data_dev1 = '500M'
    LOG ON log_dev1 = '100M'

-- Extend database
ALTER DATABASE mydb ON data_dev2 = '200M'

-- Check database info
sp_helpdb mydb
```

### 3.2 Backup and Recovery

#### Full Database Backup
```sql
dump database mydb to '/backup/mydb_full.dmp'
```

#### Transaction Log Backup
```sql
dump transaction mydb to '/backup/mydb_log.dmp'
```

#### Restore Database
```sql
load database mydb from '/backup/mydb_full.dmp'
load transaction mydb from '/backup/mydb_log.dmp'
online database mydb
```

### 3.3 User and Security Management

```sql
-- Create login
sp_addlogin 'app_user', 'password', 'mydb'

-- Create database user
USE mydb
GO
sp_adduser 'app_user', 'app_user', 'public'

-- Grant permissions
GRANT SELECT, INSERT, UPDATE ON orders TO app_user

-- Create role
sp_addrole 'app_role'
sp_addrolemember 'app_role', 'app_user'
```

### 3.4 Index Management

```sql
-- Create clustered index
CREATE CLUSTERED INDEX idx_orders_date 
    ON orders(order_date)

-- Create non-clustered index
CREATE NONCLUSTERED INDEX idx_orders_customer 
    ON orders(customer_id)

-- Update statistics
UPDATE STATISTICS orders

-- Rebuild index
REORG REBUILD orders idx_orders_date
```

### 3.5 Common Troubleshooting

#### Check for Blocking
```sql
sp_who
sp_lock
```

#### Check Space Usage
```sql
sp_spaceused
sp_helpdb mydb
```

#### Check for Long-Running Transactions
```sql
SELECT * FROM master..syslogshold
```

#### DBCC Commands
```sql
-- Check database consistency
dbcc checkdb(mydb)

-- Check table consistency
dbcc checktable(orders)

-- Check allocation
dbcc checkalloc(mydb)
```

---

## Part 4: Key Differences - ASE vs SQL Server

### 4.1 Storage Model

| Aspect | Sybase ASE | SQL Server |
|--------|-----------|------------|
| Physical Storage | Devices | Files (.mdf, .ndf, .ldf) |
| Logical Grouping | Segments | Filegroups |
| Object Placement | Explicit segment assignment | Filegroup assignment |
| Log Storage | syslogs table on device | Separate .ldf file |
| Complexity | Higher (more flexible) | Lower (more straightforward) |

### 4.2 Locking Behavior

| Aspect | Sybase ASE | SQL Server |
|--------|-----------|------------|
| Default | Page-level (APL) | Row-level |
| Row Locking | DOL (datarows) option | Default behavior |
| Lock Escalation | Configurable | Automatic |
| Deadlock Detection | Configurable interval | Automatic |

### 4.3 T-SQL Syntax Differences

#### Temporary Tables
```sql
-- Sybase ASE
SELECT * INTO #temp FROM orders

-- SQL Server (same, but tempdb behavior differs)
SELECT * INTO #temp FROM orders
```

#### Outer Joins (Legacy Syntax)
```sql
-- Sybase ASE (old syntax still supported)
SELECT * FROM orders, customers
WHERE orders.customer_id *= customers.customer_id

-- SQL Server (ANSI syntax required)
SELECT * FROM orders
LEFT OUTER JOIN customers ON orders.customer_id = customers.customer_id
```

#### Identity Columns
```sql
-- Sybase ASE
CREATE TABLE orders (
    order_id numeric(10,0) identity,
    order_date datetime
)
-- Get last identity: @@identity

-- SQL Server
CREATE TABLE orders (
    order_id int IDENTITY(1,1),
    order_date datetime
)
-- Get last identity: SCOPE_IDENTITY() (preferred)
```

#### String Functions
```sql
-- Sybase ASE
SELECT substring(name, 1, 10) FROM customers
SELECT char_length(name) FROM customers

-- SQL Server
SELECT SUBSTRING(name, 1, 10) FROM customers
SELECT LEN(name) FROM customers
```

### 4.4 System Catalog

| Sybase ASE | SQL Server |
|-----------|------------|
| sysobjects | sys.objects |
| syscolumns | sys.columns |
| sysindexes | sys.indexes |
| sysusers | sys.database_principals |
| syslogins | sys.server_principals |
| sysdatabases | sys.databases |

### 4.5 Data Types

| Sybase ASE | SQL Server Equivalent | Notes |
|-----------|----------------------|-------|
| datetime | datetime | Similar but precision differs |
| smalldatetime | smalldatetime | Same |
| money | money | Same |
| smallmoney | smallmoney | Same |
| text | varchar(max) | text deprecated in SQL Server |
| image | varbinary(max) | image deprecated in SQL Server |
| unitext | nvarchar(max) | Unicode text |
| unichar | nchar | Unicode fixed-length |
| univarchar | nvarchar | Unicode variable-length |

---

## Part 5: Migration Strategy to SQL Server

### 5.1 Assessment Phase

1. **Inventory Analysis**
   - Document all databases, sizes, and dependencies
   - Identify replication topology
   - Map application connections

2. **Compatibility Analysis**
   - T-SQL syntax differences
   - Data type mappings
   - Stored procedure conversion needs
   - Trigger syntax changes

3. **Performance Baseline**
   - Capture current performance metrics
   - Document SLAs and requirements

### 5.2 Migration Tools

#### SQL Server Migration Assistant (SSMA) for Sybase
- Microsoft's official migration tool
- Handles:
  - Schema conversion
  - Data migration
  - T-SQL conversion
  - Assessment reports

#### dbatools PowerShell Module
- Community PowerShell tools
- Useful for:
  - Data transfer
  - Schema scripting
  - Post-migration validation

### 5.3 Migration Approaches

#### Big Bang Migration
- Complete cutover at once
- Shorter total migration time
- Higher risk, requires longer downtime

#### Phased Migration
- Migrate databases/applications incrementally
- Lower risk per phase
- Requires coexistence strategy

#### Parallel Running
- Run both systems simultaneously
- Highest safety but most complex
- Requires data synchronization

### 5.4 Replication-Based Migration

Using Sybase Replication Server for minimal downtime:

1. Set up heterogeneous replication ASE → SQL Server
2. Synchronize data continuously
3. Validate data consistency
4. Cut over applications
5. Reverse replication direction (optional fallback)

### 5.5 Post-Migration Validation

1. **Data Validation**
   - Row counts
   - Checksum comparisons
   - Sample data verification

2. **Functionality Testing**
   - Application testing
   - Stored procedure execution
   - Report generation

3. **Performance Testing**
   - Query performance comparison
   - Load testing
   - Stress testing

---

## Part 6: External Migration Tools

This section covers external tools beyond SSMA and dbatools that can assist with Sybase ASE to SQL Server migrations.

### 6.1 Commercial Migration Tools

#### Ispirer Toolkit (SQLWays)
**Website**: https://www.ispirer.com/products/sybase-ase-to-sql-server-migration

Ispirer Toolkit is a comprehensive commercial solution for automated heterogeneous database migration with 25+ years of experience.

**Key Features**:
- AI-powered SQLWays conversion engine
- 20,000+ conversion rules and 100,000+ automated tests
- Converts tables, data, stored procedures, functions, views, triggers
- InsightWays free assessment tool for migration complexity evaluation
- ISO 27001 certified security

**Migration Capabilities**:
- Schema conversion (DDL)
- Data migration with validation
- Server-side code conversion (procedures, triggers, functions)
- Handles Sybase-specific constructs (@@rowcount, chained transactions)
- Data type mapping (TIMESTAMP, UNIVARCHAR to DATETIME2, NVARCHAR)

**Pricing**: Project-based or time-boxed licenses; free trial available

**Case Study**: Sybase ASE to MySQL - 100% automated migration of 300,000 lines of code over 12 months

---

#### CData Sync
**Website**: https://www.cdata.com/data/integration/sybase-to-sql-server

CData provides data integration and ETL/ELT solutions with 300+ connectors.

**Key Features**:
- Near real-time data movement
- Change Data Capture (CDC) capabilities
- High-performance ETL/ELT pipelines
- Cloud and on-premises deployment options

**Use Cases**:
- Continuous data synchronization during migration
- Hybrid cloud migrations
- Real-time data replication

---

#### Fivetran
**Website**: https://www.fivetran.com

Fivetran offers automated data migration with 700+ pre-built connectors.

**Key Features**:
- Maintenance-free connectors
- Automated schema drift handling
- Incremental data loading
- Enterprise-grade security

**Best For**: Organizations needing ongoing data synchronization rather than one-time migration

---

### 6.2 Open Source Migration Tools

#### SQLines
**Website**: https://www.sqlines.com
**GitHub**: https://github.com/dmtolpeko/sqlines

SQLines is an open-source database migration toolkit (Apache License 2.0).

**Components**:

1. **SQLines SQL Converter**
   - Converts SQL scripts and standalone statements
   - Schema (DDL) conversion
   - Query and DML conversion
   - Online conversion available at sqlines.com/online

2. **SQLines Data**
   - High-performance data transfer tool
   - Schema conversion from live databases
   - Migration validation
   - Supports large volume migrations

**Supported Conversions**:
- Sybase ASE to SQL Server
- Sybase SQL Anywhere to SQL Server
- Views, stored procedures, functions, triggers

**Example Usage**:
```bash
# Convert SQL script
sqlines -s=sybase -t=sqlserver -in=script.sql -out=converted.sql

# Data migration
sqldata -s=sybase -t=sqlserver -sd="server=ASE;db=mydb" -td="server=SQLSRV;db=mydb"
```

---

#### Travinto Code Converter
**Website**: https://travinto.com/products/code-converter/sybase-to-sql-server

Automated code converter claiming 90% reduction in migration time.

**Features**:
- T-SQL dialect conversion
- Stored procedure migration
- Performance optimization suggestions

---

### 6.3 ETL and Data Integration Platforms

#### Integrate.io
**Website**: https://www.integrate.io

Cloud-native ETL platform with Sybase ASE connector.

**Capabilities**:
- Visual data pipeline designer
- Pre-built transformations
- Data quality monitoring
- Scheduling and orchestration

---

#### Talend
Enterprise data integration platform with Sybase connectivity.

**Features**:
- Open-source and commercial editions
- Visual job designer
- Data quality tools
- Big data support

---

#### Apache NiFi
Open-source data flow automation tool.

**Sybase Support**:
- JDBC connectivity to ASE
- Data routing and transformation
- Real-time and batch processing

---

### 6.4 Consulting and Migration Services

#### Adastra
**Website**: https://adastracorp.com/sybase-to-sql-migration-services

Provides end-to-end Sybase to SQL Server migration services including:
- Schema and data migration methodologies
- Replication technology setup (ASE to SQL Server and vice-versa)
- Migration accelerators and automation tools

---

#### RalanTech
**Website**: https://www.ralantech.com/resources/sap-sybase-migration

Offers migration accelerators to reduce migration time, cost, and resources.

---

#### Spinnaker Support
**Website**: https://www.spinnakersupport.com

Third-party support for Sybase ASE (especially relevant as SAP ends mainstream support).

**Services**:
- Extended support for legacy Sybase systems
- Migration planning assistance
- Hybrid support during migration periods

---

### 6.5 Tool Selection Matrix

| Tool | Type | Best For | Cost | Automation Level |
|------|------|----------|------|------------------|
| **SSMA** | Microsoft Official | Schema + Data migration | Free | High |
| **Ispirer** | Commercial | Complex migrations, code conversion | $$$$ | Very High |
| **SQLines** | Open Source | SQL conversion, data transfer | Free | Medium-High |
| **CData Sync** | Commercial | Continuous sync, CDC | $$$ | High |
| **Fivetran** | Commercial | Ongoing data pipelines | $$$ | Very High |
| **dbatools** | Open Source | PowerShell automation | Free | Medium |
| **Talend** | Commercial/OSS | Enterprise ETL | $$-$$$$ | High |

### 6.6 Recommended Tool Combinations

**For Small Migrations (< 100 objects)**:
- SSMA for schema and data
- Manual T-SQL fixes
- dbatools for validation

**For Medium Migrations (100-1000 objects)**:
- SSMA for initial assessment
- SQLines for code conversion
- dbatools for data transfer and validation

**For Large/Complex Migrations (> 1000 objects)**:
- Ispirer Toolkit for automated conversion
- CData or Fivetran for continuous sync during transition
- Professional services for complex scenarios

**For Minimal Downtime Requirements**:
- Sybase Replication Server for heterogeneous replication
- CData Sync for CDC-based synchronization
- Parallel running with data validation

---

## Part 7: Docker Containerization

### 6.1 ASE Container Requirements

Based on community Docker implementations:

- **Base Image**: CentOS 7 or Ubuntu
- **ASE Edition**: Developer Edition (free) or Express Edition
- **Download**: SAP provides direct download links
- **Installation**: Silent install with response file
- **Ports**: 5000 (default ASE port), 5001 (backup server)

### 6.2 Sample Docker Compose for Lab Environment

```yaml
version: '3.8'

services:
  ase-primary:
    build: ./ase
    container_name: sybase-primary
    hostname: sybase-primary
    ports:
      - "5000:5000"
      - "5001:5001"
    volumes:
      - ase-primary-data:/opt/sybase/data
    environment:
      - SYBASE_USER=sa
      - SYBASE_PASSWORD=MyPassword123
    networks:
      - sybase-net

  ase-secondary:
    build: ./ase
    container_name: sybase-secondary
    hostname: sybase-secondary
    ports:
      - "5002:5000"
      - "5003:5001"
    volumes:
      - ase-secondary-data:/opt/sybase/data
    environment:
      - SYBASE_USER=sa
      - SYBASE_PASSWORD=MyPassword123
    networks:
      - sybase-net

  repserver:
    build: ./repserver
    container_name: sybase-repserver
    hostname: sybase-repserver
    ports:
      - "5100:5100"
    volumes:
      - repserver-data:/opt/sybase/data
    depends_on:
      - ase-primary
      - ase-secondary
    networks:
      - sybase-net

volumes:
  ase-primary-data:
  ase-secondary-data:
  repserver-data:

networks:
  sybase-net:
    driver: bridge
```

### 6.3 Key Configuration Files

#### Response File (sybase-response.txt)
```
AGREE_TO_SAP_LICENSE=true
RUN_SILENT=true
INSTALL_LOCATION=/opt/sybase
SYBASE_PRODUCT_LICENSE_TYPE=evaluate
```

#### Resource File (sybase-ase.rs)
```
srvbuild.server_name: MYSYBASE
srvbuild.sa_password: MyPassword123
srvbuild.master_device_physical_name: /opt/sybase/data/master.dat
srvbuild.master_device_size: 100
srvbuild.master_database_size: 50
srvbuild.sybsystemprocs_device_physical_name: /opt/sybase/data/sysprocs.dat
srvbuild.sybsystemprocs_device_size: 200
srvbuild.sybsystemprocs_database_size: 200
```

---

## Appendix A: Quick Reference Commands

### ASE Server Management
```sql
-- Start/Stop server (OS level)
startserver -f /opt/sybase/ASE-16_0/install/RUN_SERVERNAME
shutdown

-- Check version
SELECT @@version

-- Check server name
SELECT @@servername
```

### Database Operations
```sql
-- List databases
sp_helpdb

-- Switch database
USE mydb

-- Check space
sp_spaceused

-- Check objects
sp_help tablename
```

### Replication Server Commands
```sql
-- Check connections
admin who

-- Check queues
admin who, sqm

-- Check latency
admin show_route_versions
```

---

## Appendix B: Resources

### Official Documentation
- SAP Help Portal: https://help.sap.com/docs/SAP_ASE
- Sybase Infocenter: https://infocenter.sybase.com

### Community Resources
- SAP Community: https://community.sap.com
- GitHub Docker Images: 
  - nguoianphu/docker-sybase
  - blieusong/sybase-ase-docker

### Migration Tools
- SQL Server Migration Assistant (SSMA): Microsoft Download Center
- dbatools: https://dbatools.io

---

*Document Version: 1.0*
*Last Updated: December 2024*
*Author: Sybase DBA Migration Team*
