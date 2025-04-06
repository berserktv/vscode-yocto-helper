FROM debian:buster-slim

ENV DEBIAN_FRONTEND noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN true

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        lsof procps net-tools \
        isc-dhcp-server \
        tftpd-hpa \
        rpcbind \
        nfs-kernel-server && \
    # Clean rootfs
    apt-get clean all && \
    apt-get autoremove -y && \
    apt-get purge && \
    rm -rf /var/lib/{apt,dpkg,cache,log} && \
    # Configure DHCP
    touch /var/lib/dhcp/dhcpd.leases && \
    # Configure rpcbind
    mkdir -p /run/sendsigs.omit.d /etc/modprobe.d /var/lib/nfs && \
    touch /run/sendsigs.omit.d/rpcbind && \
    touch /var/lib/nfs/state
    
# ALEX debug    
#RUN apt-get install -y rsyslog

WORKDIR /

COPY entrypoint.sh /entrypoint.sh
# Set correct entrypoint permission
RUN chmod u+x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
