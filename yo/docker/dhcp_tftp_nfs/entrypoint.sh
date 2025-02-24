#!/bin/sh

# Make sure we react to these signals by running stop() when we see them - for clean shutdown
# And then exiting
trap "stop; exit 0;" TERM INT

stop()
{
# We're here because we've seen SIGTERM, likely via a Docker stop command or similar
# Let's shutdown cleanly
    echo "SIGTERM caught, terminating process(es)..."
    echo "TFTP Terminate..."
    service tftpd-hpa stop
    echo "DHCP Terminate..."
    service isc-dhcp-server stop

    exit 0
}

start()
{
    echo "Starting services..."
    echo "DHCP init..."
    #debug isc: /usr/sbin/dhcpd -4 -d -cf /etc/dhcp/dhcpd.conf
    service rsyslog start
    service isc-dhcp-server start
    echo "TFTP init..."
    #debug tftpp: /usr/sbin/in.tftpd -L -vvv --secure /tftpboot &
    ##/usr/sbin/in.tftpd -L -vvv --secure /tftpboot
    service tftpd-hpa start
    echo "Started..."
    while true; do sleep 1; done

    exit 0
}

start
