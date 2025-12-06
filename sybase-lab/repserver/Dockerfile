# Sybase Replication Server Docker Image
#
# This Dockerfile creates a Sybase Replication Server container.
#
# Prerequisites:
# 1. Download SAP Replication Server from SAP
# 2. Place the downloaded installer in this directory
#
# Build:
#   docker build -t sybase-repserver:16.0 .
#
# Run:
#   docker run -d -p 5100:5100 --name sybase-repserver sybase-repserver:16.0

FROM centos:7

LABEL maintainer="Sybase DBA Migration Team"
LABEL description="SAP Sybase Replication Server 16.0"
LABEL version="16.0"

# Build arguments
ARG RS_SERVER_NAME=REPSERVER
ARG RS_SA_PASSWORD=RepServerP@ss123

# Environment variables
ENV SYBASE=/opt/sybase
ENV SYBASE_REP=REP-16_0
ENV SYBASE_OCS=OCS-16_0
ENV PATH=$SYBASE/$SYBASE_REP/bin:$SYBASE/$SYBASE_OCS/bin:$PATH
ENV LD_LIBRARY_PATH=$SYBASE/$SYBASE_REP/lib:$SYBASE/$SYBASE_OCS/lib:$LD_LIBRARY_PATH
ENV RS_SERVER_NAME=${RS_SERVER_NAME}
ENV RS_SA_PASSWORD=${RS_SA_PASSWORD}

# Install required packages
RUN yum -y update && \
    yum -y install \
        libaio \
        glibc.i686 \
        libstdc++.i686 \
        ncurses-libs.i686 \
        libgcc.i686 \
        net-tools \
        hostname \
        which \
        curl \
        unzip \
        tar \
        gzip \
        procps-ng \
    && yum clean all \
    && rm -rf /var/cache/yum

# Create sybase user and directories
RUN groupadd -g 1000 sybase && \
    useradd -u 1000 -g sybase -d /opt/sybase -s /bin/bash sybase && \
    mkdir -p /opt/sybase/data /opt/sybase/logs /opt/sybase/scripts /opt/tmp && \
    chown -R sybase:sybase /opt/sybase /opt/tmp

# Set kernel parameters
COPY sysctl.conf /etc/sysctl.d/99-sybase.conf

# Copy installation files
# NOTE: You must download Replication Server installer from SAP and place it here
# COPY --chown=sybase:sybase RepServer_Suite.linuxamd64.tgz /opt/tmp/
COPY --chown=sybase:sybase rs-response.txt /opt/tmp/
COPY --chown=sybase:sybase rs-config.rs.template /opt/tmp/
COPY --chown=sybase:sybase entrypoint.sh /opt/sybase/
COPY --chown=sybase:sybase interfaces.template /opt/tmp/

# Note: Uncomment the following lines once you have the Replication Server installer
# USER sybase
# WORKDIR /opt/tmp
# RUN tar xzf RepServer_Suite.linuxamd64.tgz && rm -f RepServer_Suite.linuxamd64.tgz
# RUN ./RepServer_Suite/setup.bin -f /opt/tmp/rs-response.txt -i silent -DAGREE_TO_SAP_LICENSE=true

# Make entrypoint executable
USER root
RUN chmod +x /opt/sybase/entrypoint.sh

# Switch back to sybase user
USER sybase
WORKDIR /opt/sybase

# Expose Replication Server port
EXPOSE 5100

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=5 \
    CMD /opt/sybase/scripts/rs_healthcheck.sh || exit 1

# Entry point
ENTRYPOINT ["/opt/sybase/entrypoint.sh"]
