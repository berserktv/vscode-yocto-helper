# Boot Raspbian over the network for the Raspberry Pi 4 board

![](https://habrastorage.org/webt/0m/6i/xw/0m6ixw8xy0_7wdkr1xw1smlfui0.png)

"Machine translation — oops!"

**Table of Contents:**

- Selecting and configuring a VSCode plugin
- Dishing Out Buster Slim for an Ultimate Docker Breakdown
- Configuring DHCP, TFTP, and NFS servers
- Network-booting a core-image-minimal (wic) image on RPi4
- Network-booting Raspbian for Raspberry Pi 4


## VSCode Plugin Selection

The plugin is called "VsCode Action Buttons" (seunlanlege.action-buttons). It does exactly what I needed – it allows you to attach/execute any bash code with a button click.

First of all, you need to install both VSCode itself (if you don't have it installed yet) and the plugin itself:


```bash
sudo apt install -y snap || sudo apt install -y snapd
sudo snap install --classic code
code --install-extension seunlanlege.action-buttons
```

Plugin settings are added to `.vscode/settings.json` and the shell script call looks like this:

```json
...
"actionButtons": {
    "reloadButton": null,
    "loadNpmCommands": false,
    "commands": [
        {
            "name": "Button-1",
            "singleInstance": true,
            "color": "#007fff",
            "command": ".vscode/script1.sh"
        },
        {
            "name": "Button-N",
            "singleInstance": true,
            "color": "#ff007f",
            "command": ".vscode/scriptN.sh"
        }
    ]
}
```


## Dishing Out Buster Slim for an Ultimate Docker Breakdown

Next, I'll tackle booting the "2025-05-13-raspios-bookworm-arm64.img" for Raspberry Pi 4. The next function I absolutely need is network booting for Raspberry Pi 4. This requires only an Ethernet cable - incredibly convenient. You can build a distribution version, load it over the network, test something, reload it, and repeat.

The setup assumes one host interface (e.g., Wi-Fi) provides internet access, while the second network interface remains free. We'll directly connect this free interface via cable to the Raspberry Pi 4's network port.

If you unpack it, you can examine its structure using the command:

`fdisk -l 2025-05-13-raspios-bookworm-arm64.img`

This is a RAW image containing a partition table with two logical partitions:

- A FAT32 boot partition;
- An ext4-formatted rootfs partition.

To mount this image, I've implemented the following code:

```bash
mount_raw_image() {
  if [[ -z "${IMAGE_DIR}" || -z "${IMAGE_NAME}" || -z "${MOUNT_DIR}" ]]; then
      echo "Error: Set environment variables IMAGE_DIR, IMAGE_NAME, and MOUNT_DIR" >&2
      return 1
  fi

  local image_file="${IMAGE_DIR}/${IMAGE_NAME}"
  if [ ! -f "${image_file}" ]; then
    echo "Error: Image file ${image_file} not found" >&2
    return 2
  fi

  local loop_dev=$(losetup -j "${image_file}" | awk -F: '{print $1}')
  if [ -z "${loop_dev}" ]; then
    echo "sudo losetup -f --show -P ${image_file}"
    loop_dev=$(sudo losetup -f --show -P "${image_file}")
    if [[ $? -ne 0 ]]; then echo "Error: Failed to create loop device" >&2; return 3; fi
    echo "Created new loop device: ${loop_dev}"
  else
    echo "Using existing loop device: ${loop_dev}"
  fi

  local uid=$(id -u)
  local gid=$(id -g)
  get_mount_base
  mkdir -p ${MOUNT_BASE_DIR}

  for part_num in {1..4}; do
    local partition="${loop_dev}p${part_num}"
    if [[ -b "${partition}" ]]; then
      local mount_point="${MOUNT_BASE_DIR}/part${part_num}"
      if mountpoint -q "${mount_point}"; then
        echo "Partition ${part_num} is already mounted at ${mount_point}, skipping..."
        continue
      fi

      mkdir -p "${mount_point}"
      echo "sudo blkid -o value -s TYPE ${partition}"
      local fs_type=$(sudo blkid -o value -s TYPE "${partition}")
      case "${fs_type}" in
        vfat)
            sudo mount -o rw,uid=${uid},gid=${gid} "${partition}" "${mount_point}" ;;
        *)
            sudo mount -o rw "${partition}" "${mount_point}" ;;
      esac

      if [[ $? -eq 0 ]]; then echo "Partition ${part_num} mounted at ${mount_point}";
      else echo "Error mounting partition ${part_num}" >&2; fi
    fi
  done
}
```

Here, I leverage a kernel mechanism that enables treating regular files as block devices. Loop devices essentially "wrap" files into virtual disks, allowing the system to interact with them identically to physical hardware.

The primary Linux utility for this is losetup. Different filesystem types may require slightly different parameters. For example, with FAT32, you can't edit files as a regular user without UID/GID mapping - and I absolutely need this capability.

The function requires three environment variables as parameters:

**`IMAGE_NAME`** - image filename
**`IMAGE_DIR`**  - directory containing the image file
**`MOUNT_DIR`**  - mount target directory

Note: This implementation additionally utilizes the `get_mount_base()` function:

```lua
MOUNT_BASE_DIR=""
IMAGE_NAME_SHORT=""
get_mount_base() {
    local name_without_ext="${IMAGE_NAME%.*}"
    MOUNT_BASE_DIR="${MOUNT_DIR}/${name_without_ext}"
    IMAGE_NAME_SHORT="${name_without_ext}"
}
```

This function uses the image name `IMAGE_NAME` to determine the base mount point within the `MOUNT_DIR` directory. Since the image is composite and may contain N partitions, each partition is mounted under standardized names (part1, part2, etc.). This establishes consistent naming conventions for any raw image.

Additionally, it sets a variable for the shortened image name.

For example:
From: 2025-05-13-raspios-bookworm-arm64.img
To: 2025-05-13-raspios-bookworm-arm64

For unmounting, I use `umount_raw_image()` with the same environment variables:

```lua
umount_raw_image() {
  if [[ -z "${IMAGE_DIR}" || -z "${IMAGE_NAME}" || -z "${MOUNT_DIR}" ]]; then
    echo "Error: Set environment variables IMAGE_DIR, IMAGE_NAME, and MOUNT_DIR" >&2; return 1
  fi

  get_mount_base
  local name_without_ext="${IMAGE_NAME%.*}"
  if [ ! -d ${MOUNT_BASE_DIR} ]; then
    echo "Error: ${MOUNT_BASE_DIR} not found, exiting ..." >&2; return 2
  fi

  local mounted_parts=("${MOUNT_BASE_DIR}"/part*)
  if [[ -e "${mounted_parts[0]}" ]]; then
    for mount_point in "${mounted_parts[@]}"; do
      if mountpoint -q "${mount_point}"; then
        echo "sudo umount ${mount_point}"
        sudo umount "${mount_point}"
        if [[ $? -eq 0 ]]; then echo "Successfully unmounted ${mount_point}"
        else echo "Error: Failed to unmount ${mount_point}" >&2; fi
      else
        echo "Warning: ${mount_point} is not mounted" >&2
      fi
    done
  else
      echo "No mounted partitions found in ${MOUNT_DIR}/${name_without_ext}"
  fi

  local image_file="${IMAGE_DIR}/${IMAGE_NAME}"
  if [[ -f "${image_file}" ]]; then
    local loop_devices
    loop_devices=$(losetup -j "${image_file}" | awk -F: '{print $1}')
    for loop_dev in ${loop_devices}; do
      echo "sudo losetup -d ${loop_dev}"
      sudo losetup -d "${loop_dev}"
      if [[ $? -eq 0 ]]; then echo "Successfully detached loop device ${loop_dev}"
      else echo "Error: Failed to detach loop device ${loop_dev}" >&2; fi
    done
  else
    echo "Warning: Image file ${image_file} not found, skipping loop device cleanup" >&2
  fi
}
```

With the `mount_raw_image()` and `umount_raw_image()` functions implemented, I can now proceed with network boot setup. 

For this purpose, I'll utilize the Buster Slim Docker container: "debian:buster-slim".


## Configuring DHCP, TFTP, and NFS servers

```dart
docker
└── dhcp_tftp_nfs
    ├── Dockerfile
    ├── entrypoint.sh
    ├── etc
    │   ├── default
    │   │   ├── isc-dhcp-server
    │   │   └── nfs-kernel-server
    │   ├── dhcp
    │   │   └── dhcpd.conf
    │   ├── exports
    │   └── network
    │       └── interfaces
    ├── Makefile
    ├── reconfig_net.sh
    └── rpi
        ├── cmdline.txt
        └── enable_uart.txt
```

Main Dockerfile:

```dart
FROM debian:buster-slim

ENV DEBIAN_FRONTEND noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN true

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
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

WORKDIR /

COPY entrypoint.sh /entrypoint.sh
# Set correct entrypoint permission
RUN chmod u+x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
```

This installation configures three core servers essential for network booting: DHCP, TFTP, and NFS.

The launch script `entrypoint.sh` appears as follows:

```bash
#!/bin/sh

# Make sure we react to these signals by running stop() when we see them - for clean shutdown
# And then exiting
trap "stop; exit 0;" TERM INT

stop()
{
# We're here because we've seen SIGTERM, likely via a Docker stop command or similar
# Let's shutdown cleanly
    echo "SIGTERM caught, terminating process(es)..."
    echo "NFS Terminate..."
    exportfs -uav
    service nfs-kernel-server stop
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
    service isc-dhcp-server start
    echo "TFTP init..."
    service tftpd-hpa start
    echo "NFS init..."
    service rpcbind start
    service nfs-common start
    service nfs-kernel-server start
    exportfs -rva

    echo "Started..."
    while true; do sleep 1; done

    exit 0
}

start
```

To launch the Buster Slim container, a Makefile is used:

```bash
IMAGE=dhcp_tftp_nfs
DOCKER_TAG=buster-slim
DOCKER_NETWORK="--network=host"
TFTP_DIR=/tmp/docker/tftp
NFS_DIR=/tmp/docker/nfs

# Host network config =>
HOST_NET_IFACE=""
IP_ADDR="10.0.7.1"
IP_SUBNET="10.0.7.0"
IP_MASK="255.255.255.0"
IP_MASK2="24"
IP_RANGE="range 10.0.7.100 10.0.7.200"

run:
    sudo nmcli connection delete "static-host-net" >/dev/null 2>&1 || true
    sudo nmcli connection add type ethernet con-name "static-host-net" \
        ifname ${HOST_NET_IFACE} ipv4.address ${IP_ADDR}/${IP_MASK2} \
        ipv4.method manual connection.autoconnect yes
    sudo nmcli connection up "static-host-net"

    sudo modprobe nfsd
    @sudo systemctl stop rpcbind.socket rpcbind > /dev/null 2>&1 || true

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
```

Here, Docker runs in privileged mode and mounts several core configuration files for DHCP and NFS during startup.

For the most basic setup, you can configure the following network interface files within Docker:

```lua
########################################
# configuration /etc/network/interfaces
######################################
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet static
address 10.0.7.1
netmask 255.255.255.0
```

Since the Buster Slim container runs in host network mode (--network=host), the network interface name must match the host's interface - in this example, "eth0".

DHCP server configuration within Docker:

```lua
#############################################
# configuration /etc/default/isc-dhcp-server
###########################################
DHCPDv4_CONF=/etc/dhcp/dhcpd.conf
DHCPDv4_PID=/var/run/dhcpd.pid
INTERFACESv4="eth0"

#####################################
# configuration /etc/dhcp/dhcpd.conf
###################################
option domain-name "example.org";
option domain-name-servers ns1.example.org;
default-lease-time 600;
max-lease-time 7200;
ddns-update-style none;

subnet 10.0.7.0 netmask 255.255.255.0 {
    range 10.0.7.100 10.0.7.200;
    option routers 10.0.7.1;
    option subnet-mask 255.255.255.0;
    option tftp-server-name "10.0.7.1";
    option bootfile-name "bootcode.bin";
}
```

For DHCP configuration, you must first specify the listening network interface - which must match the host's interface name. Next, define: the dynamic address pool range, gateway address, subnet mask, TFTP server address (which distributes files), and crucially, the primary network bootloader "bootcode.bin" (though I have questions about whether it's truly primary or secondary - but that's not the core issue here).

The critical point is: when network-booting a Raspberry Pi 4, this bootloader must reside in the TFTP server's root directory. Otherwise, the boot process fails completely.

By default, Raspberry Pi 4 prioritizes booting from microSD cards first, followed by USB devices, with network boot as the last option.

You can easily verify this: Connect an HDMI monitor, remove the SD card, and power on the board. With no SD card or USB drive connected, network boot should initiate - visible through the beautiful splash screen displaying a «network boot» startup message.

If issues persist, you may need to update the EEPROM variable controlling Raspberry Pi 4's boot order:

```lua
################################
# On Desktop computer
################################
# Install Raspberry Pi Imager
sudo apt install rpi-imager

# Insert microSD card into card reader for EEPROM update
# Launch rpi-imager program
rpi-imager

# Select OS to install (CHOOSE OS)
=> Misc utility images (Bootloader EEPROM configuration)
=> Bootloader (Pi 4 family)

# Choose one of three images with different boot priorities
# Recommend selecting boot priority: SD => USB => network
# i.e., network boot has lowest priority

# Wait for write completion. If successful,
# connect SD card to Raspberry Pi 4
# If you connect debug USB-UART to GPIO, you can monitor update process
sudo picocom --baud 115200 /dev/ttyUSB0

# After powering the board, UART at least shows progress, e.g.:
...
Reading EEPROM: 524288
Writing EEPROM
......................................................................................+....+
Verify BOOT EEPROM
Reading EEPROM: 524288
BOOT-EEPROM: UPDATED

# If no UART(A), monitor LEDs - they provide status clues
```

NFS server configuration in Docker:

```lua
###############################################
# configuration /etc/default/nfs-kernel-server
#############################################
# Number of servers to start up
RPCNFSDCOUNT=8
# Runtime priority of server (see nice(1))
RPCNFSDPRIORITY=0
# Options for rpc.mountd. (rpcinfo -p)
RPCMOUNTDOPTS="--nfs-version 4.2 --manage-gids"
NEED_SVCGSSD=""
# Options for rpc.svcgssd.
RPCSVCGSSDOPTS=""
# Options for rpc.nfsd. (cat /proc/fs/nfsd/versions)
RPCNFSDOPTS="--nfs-version 4.2"

############################
# configuration /etc/export
##########################
/nfs  *(rw,fsid=0,sync,no_subtree_check,no_root_squash,no_all_squash,crossmnt)
```

Here I enable version 4 where possible, though other versions should also work.

NFS export configuration:

* `rw` - read and write permission;
* `fsid=0` - specifies this as the root export for NFSv4. In NFSv4, clients mount a "virtual"
  root filesystem (e.g., /), with all other exports becoming its subdirectories;
* `sync` - requires synchronous disk writes before acknowledging operations,
  guaranteeing data integrity at the cost of performance;
* `no_subtree_check` - disables verification that files are within the exported directory on each access request;
* `no_root_squash` - preserves root user permissions from the client (no mapping to anonymous user).
  Grants clients full root access to server files. Essential for bootable OS rootfs since
  the launched OS wouldn't function properly otherwise;
* `no_all_squash` - preserves original UID/GID of client users on the server (no anonymous mapping).
  Also essential - see previous point.

I'd also like to note that specifically with the NFS server, I encountered several issues:

- First, it can only operate exclusively - meaning if you run two such Docker containers, the second
  will interfere with the first. I solve this by running the container
  without background mode (removing `make run_detach`),
  and always stopping all found containers with this name before launching;
- Second, in `network=host` mode, Docker will use the host's kernel module, requiring `modprobe nfsd`
  before starting the container;
- Third, before launching the container, you need to disable the `rpcbind` service on the host 
  as it also interferes with Docker.
  So if your desktop computer can't do without `rpcbind`, you might need to postpone the boot process,
  keep this in mind.

```cmake
sudo modprobe nfsd
@sudo systemctl stop rpcbind.socket rpcbind > /dev/null 2>&1 || true
```

Let's revisit the Buster Slim Makefile once more:

```lua
...
TFTP_DIR=/tmp/docker/tftp
NFS_DIR=/tmp/docker/nfs

# Host network config =>
HOST_NET_IFACE=""
IP_ADDR="10.0.7.1"
IP_SUBNET="10.0.7.0"
IP_MASK="255.255.255.0"
IP_MASK2="24"
IP_RANGE="range 10.0.7.100 10.0.7.200"
```

The `HOST_NET_IFACE` variable specifies the name of the host network interface that matches what's defined in `/etc/network/interfaces` and `/etc/default/isc-dhcp-server`.

When working with Docker, I first execute the shell script `docker/dhcp_tftp_nfs/reconfig_net.sh` to automatically configure `/etc/network/interfaces`, `/etc/default/isc-dhcp-server`, and several other files.

This reconfiguration occurs only when the Makefile variable `HOST_NET_IFACE=""` is empty.

After reconfiguration, the script updates this variable with the identified local network interface name (e.g., `HOST_NET_IFACE="eth0"`), meaning the setup effectively runs just once.

The `reconfig_net.sh` script uses these variables from the `Makefile` for configuration:  
`IP_ADDR` `IP_SUBNET` `IP_MASK` `IP_RANGE`  
allowing you to add custom local configurations. However, there's one challenge: I identify the host computer's local network interface as follows:

```lua
ip link show | awk -F: '$0 !~ "lo|vir|docker|veth|br|wl" {print $2; getline; print $2}' | tr -d ' ' | head -n 1

# and if you happen to have two local network interfaces,
# this might not work
# requiring you to manually configure
# the aforementioned files

# there's also an issue
# with the IP_TFTP="10.0.7.1" variable in func.sh
# currently it is static
# meaning if you change IP_ADDR in the Makefile
# you must also update this variable
```

The Makefile also specifies core base directories `TFTP_DIR` and `NFS_DIR`, which are always mounted into Docker at startup. These could be symbolic links to directories representing mount points obtained through the `mount_raw_image()` function.

For `2025-05-13-raspios-bookworm-arm64.img` for example:  
link `/tmp/docker/tftp` => `2025-05-13-raspios-bookworm-arm64/part1`  
link `/tmp/docker/nfs`  => `2025-05-13-raspios-bookworm-arm64/part2`

We serve the boot partition via TFTP, while the root rootfs partition is served by the NFS server.

## Image Dissection

So what's great about image dissection? It makes you completely indifferent to what you load - example "Raspbian".

In this scenario, the Buster Slim Docker **works wonders**. This is an awesome breakdown.

In some cases, when an image is loaded, it will think it's running natively. For Raspbian, the image is physically a single file containing a partition table and logical drives. After mounting via `losetup`, the image gets dissected into multiple logical drives (usually two), and each mount point will behave according to its filesystem capabilities - ext4 allows writing, ISO is read-only, etc.

Free space in the image is usually limited since minimizing image size is crucial, but this can be fixed for long-term use of the same image. After all, a good image should always be at hand.


## Network Boot for Raspbian on Raspberry Pi 4 Board

So the top-level code for Raspbian network boot:

```lua
start_netboot_raspios() {
    set_env_raw_raspios
    stop_docker "dhcp_tftp_nfs:buster-slim"
    mount_raw_raspios && start_session_docker
}
```

next:

```lua
set_env_raw_raspios() {
  IMAGE_DIR="${DOWNLOAD_RASPIOS}"
  IMAGE_NAME="2025-05-13-raspios-bookworm-arm64.img"
  MOUNT_DIR="${DOWNLOAD_RASPIOS}/tmp_mount"
  DOCKER_DIR='docker/dhcp_tftp_nfs'
}

mount_raw_raspios() {
  download_raspios || return 1
  mount_raw_image || return 2
  add_cmdline_for_nfs_raspios
  disable_partuuid_fstab_for_raspios
  docker_dhcp_tftp_reconfig_net
  change_bootloader_name_in_dhcp "raspberry"
  create_mount_point_for_docker "tftp" "${MOUNT_BASE_DIR}/part1"
  create_mount_point_for_docker "nfs" "${MOUNT_BASE_DIR}/part2"
}
```

Here I modify the standard `cmdline.txt` on the FAT boot partition to this:

```lua
console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=10.0.7.1:/nfs,hard,nolock,vers=3 rw ip=dhcp rootwait
```

Additionally, to ensure everything works smoothly, you need to modify the standard `/etc/fstab` in the Raspbian image:  
(Otherwise it won't work - it will keep checking, attempting to verify, and hang indefinitely)

```lua
disable_partuuid_fstab_for_raspios() {
  local fstab_file="${MOUNT_BASE_DIR}/part2/etc/fstab"
  [[ -f "${fstab_file}" ]] || return 1

  if cat "${fstab_file}" | grep -q "^PARTUUID="; then
      echo "Disable the PARTUUID entries in ${fstab_file}"
      echo "This is an NFS root filesystem for RaspiOS, and the root password is required."
      sudo sed -i "s|^PARTUUID=|#PARTUUID=|g" "${fstab_file}"
  fi
}

restore_partuuid_fstab_for_raspios() {
  local fstab_file="${MOUNT_BASE_DIR}/part2/etc/fstab"
  [[ -f "${fstab_file}" ]] || return 1

  if cat "${fstab_file}" | grep -q "^#PARTUUID="; then
      echo "Need to restore the PARTUUID entries in ${fstab_file}"
      echo "This is an NFS root filesystem for RaspiOS, and the root password is required."
      sudo sed -i "s|^#PARTUUID=|PARTUUID=|g" "${fstab_file}"
  fi
}
```

But we'll outsmart it: comment out the `PARTUUID=` disks under root privileges. Later if needed, we can re-enable them, preserving the image's ability to be flashed to an SD card with `dd`:

```lua
restore_image_raspios() {
    set_env_raw_raspios
    mount_raw_image
    local mount_dir="${MOUNT_BASE_DIR}/part1"
    for file in config.txt cmdline.txt; do
        restore_orig "${mount_dir}/${file}"
    done
    restore_partuuid_fstab_for_raspios
    umount_raw_image
}
```

Note: UART debugging is also enabled in `config.txt` - it can be connected to GPIO pins. This setting is restored to the original `Raspbian` (RaspiOS) configuration.


To install the "vscode-yocto-helper" project, try running the command:

```bash
curl -fsSL https://github.com/berserktv/vscode-yocto-helper/blob/RaspbianLoader/install.sh | sh
```
           

Or view it this way:

```bash
    mkdir vscode-yocto-helper
    cd vscode-yocto-helper
    git clone -b RaspbianLoader https://github.com/berserktv/vscode-yocto-helper.git .vscode
    code .
```

So in my view, the result is "Network Boots" - I hadn't used NFS before and didn't realize how powerful it is. Just one recommendation: don't expose Docker in host mode to the internet, it's not secure.
