# Sybase ASE 16.0 Docker Image
#
# This Dockerfile creates a Sybase ASE server container.
#
# Prerequisites:
# 1. Download SAP ASE Developer Edition 16.0 from SAP:
#    https://go.sap.com/cmp/syb/crm-xu15-int-asewindm/typ.html
#    or direct link:
#    http://d1cuw2q49dpd0p.cloudfront.net/ASE16.0/Linux16SP02/ASE_Suite.linuxamd64.tgz
#
# 2. Place the downloaded file (ASE_Suite.linuxamd64.tgz) in this directory
#
# Build:
#   docker build -t sybase-ase:16.0 .
#
# Run:
#   docker run -d -p 5000:5000 -p 5001:5001 --name sybase-ase sybase-ase:16.0

FROM centos:7

LABEL maintainer="Sybase DBA Migration Team"
LABEL description="SAP Sybase ASE 16.0 Developer Edition"
LABEL version="16.0"

# Build arguments
ARG ASE_SERVER_NAME=SYBASE
ARG ASE_SA_PASSWORD=SybaseP@ss123

# Environment variables
ENV SYBASE=/opt/sybase
ENV SYBASE_ASE=ASE-16_0
ENV SYBASE_OCS=OCS-16_0
ENV PATH=$SYBASE/$SYBASE_ASE/bin:$SYBASE/$SYBASE_OCS/bin:$PATH
ENV LD_LIBRARY_PATH=$SYBASE/$SYBASE_ASE/lib:$SYBASE/$SYBASE_OCS/lib:$LD_LIBRARY_PATH
ENV ASE_SERVER_NAME=${ASE_SERVER_NAME}
ENV ASE_SA_PASSWORD=${ASE_SA_PASSWORD}

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

# Set kernel parameters (will be applied at runtime)
COPY sysctl.conf /etc/sysctl.d/99-sybase.conf

# Copy installation files
# NOTE: You must download ASE_Suite.linuxamd64.tgz from SAP and place it here
COPY --chown=sybase:sybase ASE_Suite.linuxamd64.tgz /opt/tmp/
COPY --chown=sybase:sybase sybase-response.txt /opt/tmp/
COPY --chown=sybase:sybase sybase-ase.rs.template /opt/tmp/
COPY --chown=sybase:sybase entrypoint.sh /opt/sybase/
COPY --chown=sybase:sybase interfaces.template /opt/tmp/

# Extract and install ASE
USER sybase
WORKDIR /opt/tmp

RUN tar xzf ASE_Suite.linuxamd64.tgz && \
    rm -f ASE_Suite.linuxamd64.tgz

# Run silent installation
RUN ./ASE_Suite/setup.bin \
    -f /opt/tmp/sybase-response.txt \
    -i silent \
    -DAGREE_TO_SAP_LICENSE=true \
    -DRUN_SILENT=true \
    -DINSTALL_LOCATION=/opt/sybase

# Clean up installation files
RUN rm -rf /opt/tmp/ASE_Suite

# Make entrypoint executable
USER root
RUN chmod +x /opt/sybase/entrypoint.sh

# Switch back to sybase user
USER sybase
WORKDIR /opt/sybase

# Expose ports
# 5000 - ASE Server
# 5001 - Backup Server
EXPOSE 5000 5001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=5 \
    CMD /opt/sybase/scripts/healthcheck.sh || exit 1

# Entry point
ENTRYPOINT ["/opt/sybase/entrypoint.sh"]
