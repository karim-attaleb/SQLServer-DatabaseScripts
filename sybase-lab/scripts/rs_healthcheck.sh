#!/bin/bash
# Sybase Replication Server Health Check Script
#
# This script checks if the Replication Server is running and responsive
# Used by Docker health check

# Source Sybase environment
source /opt/sybase/SYBASE.sh 2>/dev/null || true

RS_SERVER_NAME=${RS_SERVER_NAME:-REPSERVER}
RS_SA_PASSWORD=${RS_SA_PASSWORD:-RepServerP@ss123}

# Try to connect and run admin who command
${SYBASE}/${SYBASE_OCS}/bin/isql -U sa -P ${RS_SA_PASSWORD} -S ${RS_SERVER_NAME} -b << EOF
admin who
go
EOF

exit $?
