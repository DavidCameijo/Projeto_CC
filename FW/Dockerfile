FROM debian:12

# Install nftables, iptables, and utilities
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nftables \
        iptables \
        iproute2 \
        procps \
        curl \
        openssl \
        ca-certificates \
        nano \
        tcpdump \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create directories for configs and integrity checks
RUN mkdir -p /etc/firewall /var/log/firewall

# Copy nftables configuration
COPY nftables.conf /etc/nftables.conf
COPY rules.d /etc/firewall/rules.d
COPY integrity-check.sh /usr/local/bin/integrity-check.sh
COPY entrypoint.sh /entrypoint.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/integrity-check.sh /entrypoint.sh

# Enable IP forwarding (for routing between networks)
RUN echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && \
    echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf

WORKDIR /etc/firewall

ENTRYPOINT ["/entrypoint.sh"]
CMD ["tail", "-f", "/dev/null"]
