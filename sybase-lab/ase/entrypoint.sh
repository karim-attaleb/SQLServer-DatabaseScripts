#!/bin/bash
# Sybase ASE Container Entrypoint Script
#
# This script:
# 1. Configures the ASE server on first run
# 2. Starts the ASE server
# 3. Keeps the container running

set -e

# Source Sybase environment
source /opt/sybase/SYBASE.sh 2>/dev/null || true

# Configuration
ASE_SERVER_NAME=${ASE_SERVER_NAME:-SYBASE}
ASE_SA_PASSWORD=${ASE_SA_PASSWORD:-SybaseP@ss123}
SYBASE=${SYBASE:-/opt/sybase}
DATA_DIR=${SYBASE}/data
LOG_DIR=${SYBASE}/logs

echo "=========================================="
echo "Sybase ASE Container Starting"
echo "Server Name: ${ASE_SERVER_NAME}"
echo "=========================================="

# Create directories if they don't exist
mkdir -p ${DATA_DIR} ${LOG_DIR}

# Function to check if server is already configured
is_configured() {
    [ -f "${DATA_DIR}/master.dat" ] && [ -f "${SYBASE}/interfaces" ]
}

# Function to configure the server
configure_server() {
    echo "Configuring ASE server ${ASE_SERVER_NAME}..."
    
    # Generate resource file from template
    if [ -f /opt/tmp/sybase-ase.rs.template ]; then
        sed -e "s/\${ASE_SERVER_NAME}/${ASE_SERVER_NAME}/g" \
            -e "s/\${ASE_SA_PASSWORD}/${ASE_SA_PASSWORD}/g" \
            /opt/tmp/sybase-ase.rs.template > ${SYBASE}/${SYBASE_ASE}/sybase-ase.rs
    fi
    
    # Generate interfaces file from template
    if [ -f /opt/tmp/interfaces.template ]; then
        sed -e "s/\${ASE_SERVER_NAME}/${ASE_SERVER_NAME}/g" \
            /opt/tmp/interfaces.template > ${SYBASE}/interfaces
    fi
    
    # Build the server using srvbuildres
    echo "Building ASE server..."
    ${SYBASE}/${SYBASE_ASE}/bin/srvbuildres -r ${SYBASE}/${SYBASE_ASE}/sybase-ase.rs
    
    if [ $? -eq 0 ]; then
        echo "ASE server configured successfully"
    else
        echo "ERROR: Failed to configure ASE server"
        exit 1
    fi
}

# Function to start the server
start_server() {
    echo "Starting ASE server ${ASE_SERVER_NAME}..."
    
    # Start the ASE server
    ${SYBASE}/${SYBASE_ASE}/bin/startserver \
        -f ${SYBASE}/${SYBASE_ASE}/install/RUN_${ASE_SERVER_NAME} &
    
    # Wait for server to start
    echo "Waiting for ASE server to start..."
    sleep 10
    
    # Check if server is running
    for i in {1..30}; do
        if ${SYBASE}/${SYBASE_OCS}/bin/isql -U sa -P ${ASE_SA_PASSWORD} -S ${ASE_SERVER_NAME} -b <<< "SELECT 1" > /dev/null 2>&1; then
            echo "ASE server ${ASE_SERVER_NAME} is running"
            break
        fi
        echo "Waiting for server... (attempt $i/30)"
        sleep 5
    done
    
    # Start the Backup Server if configured
    if [ -f ${SYBASE}/${SYBASE_ASE}/install/RUN_${ASE_SERVER_NAME}_BS ]; then
        echo "Starting Backup Server ${ASE_SERVER_NAME}_BS..."
        ${SYBASE}/${SYBASE_ASE}/bin/startserver \
            -f ${SYBASE}/${SYBASE_ASE}/install/RUN_${ASE_SERVER_NAME}_BS &
    fi
}

# Function to run post-configuration scripts
post_configure() {
    echo "Running post-configuration..."
    
    # Enable monitoring
    ${SYBASE}/${SYBASE_OCS}/bin/isql -U sa -P ${ASE_SA_PASSWORD} -S ${ASE_SERVER_NAME} -b << EOF
sp_configure 'enable monitoring', 1
go
sp_configure 'sql server clock tick length', 100000
go
sp_configure 'max online engines', 2
go
EOF
    
    echo "Post-configuration complete"
}

# Main execution
if is_configured; then
    echo "Server already configured, starting..."
    start_server
else
    echo "First run - configuring server..."
    configure_server
    start_server
    post_configure
fi

# Keep container running and tail the log
echo "ASE server is running. Tailing error log..."
tail -f ${LOG_DIR}/${ASE_SERVER_NAME}.log 2>/dev/null || \
tail -f ${SYBASE}/${SYBASE_ASE}/install/${ASE_SERVER_NAME}.log 2>/dev/null || \
while true; do sleep 3600; done
