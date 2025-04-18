#!/bin/bash
INTERFACES_FILE="${PWD}/etc/network/interfaces"
DHCP_SERVER_FILE="${PWD}/etc/default/isc-dhcp-server"
DHCP_CONF_FILE="${PWD}/etc/dhcp/dhcpd.conf"
CMDLINE_FILE="${PWD}/rpi/cmdline.txt"
MAKEFILE="${PWD}/Makefile"

if ! grep -q 'HOST_NET_IFACE=""' Makefile; then
    echo "HOST_NET_IFACE is set in Makefile, skipping ..."
    exit 0
fi

# find local network interface for host
LOCAL_NET_IFACE=$(ip link show | awk -F: '$0 !~ "lo|vir|docker|veth|br|wl" {print $2; getline; print $2}' | tr -d ' ' | head -n 1)

if [ -z "$LOCAL_NET_IFACE" ]; then
    echo "No local network interface found, exiting ..."
    exit 1
fi

test -f ${INTERFACES_FILE}.orig || cp ${INTERFACES_FILE} ${INTERFACES_FILE}.orig
test -f ${DHCP_SERVER_FILE}.orig || cp ${DHCP_SERVER_FILE} ${DHCP_SERVER_FILE}.orig
test -f ${DHCP_CONF_FILE}.orig || cp ${DHCP_CONF_FILE} ${DHCP_CONF_FILE}.orig

IP_ADDR=$(grep 'IP_ADDR=' "$MAKEFILE" | cut -d'=' -f2 | tr -d '"')
IP_MASK=$(grep 'IP_MASK=' "$MAKEFILE" | cut -d'=' -f2 | tr -d '"')
IP_RANGE=$(grep 'IP_RANGE=' "$MAKEFILE" | cut -d'=' -f2 | tr -d '"')
IP_SUBNET=$(grep 'IP_SUBNET=' "$MAKEFILE" | cut -d'=' -f2 | tr -d '"')
echo "Using local network interface: $LOCAL_NET_IFACE => $IP_ADDR/$IP_MASK"

DHCP_CONFIG=$(cat << EOF
subnet $IP_SUBNET netmask $IP_MASK {
  $IP_RANGE;
  option routers $IP_ADDR;
  option subnet-mask $IP_MASK;
  option tftp-server-name "$IP_ADDR";
  option bootfile-name "bootcode.bin";
}
EOF
)

INTERFACES_CONFIG=$(cat << EOF
auto $LOCAL_NET_IFACE
  iface $LOCAL_NET_IFACE inet static
  address $IP_ADDR
  netmask $IP_MASK
EOF
)

sed -i "s/HOST_NET_IFACE=\"\"/HOST_NET_IFACE=\"$LOCAL_NET_IFACE\"/" "$MAKEFILE"
echo "replaced HOST_NET_IFACE with LOCAL_NET_IFACE in $MAKEFILE"

cp ${INTERFACES_FILE}.orig ${INTERFACES_FILE}
cp ${DHCP_SERVER_FILE}.orig ${DHCP_SERVER_FILE}
cp ${DHCP_CONF_FILE}.orig ${DHCP_CONF_FILE}

# change isc-dhcp-server
sed -i '/^INTERFACESv4=/s/^/#/' "$DHCP_SERVER_FILE"
echo "INTERFACESv4=\"$LOCAL_NET_IFACE\"" >> "$DHCP_SERVER_FILE"
echo "added $LOCAL_NET_IFACE to INTERFACESv4 in $DHCP_SERVER_FILE"
# change interfaces
if grep -q -E "^auto ($LOCAL_NET_IFACE|eth0)" "$INTERFACES_FILE"; then
    sed -i "/^auto eth0/,/^$/s/^/#/" "$INTERFACES_FILE"
    sed -i "/^auto $LOCAL_NET_IFACE/,/^$/s/^/#/" "$INTERFACES_FILE"
    echo "commented out existing configuration for $LOCAL_NET_IFACE in $INTERFACES_FILE"
fi
echo "$INTERFACES_CONFIG" >> $INTERFACES_FILE
echo "added $LOCAL_NET_IFACE to $INTERFACES_FILE with address $IP_ADDR and netmask $IP_MASK"
# change dhcpd config
sed -i '/^subnet/,/^}/ s/^/#/' $DHCP_CONF_FILE
echo "$DHCP_CONFIG" >> $DHCP_CONF_FILE
echo "adding DHCP_CONFIG to $DHCP_CONF_FILE"
# change IP NFS server
sed -i "s|NFS_IP_ADDRESS|$IP_ADDR|" $CMDLINE_FILE
echo "adding NFS_IP_ADDRESS to $CMDLINE_FILE"
