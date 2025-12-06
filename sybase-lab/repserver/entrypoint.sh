#!/bin/bash
# Sybase Replication Server Container Entrypoint Script
#
# This script:
# 1. Configures the Replication Server on first run
# 2. Starts the Replication Server
# 3. Keeps the container running

set -e

# Source Sybase environment
source /opt/sybase/SYBASE.sh 2>/dev/null || true

# Configuration
RS_SERVER_NAME=${RS_SERVER_NAME:-REPSERVER}
RS_SA_PASSWORD=${RS_SA_PASSWORD:-RepServerP@ss123}
ASE_SA_PASSWORD=${ASE_SA_PASSWORD:-SybaseP@ss123}
PRIMARY_ASE_HOST=${PRIMARY_ASE_HOST:-sybase-primary}
PRIMARY_ASE_PORT=${PRIMARY_ASE_PORT:-5000}
SECONDARY_ASE_HOST=${SECONDARY_ASE_HOST:-sybase-secondary}
SECONDARY_ASE_PORT=${SECONDARY_ASE_PORT:-5000}
SYBASE=${SYBASE:-/opt/sybase}
DATA_DIR=${SYBASE}/data
LOG_DIR=${SYBASE}/logs

echo "=========================================="
echo "Sybase Replication Server Container Starting"
echo "Server Name: ${RS_SERVER_NAME}"
echo "Primary ASE: ${PRIMARY_ASE_HOST}:${PRIMARY_ASE_PORT}"
echo "Secondary ASE: ${SECONDARY_ASE_HOST}:${SECONDARY_ASE_PORT}"
echo "=========================================="

# Create directories if they don't exist
mkdir -p ${DATA_DIR} ${LOG_DIR}

# Function to check if server is already configured
is_configured() {
    [ -f "${DATA_DIR}/stable_queue.dat" ] && [ -f "${SYBASE}/interfaces" ]
}

# Function to wait for ASE servers to be available
wait_for_ase() {
    local host=$1
    local port=$2
    local server_name=$3
    
    echo "Waiting for ASE server ${server_name} at ${host}:${port}..."
    
    for i in {1..60}; do
        if nc -z ${host} ${port} 2>/dev/null; then
            echo "ASE server ${server_name} is available"
            return 0
        fi
        echo "Waiting for ${server_name}... (attempt $i/60)"
        sleep 5
    done
    
    echo "ERROR: ASE server ${server_name} not available after 5 minutes"
    return 1
}

# Function to configure the Replication Server
configure_server() {
    echo "Configuring Replication Server ${RS_SERVER_NAME}..."
    
    # Wait for ASE servers
    wait_for_ase ${PRIMARY_ASE_HOST} ${PRIMARY_ASE_PORT} "SYBASE_PRIMARY"
    wait_for_ase ${SECONDARY_ASE_HOST} ${SECONDARY_ASE_PORT} "SYBASE_SECONDARY"
    
    # Generate interfaces file from template
    if [ -f /opt/tmp/interfaces.template ]; then
        sed -e "s/\${RS_SERVER_NAME}/${RS_SERVER_NAME}/g" \
            -e "s/sybase-primary/${PRIMARY_ASE_HOST}/g" \
            -e "s/sybase-secondary/${SECONDARY_ASE_HOST}/g" \
            /opt/tmp/interfaces.template > ${SYBASE}/interfaces
    fi
    
    # Generate resource file from template
    if [ -f /opt/tmp/rs-config.rs.template ]; then
        sed -e "s/\${RS_SERVER_NAME}/${RS_SERVER_NAME}/g" \
            -e "s/\${RS_SA_PASSWORD}/${RS_SA_PASSWORD}/g" \
            -e "s/\${ASE_SA_PASSWORD}/${ASE_SA_PASSWORD}/g" \
            /opt/tmp/rs-config.rs.template > ${SYBASE}/rs-config.rs
    fi
    
    # Create RSSD database on primary ASE
    echo "Creating RSSD database on primary ASE..."
    ${SYBASE}/${SYBASE_OCS}/bin/isql -U sa -P ${ASE_SA_PASSWORD} -S SYBASE_PRIMARY -b << EOF
-- Create device for RSSD
disk init name = 'rssd_data',
    physname = '/opt/sybase/data/rssd_data.dat',
    size = '100M'
go

disk init name = 'rssd_log',
    physname = '/opt/sybase/data/rssd_log.dat',
    size = '50M'
go

-- Create RSSD database
create database ${RS_SERVER_NAME}_RSSD on rssd_data = 80
log on rssd_log = 40
go

-- Set database options
sp_dboption ${RS_SERVER_NAME}_RSSD, 'trunc log on chkpt', true
go
EOF
    
    # Initialize Replication Server using rs_init
    echo "Initializing Replication Server..."
    ${SYBASE}/${SYBASE_REP}/bin/rs_init -r ${SYBASE}/rs-config.rs
    
    if [ $? -eq 0 ]; then
        echo "Replication Server configured successfully"
    else
        echo "WARNING: rs_init may have encountered issues"
    fi
}

# Function to start the Replication Server
start_server() {
    echo "Starting Replication Server ${RS_SERVER_NAME}..."
    
    # Start the Replication Server
    ${SYBASE}/${SYBASE_REP}/bin/repserver \
        -S${RS_SERVER_NAME} \
        -I${SYBASE}/interfaces \
        -E${LOG_DIR}/${RS_SERVER_NAME}.log &
    
    # Wait for server to start
    echo "Waiting for Replication Server to start..."
    sleep 15
    
    # Check if server is running
    for i in {1..30}; do
        if ${SYBASE}/${SYBASE_OCS}/bin/isql -U sa -P ${RS_SA_PASSWORD} -S ${RS_SERVER_NAME} -b <<< "admin who" > /dev/null 2>&1; then
            echo "Replication Server ${RS_SERVER_NAME} is running"
            break
        fi
        echo "Waiting for server... (attempt $i/30)"
        sleep 5
    done
}

# Function to configure replication connections
configure_replication() {
    echo "Configuring replication connections..."
    
    # Create connection to primary ASE
    ${SYBASE}/${SYBASE_OCS}/bin/isql -U sa -P ${RS_SA_PASSWORD} -S ${RS_SERVER_NAME} -b << EOF
-- Create connection to primary ASE
create connection to SYBASE_PRIMARY.pubs2
set error class rs_sqlserver_error_class
set function string class rs_sqlserver_function_class
set username sa
set password ${ASE_SA_PASSWORD}
go

-- Create connection to secondary ASE
create connection to SYBASE_SECONDARY.pubs2
set error class rs_sqlserver_error_class
set function string class rs_sqlserver_function_class
set username sa
set password ${ASE_SA_PASSWORD}
go
EOF
    
    echo "Replication connections configured"
}

# Main execution
if is_configured; then
    echo "Server already configured, starting..."
    start_server
else
    echo "First run - configuring server..."
    configure_server
    start_server
    # Give server time to fully initialize before configuring replication
    sleep 30
    configure_replication
fi

# Keep container running and tail the log
echo "Replication Server is running. Tailing error log..."
tail -f ${LOG_DIR}/${RS_SERVER_NAME}.log 2>/dev/null || \
while true; do sleep 3600; done
