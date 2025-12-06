# Sybase ASE and Replication Server Lab Environment

This directory contains Docker configurations for setting up a Sybase lab environment with:
- 2 Sybase ASE (Adaptive Server Enterprise) containers
- 1 Sybase Replication Server container

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Docker Network (sybase-net)                   │
│                          172.28.0.0/16                               │
│                                                                      │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐  │
│  │  ASE Primary    │    │  Replication    │    │  ASE Secondary  │  │
│  │  SYBASE_PRIMARY │◄──►│  Server         │◄──►│  SYBASE_SECONDARY│  │
│  │  172.28.0.10    │    │  REPSERVER      │    │  172.28.0.11    │  │
│  │  Port: 5000     │    │  172.28.0.12    │    │  Port: 5002     │  │
│  └─────────────────┘    │  Port: 5100     │    └─────────────────┘  │
│                         └─────────────────┘                          │
└─────────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. Download SAP ASE Developer Edition

Download SAP ASE 16.0 Developer Edition from SAP:
- Direct link: http://d1cuw2q49dpd0p.cloudfront.net/ASE16.0/Linux16SP02/ASE_Suite.linuxamd64.tgz
- Or from SAP downloads: https://go.sap.com/cmp/syb/crm-xu15-int-asewindm/typ.html

Place the downloaded file in the `ase/` directory:
```bash
cp ASE_Suite.linuxamd64.tgz sybase-lab/ase/
```

### 2. Download SAP Replication Server (Optional)

If you want to use Replication Server, download it from SAP and place it in the `repserver/` directory.

Note: Replication Server requires a separate license. For testing purposes, you can use ASE's built-in replication features or skip the Replication Server container.

### 3. Docker and Docker Compose

Ensure Docker and Docker Compose are installed:
```bash
docker --version
docker-compose --version
```

## Quick Start

### 1. Build the Images

```bash
cd sybase-lab
docker-compose build
```

### 2. Start the Environment

```bash
docker-compose up -d
```

### 3. Check Status

```bash
docker-compose ps
docker-compose logs -f
```

### 4. Connect to ASE

Using isql from the container:
```bash
docker exec -it sybase-primary /opt/sybase/OCS-16_0/bin/isql -U sa -P SybaseP@ss123 -S SYBASE_PRIMARY
```

Or from your host (if you have isql installed):
```bash
isql -U sa -P SybaseP@ss123 -S SYBASE_PRIMARY -H localhost -p 5000
```

## Port Mappings

| Service | Container Port | Host Port | Description |
|---------|---------------|-----------|-------------|
| ASE Primary | 5000 | 5000 | ASE Server |
| ASE Primary | 5001 | 5001 | Backup Server |
| ASE Secondary | 5000 | 5002 | ASE Server |
| ASE Secondary | 5001 | 5003 | Backup Server |
| Replication Server | 5100 | 5100 | RepServer |

## Environment Variables

### ASE Containers

| Variable | Default | Description |
|----------|---------|-------------|
| ASE_SERVER_NAME | SYBASE_PRIMARY/SECONDARY | Server name |
| ASE_SA_PASSWORD | SybaseP@ss123 | SA password |

### Replication Server Container

| Variable | Default | Description |
|----------|---------|-------------|
| RS_SERVER_NAME | REPSERVER | Replication Server name |
| RS_SA_PASSWORD | RepServerP@ss123 | RS SA password |
| PRIMARY_ASE_HOST | sybase-primary | Primary ASE hostname |
| SECONDARY_ASE_HOST | sybase-secondary | Secondary ASE hostname |

## Customization

### Change Passwords

Create a `.env` file in the `sybase-lab` directory:
```bash
ASE_SA_PASSWORD=YourSecurePassword123!
RS_SA_PASSWORD=YourRSPassword123!
```

### Modify Server Configuration

Edit the resource file templates:
- `ase/sybase-ase.rs.template` - ASE server configuration
- `repserver/rs-config.rs.template` - Replication Server configuration

## Data Persistence

Data is stored in Docker volumes:
- `ase-primary-data` - Primary ASE data files
- `ase-primary-logs` - Primary ASE logs
- `ase-secondary-data` - Secondary ASE data files
- `ase-secondary-logs` - Secondary ASE logs
- `repserver-data` - Replication Server data
- `repserver-logs` - Replication Server logs

To remove all data and start fresh:
```bash
docker-compose down -v
```

## Troubleshooting

### Container Won't Start

Check the logs:
```bash
docker-compose logs ase-primary
docker-compose logs ase-secondary
docker-compose logs repserver
```

### Connection Refused

1. Ensure the container is running: `docker-compose ps`
2. Check if the server is listening: `docker exec sybase-primary netstat -tlnp`
3. Verify the interfaces file: `docker exec sybase-primary cat /opt/sybase/interfaces`

### Memory Issues

ASE requires significant memory. Ensure Docker has at least 4GB RAM allocated.

Edit Docker Desktop settings or for Linux:
```bash
# Check available memory
free -h

# Increase Docker memory limit if needed
```

## Setting Up Replication

Once all containers are running, you can set up replication between the ASE instances.

### 1. Create a Test Database on Primary

```sql
-- Connect to SYBASE_PRIMARY
create database testdb on default = 100
go
use testdb
go
create table orders (
    order_id int identity primary key,
    customer_name varchar(100),
    order_date datetime default getdate()
)
go
```

### 2. Enable RepAgent on Primary

```sql
-- Enable RepAgent for the database
sp_config_rep_agent testdb, 'enable', 'REPSERVER', 'testdb_prim'
go
sp_start_rep_agent testdb
go
```

### 3. Create Replication Definition

```sql
-- Connect to REPSERVER
create replication definition orders_rep
with primary at SYBASE_PRIMARY.testdb
with all tables named 'orders'
(order_id, customer_name, order_date)
primary key (order_id)
go
```

### 4. Create Subscription

```sql
-- Create subscription on secondary
create subscription orders_sub
for orders_rep
with replicate at SYBASE_SECONDARY.testdb
without materialization
go
```

## Directory Structure

```
sybase-lab/
├── docker-compose.yml      # Main compose file
├── README.md               # This file
├── ase/                    # ASE container files
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── interfaces.template
│   ├── sybase-ase.rs.template
│   ├── sybase-response.txt
│   └── sysctl.conf
├── repserver/              # Replication Server files
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── interfaces.template
│   ├── rs-config.rs.template
│   ├── rs-response.txt
│   └── sysctl.conf
└── scripts/                # Shared scripts
    ├── healthcheck.sh
    └── rs_healthcheck.sh
```

## License

SAP ASE Developer Edition is free for development and testing purposes. Production use requires a commercial license from SAP.

## References

- [SAP ASE Documentation](https://help.sap.com/docs/SAP_ASE)
- [SAP Replication Server Documentation](https://help.sap.com/docs/SAP_REPLICATION_SERVER)
- [Sybase Infocenter](https://infocenter.sybase.com)
