IMAGE=dhcp_tftp_server
DOCKER_TAG=buster-slim
DOCKER_NETWORK="--network=host"
TFTP_DIR=/tmp/tftp
NFS_DIR=/tmp/nfs

# Host network config =>
HOST_NET_IFACE=""
IP_ADDR="10.0.7.1"
IP_SUBNET="10.0.7.0"
IP_MASK="255.255.255.0"
IP_MASK2="24"
IP_RANGE="range 10.0.7.100 10.0.7.200"

run:
	#sudo nmcli connection add type ethernet ifname $(HOST_NET_IFACE) ip4 $(IP_ADDR)/$(IP_MASK2) autoconnect yes
	sudo ip addr flush dev $(HOST_NET_IFACE)
	sudo ip addr add $(IP_ADDR)/$(IP_MASK) dev $(HOST_NET_IFACE)
	sudo ip link set $(HOST_NET_IFACE) up
	
	sudo modprobe nfsd
	if ps aux | grep -q /sbin/rpcbind; then sudo systemctl stop rpcbind.socket; sudo systemctl stop rpcbind; fi

	docker run --rm -ti --privileged \
	${DOCKER_NETWORK} \
	-v ${TFTP_DIR}:/srv/tftp \
	-v ${NFS_DIR}:/nfs \
	-v ${PWD}/etc/exports:/etc/exports \
	-v ${PWD}/etc/default/nfs-kernel-server:/etc/default/nfs-kernel-server \
	-v ${PWD}/etc/default/isc-dhcp-server:/etc/default/isc-dhcp-server \
	-v ${PWD}/etc/dhcp/dhcpd.conf:/etc/dhcp/dhcpd.conf \
	-v ${PWD}/etc/network/interfaces:/etc/network/interfaces \
	${IMAGE}:${DOCKER_TAG}
	
build:
	docker build --rm -t ${IMAGE}:${DOCKER_TAG} .

rebuild:
	docker build --rm --no-cache -t ${IMAGE}:${DOCKER_TAG} .
	
install:
	sudo apt-get update
	sudo apt-get install -y docker.io
	
clean-all-container:
	sudo docker rm $(docker ps -qa)
	
.PHONY: run build clean-all-container
