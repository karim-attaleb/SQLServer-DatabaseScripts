#!/bin/bash
# Sybase ASE Health Check Script
#
# This script checks if the ASE server is running and responsive
# Used by Docker health check

# Source Sybase environment
source /opt/sybase/SYBASE.sh 2>/dev/null || true

ASE_SERVER_NAME=${ASE_SERVER_NAME:-SYBASE}
ASE_SA_PASSWORD=${ASE_SA_PASSWORD:-SybaseP@ss123}

# Try to connect and run a simple query
${SYBASE}/${SYBASE_OCS}/bin/isql -U sa -P ${ASE_SA_PASSWORD} -S ${ASE_SERVER_NAME} -b << EOF
SELECT 1
go
EOF

exit $?
