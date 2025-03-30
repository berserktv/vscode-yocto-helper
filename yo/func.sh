#!/bin/bash

# корневой каталог yocto, где будет располагаться каталог build, относительно текущего каталога
YO_R="../.."
CURDIR=$(pwd)
find_setup_env() {
    if [ -f "${YO_R}/setup-environment" ]; then return 0; fi
    local tmp_path=".."
    for i in {1..7}; do
        if [ -f "${tmp_path}/setup-environment" ]; then
            export YO_R=$(realpath "${tmp_path}")
            return 0;
        fi
        tmp_path="${tmp_path}/.."
    done
    echo "error: 'setup-environment' not found in parent directories, env: 'YO_R' wrong path ..."; return 1
}
check_first_start() {
    [[ -d "${YO_R}/build" ]] && return 0
    [[ ! -f "${YO_R}/shell.sh" ]] && return 1
    cd "${YO_R}" && ./shell.sh
    cd "${CURDIR}"
}
find_setup_env
check_first_start

YO_M=`cat $YO_R/build/conf/local.conf | grep "^MACHINE " | cut -d"'" -f2`
YO_DIR_IMAGE="$YO_R/build/tmp/deploy/images"
YO_DIR_PROJECTS="$HOME/yocto"
YO_IMAGE_NAME=""
YO_EXT=".wic .rootfs.wic .rootfs.wic.bz2 .rpi-sdimg .wic.bz2"
DOCKER_DIR=""
DOCKER_DIR_MOUNT="/tmp/docker"
DOCKER_DHCP_TFTP="docker/dhcp_tftp_nfs"
LI_DISK=""
IP_COMP="192.168.0.1"
IP_TFTP="10.0.7.1"
USER_COMP="user"
KEY_ID="computer_id_rsa"
CONTAINER_ID=""
CONTAINER_NAME=""
IMAGE_NAME=""
IMAGE_DIR=""
IMAGE_SEL=""
IMAGE_KALI_URL=""
IMAGE_UBUNTU_URL=""
MOUNT_DIR=""
DOWNLOAD_DIR="$HOME/distrib"
DOWNLOAD_RASPIOS="${DOWNLOAD_DIR}/raspios"
DOWNLOAD_UBUNTU="${DOWNLOAD_DIR}/ubuntu"
DOWNLOAD_KALI="${DOWNLOAD_DIR}/kali"
CMDLINE_RPI4="docker/dhcp_tftp_nfs/rpi/cmdline.txt"
ENABLE_UART_RPI4="docker/dhcp_tftp_nfs/rpi/enable_uart.txt"
MENU_ITEM_UBUNTU="docker/dhcp_tftp_nfs/ubuntu/menu_item_to_pxe.txt"

# общие функции для работы с IDE vscode
gen_send_ssh_key() {
    ssh-keygen -t rsa -q -N '' -f ~/.ssh/${KEY_ID}
    ssh-copy-id -i ~/.ssh/${KEY_ID}.pub ${USER_COMP}@${IP_COMP}
}

#DEEPSEEK_MODEL="deepseek-coder-v2" # size 8.9 Gb
DEEPSEEK_MODEL="deepseek-r1:8b"     # size 4.9 Gb
install_deepseek() {
    # installation requires ~ 4.9 + 3 Gb Ollama
    curl -fsSL https://ollama.com/install.sh | sh
    ollama serve
    ollama run ${DEEPSEEK_MODEL}
}

run_deepseek() { ollama run ${DEEPSEEK_MODEL}; }

unistall_ollama() {
    #Remove the ollama service:
    sudo systemctl stop ollama
    sudo systemctl disable ollama
    sudo rm /etc/systemd/system/ollama.service
    #Remove the ollama binary from your bin directory:
    sudo rm $(which ollama)
    #Remove the downloaded models and Ollama service user and group:
    sudo rm -r /usr/share/ollama
    sudo userdel ollama
    sudo groupdel ollama
    #Remove installed libraries:
    sudo rm -rf /usr/local/lib/ollama
}

find_docker_id() {
    local id=$(docker ps | grep -m1 $CONTAINER_NAME | cut -d" " -f1)
    if [ -z "$id" ]; then CONTAINER_ID=""; return 1;
    else CONTAINER_ID=$id; return 0; fi
}

docker_dhcp_tftp_reconfig_net() {
    cd "${DOCKER_DHCP_TFTP}"
    ./reconfig_net.sh
    cd "${CURDIR}"
}

start_cmd_docker() {
    if [ -z "$1" ]; then
        echo "error: start_cmd_docker(), arg1 command name empty ..."
        return 1;
    fi

    local cmd_args=$1
    cd $DOCKER_DIR
    if ! find_docker_id; then
        make build && make run_detach
        if ! find_docker_id; then
            echo "failed to start container => make run_detach ..."
            cd "${CURDIR}"
            return 2;
        fi
    fi

    echo "docker exec -it ${CONTAINER_ID} bash -c \"$cmd_args\""
    docker exec -it ${CONTAINER_ID} bash -c "$cmd_args"
    cd "${CURDIR}"
}

start_session_docker() {
    cd "${DOCKER_DIR}"
    make build && make run
    cd "${CURDIR}"
}

find_name_image() {
    IFS=$' '
    YO_IMAGE_NAME=""
    if [ -z "$YO_M" ]; then echo "MACHINE variable not found"; return -1; fi

    for ext in ${YO_EXT}; do
        local find_str=$(ls -1 ${YO_DIR_IMAGE}/${YO_M} | grep "${YO_M}${ext}$")
        if [ -z "$find_str" ]; then
            echo "NAME IMAGE ${YO_M}${ext} is not found => ${YO_DIR_IMAGE}/${YO_M}"
        else 
            YO_IMAGE_NAME="$YO_IMAGE_NAME $find_str"
            echo "find: YO_IMAGE_NAME=$YO_IMAGE_NAME"
        fi
    done

    [[ -z "${YO_IMAGE_NAME}" ]] && return 1
    YO_IMAGE_NAME=$(echo "$YO_IMAGE_NAME" | tr '\n' ' ')
    return 0
}

find_sd_card() {
    IFS=$'\n'
    LI_DISK=""
    echo "Disk devices in the system:"
    echo "┌────┬──────┬──────┬──────────────────────────────┐"
    echo "Name | Type | Size | Model                        |"
    echo "├────┴──────┴──────┴──────────────────────────────┘"
    lsblk -o NAME,TYPE,SIZE,MODEL | grep -E 'disk|mmcblk|sd.*'
    echo "└─────────────────────────────────────────────────┘"
    local bn;
    local list=$(ls -l /dev/disk/by-id/usb* 2>/dev/null)
    if [ $? -eq 0 ]; then
        for i in $list; do
            bn=$(basename $i)
            if ! echo "$bn" | grep -q "[0-9]"; then LI_DISK+="$bn "; fi
        done 
    fi

    list=$(ls -l /dev/disk/by-id/mmc* 2>/dev/null)
    if [ $? -eq 0 ]; then
        for i in $list; do
            bn=$(basename $i)
            if ! echo "$bn" | grep -q "p[0-9]"; then LI_DISK+="$bn "; fi
        done 
    fi
    if [ -n "$LI_DISK" ]; then echo "LIST SD card => $LI_DISK"; return 0;
    else echo "SD card not found => exiting ..."; return 1; fi
}

select_dd_info() {
    local j=1
    IFS=$' '
    for i in $LI_DISK; do
        for image in $YO_IMAGE_NAME; do
            if echo "$image" | grep -q "\.wic\.bz2"; then
                echo "$j) bzip2 -dc $image | sudo dd of=/dev/$i bs=1M"
            else
                echo "$j) dd if=$image of=/dev/$i bs=1M"
            fi
            j=$((j+1))
        done
    done

    echo -n "=> Select the option. WARNING: the data on the disk will be DELETED:"
    read SEL

    j=1
    for i in $LI_DISK; do
        for image in $YO_IMAGE_NAME; do
            if [ $SEL == "$j" ]; then
                mount | grep "^/dev/$i" | awk '{print $1}' | xargs -r sudo umount
                if echo "$image" | grep -q "\.wic\.bz2"; then
                    echo "bzip2 -dc $image | sudo dd of=/dev/$i bs=1M"
                    bzip2 -dc $image | sudo dd of=/dev/$i bs=1M; sync
                else
                    echo "sudo dd if=$image of=/dev/$i bs=1M"
                    sudo dd if=$image of=/dev/$i bs=1M; sync
                fi
            fi
            j=$((j+1))
        done
    done
}

sdcard_deploy() {
    if find_sd_card && find_name_image; then
        cd "${YO_DIR_IMAGE}/${YO_M}"
        select_dd_info
    fi
}

ssh_config_add_negotiate() {
    if [ -z "$1" ]; then echo "error: ssh_config_add_negotiate(), arg1 IP address ..."; return 1; fi
    if ! cat ~/.ssh/config | grep -q "$1"; then
        echo "Host $1" >> ~/.ssh/config
        echo "  User ${USER_COMP}"
        echo "  HostkeyAlgorithms +ssh-rsa" >> ~/.ssh/config
        echo "  PubkeyAcceptedAlgorithms +ssh-rsa" >> ~/.ssh/config
    fi
}

# to run image Raspberrypi3-64 Yocto with SysVinit you need to change variables (not tested under Systemd)
# SERIAL_CONSOLES = "115200;ttyAMA0"; SERIAL_CONSOLES_CHECK = "ttyAMA0:ttyS0"; => /etc/inittab
start_qemu_rpi3_64() {
    local kernel="Image"
    local dtb="bcm2837-rpi-3-b.dtb"
    local image="core-image-minimal-raspberrypi3-64.rpi-sdimg"
    cd "${YO_DIR_IMAGE}/${YO_M}"

    size_mb=$(( ($(stat -c %s "$image") + 1048575) / 1048576 ))
    thresholds=(64 128 256 512)

    for threshold in "${thresholds[@]}"; do
        if [ "$size_mb" -lt "$threshold" ]; then
            qemu-img resize "${image}" "${threshold}M"
        fi
    done

    qemu-system-aarch64 \
        -m 1G \
        -M raspi3b \
        -dtb ${dtb} \
        -kernel ${kernel} \
        -serial mon:stdio \
        -drive file=${image},format=raw,if=sd,readonly=off \
        -append "console=ttyAMA0,115200 root=/dev/mmcblk0p2 rw earlycon=pl011,0x3f201000" \
        -nographic
    cd "${CURDIR}"
}

MOUNT_BASE_DIR=""
IMAGE_NAME_SHORT=""
get_mount_base() {
    local name_without_ext="${IMAGE_NAME%.*}"
    MOUNT_BASE_DIR="${MOUNT_DIR}/${name_without_ext}"
    IMAGE_NAME_SHORT="${name_without_ext}"
}

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
            sudo losetup -d "${loop_dev}"
            if [[ $? -eq 0 ]]; then echo "Successfully detached loop device ${loop_dev}"
            else echo "Error: Failed to detach loop device ${loop_dev}" >&2; fi
        done
    else
        echo "Warning: Image file ${image_file} not found, skipping loop device cleanup" >&2
    fi
}

select_yocto_image() {
    j=1
    IMAGE_SEL=""
    for image in $YO_IMAGE_NAME; do
        echo "$j) $image"
        j=$((j+1))
    done

    echo -n "=> Select an image to Load:"
    read SEL

    i=1
    for image in $YO_IMAGE_NAME; do
        [ $i -eq $SEL ] && IMAGE_SEL="$image" && break
        i=$((i+1))
    done
    [[ -n "${IMAGE_SEL}" ]] || { echo "Image not selected, exiting ..."; return 1; }
}

download_files() {
    local dir="$1"
    local url="$2"
    local count_error=0
    shift 2
    for FILE in "$@"; do
        local file_path="$dir/$FILE"
        local file_dir=$(dirname "$file_path")
        mkdir -p "$file_dir"
        if [ -f "$file_path" ]; then echo "file $file_path already exists, skipping ...";
        else wget -P "$file_dir" "$url/$FILE" || { echo "Failed to download $FILE"; count_error=$((count_error+1)); }; fi
    done
    return $count_error
}

download_raspios() {
    # arg1 - select version
    mkdir -p "${DOWNLOAD_RASPIOS}"
    local url="https://downloads.raspberrypi.com/raspios_arm64/images/"
    local latest_dir
    local selected_dir

    local dir_list=$(curl -s "$url" | grep -oP 'raspios_arm64-\d{4}-\d{2}-\d{2}/' | sort -u -r)
    if [ -z "$1" ]; then
        latest_dir=$(echo "$dir_list" | head -n 1)
        echo "Selected the latest available image: $latest_dir"
        selected_dir="$latest_dir"
    else
        echo "Available images:"
        echo "$dir_list" | nl
        read -p "Enter the number of the image to download: " choice
        selected_dir=$(echo "$dir_list" | sed -n "${choice}p")
        if [ -z "$selected_dir" ]; then
            echo "Error: Invalid selection."
            return 1
        fi
    fi

    local selected_file=$(curl -s "${url}${selected_dir}" | grep -oP 'href="\K[^"]+\.img\.xz' | sort -u | head -n 1)
    if [ -z "$selected_file" ]; then
        echo "Error: No image file (.img.xz) found in the directory."
        return 2
    fi

    local extracted_file="${selected_file%.xz}"
    if [ -f "${DOWNLOAD_RASPIOS}/${extracted_file}" ]; then
        echo "File already exists: ${DOWNLOAD_RASPIOS}/${extracted_file}, skipping ..."; return
    fi

    local download_url="${url}${selected_dir}"
    echo "Downloading file: $selected_file"
    download_files "${DOWNLOAD_RASPIOS}" "$download_url" "${selected_file}"

    local downloaded_file="${DOWNLOAD_RASPIOS}/${selected_file}"
    echo "Extracting XZ archive..."
    xz -d "$downloaded_file"
}

add_lines_to_config_txt() {
    local enable_uart_txt="$1"
    local config_txt="$2"
    while IFS= read -r line; do
        if ! grep -q "^${line}" "$config_txt"; then
            echo "$line" >> "$config_txt"
            echo "add string: $line in $config_txt"
        else
            echo "string '$line' already exists in $config_txt"
        fi
    done < "$enable_uart_txt"
}

raspberry_pi4_cmdline_for_nfs() {
    # save original files on first launch
    test -f $1/cmdline.txt.orig || cp $1/cmdline.txt $1/cmdline.txt.orig
    test -f $1/config.txt.orig || cp $1/config.txt $1/config.txt.orig
    # change cmdline.txt and add enable_uart in cmdline.txt
    test -f ${CMDLINE_RPI4} && cp ${CMDLINE_RPI4} $1/cmdline.txt
    # if the IP address NFS is not explicitly set, then by default
    if cat $1/cmdline.txt | grep -q "NFS_IP_ADDRESS"; then
        local default_ip="${IP_TFTP}"
        sed -i "s|NFS_IP_ADDRESS|$default_ip|" $1/cmdline.txt
    fi
    add_lines_to_config_txt "${ENABLE_UART_RPI4}" "$1/config.txt"
}

add_cmdline_for_nfs_raspios() {
    get_mount_base
    if [ -d ${MOUNT_BASE_DIR}/part1 ]; then
        raspberry_pi4_cmdline_for_nfs "${MOUNT_BASE_DIR}/part1"
    fi
}

change_bootloader_name_in_dhcp() {
    [[ -n "$1" ]] || { echo "arg1: bootloader type is missing. Use 'raspberry' or 'pxe'"; return 1; }
    local name_loader
    local dhcp_conf="docker/dhcp_tftp_nfs/etc/dhcp/dhcpd.conf"
    case "$1" in
        "raspberry") name_loader="bootcode.bin" ;;
        "pxe")       name_loader="pxelinux.0"   ;;
        *)           echo "Invalid argument: $1. Allowed: 'raspberry' or 'pxe'"; return 2 ;;
    esac
    
    if cat ${dhcp_conf} | grep -q " option bootfile-name \"$name_loader\""; then
        echo "options $name_loader is already set, skipping ..."; return 0
    fi

    sed -i "s| option bootfile-name \".*\";| option bootfile-name \"$name_loader\";|" "$dhcp_conf"
    if [ $? -eq 0 ]; then echo "option $name_loader set in file $dhcp_conf"; fi
}

mount_raw_raspios() {
    IMAGE_DIR="${DOWNLOAD_RASPIOS}"
    IMAGE_NAME="2024-11-19-raspios-bookworm-arm64.img"
    MOUNT_DIR="${DOWNLOAD_RASPIOS}/tmp_mount"
    download_raspios
    mount_raw_image
    add_cmdline_for_nfs_raspios
    change_bootloader_name_in_dhcp "raspberry"
}

download_ubuntu() {
    if [ -z "${IMAGE_NAME}" ]; then echo "Error: Set environment variables IMAGE_NAME, exit"; return 1; fi
    mkdir -p "${DOWNLOAD_UBUNTU}"
    download_files "${DOWNLOAD_UBUNTU}" "${IMAGE_UBUNTU_URL}" "${IMAGE_NAME}"
    return $?
}

download_kali() {
    if [ -z "${IMAGE_NAME}" ]; then echo "Error: Set environment variables IMAGE_NAME, exit"; return 1; fi
    mkdir -p "${DOWNLOAD_KALI}"
    download_files "${DOWNLOAD_KALI}" "${IMAGE_KALI_URL}" "${IMAGE_NAME}"
    return $?
}

download_netboot() {
    local download="$1"
    local base_url="$2"
    local netboot="${download}/netboot"
    local file="netboot.tar.gz"
    [[ -n "$3" ]] && file="$3"

    download_files "${download}" "$base_url" "${file}"
    [[ $? -ne 0 ]] && return 1
    [[ -d "${netboot}" ]] && { echo "dir ${netboot} already exists, skipping ..."; return 0; }

    mkdir -p "${netboot}"
    extract_tar_archive "${download}/${file}" "${netboot}"
    local ret=$?
    [[ $ret -ne 0 ]] && return 2

    local cfg_default=${netboot}/pxelinux.cfg/default
    save_orig "${cfg_default}" "off_symlink"
    return $ret
}

download_netboot_ubuntu() {
    local download_dir="${DOWNLOAD_UBUNTU}"
    local base_url="http://archive.ubuntu.com/ubuntu/dists/bionic-updates/main/installer-amd64/current/images/netboot"
    download_netboot "${download_dir}" "${base_url}"
    return $?
}

download_netboot_kali() {
    local download_dir="${DOWNLOAD_KALI}"
    local base_url="https://http.kali.org/kali/dists/kali-rolling/main/installer-amd64/current/images/netboot"
    download_netboot "${download_dir}" "${base_url}"
    return $?
}

add_menu_item_netboot() {
    local target_file="$1"
    local template_file="$2"
    test -f "${target_file}.orig" || return 1
    test -f "${template_file}" || return 2
    [[ -n "${IMAGE_NAME_SHORT}" ]] || return 3

    cp "${target_file}.orig" "${target_file}"
    cat "${template_file}" >> "${target_file}"
    # if template parameters are not explicitly specified, then by default
    if cat "${target_file}" | grep -q "NFS_IP_ADDRESS"; then
        local default_ip="${IP_TFTP}"
        sed -i "s|NFS_IP_ADDRESS|$default_ip|" "${target_file}"
    fi
    if cat "${target_file}" | grep -q "IMAGE_NAME"; then
        sed -i "s|IMAGE_NAME|${IMAGE_NAME_SHORT}|g" "${target_file}"
    fi
    sed -i "s|timeout 0|timeout 50|" "${target_file}"
}

add_menu_item_ubuntu_to_pxe() {
    local target_file=${DOWNLOAD_UBUNTU}/netboot/pxelinux.cfg/default
    test -f "${target_file}.orig" || return 1
    test -f "${MENU_ITEM_UBUNTU}" || return 2
    [[ -n "${IMAGE_NAME_SHORT}" ]] || return 3

    cp "${target_file}.orig" "${target_file}"
    cat "${MENU_ITEM_UBUNTU}" >> "${target_file}"
    # if template parameters are not explicitly specified, then by default
    if cat "${target_file}" | grep -q "NFS_IP_ADDRESS"; then
        local default_ip="${IP_TFTP}"
        sed -i "s|NFS_IP_ADDRESS|$default_ip|" "${target_file}"
    fi
    if cat "${target_file}" | grep -q "IMAGE_NAME"; then
        sed -i "s|IMAGE_NAME|${IMAGE_NAME_SHORT}|g" "${target_file}"
    fi
    sed -i "s|timeout 0|timeout 50|" "${target_file}"
}

initrd_and_kernel_to_netboot() {
    get_mount_base
    local kernel_file="$1"
    local initrd_file="$2"
    local netboot_dir="$3"
    test -f "${kernel_file}" || return 1
    test -f "${initrd_file}" || return 2
    [[ -n "${IMAGE_NAME}" ]] || return 3
    test -d "${netboot_dir}" || return 4

    local target_dir="${netboot_dir}/${IMAGE_NAME_SHORT}"
    mkdir -p "${target_dir}"
    if test -f "${target_dir}/vmlinuz"; then echo "File found: ${target_dir}/vmlinuz, skipping ..."
    else cp "${kernel_file}" "${target_dir}/vmlinuz" && echo "cp ${kernel_file} ${target_dir}/vmlinuz"; fi

    if test -f "${target_dir}/initrd"; then echo "File found: ${target_dir}/initrd, skipping ..."
    else cp "${initrd_file}" "${target_dir}/initrd" && echo "cp ${initrd_file} ${target_dir}/initrd"; fi
}

clean_tmp_mount_dir() {
    local dir_path="$1"
    if [ -d "${dir_path}" ]; then
        if [ -L "${dir_path}" ]; then
            rm -f "${dir_path}"
        else
            if [[ "$(stat -c %u "$dir_path")" -eq 0 ]]; then
                echo "dir => $dir_path owned by root: sudo rm -fr ${dir_path}"
                sudo rm -fr "${dir_path}"
            else
                rm -fr "${dir_path}";
            fi
        fi
    fi
}

create_mount_point_for_docker() {
    local symlink_mount_dir
    [[ -n "$1" ]] || { echo "arg1: name, Use 'tftp' or 'nfs'"; return 1; }
    [[ -n "$2" ]] || { echo "arg2: mount point not set"; return 2; }
    test -d "$2" || { echo "not find mount point $2"; return 3; }
    case "$1" in
        "tftp") symlink_mount_dir="${DOCKER_DIR_MOUNT}/tftp" ;;
        "nfs")  symlink_mount_dir="${DOCKER_DIR_MOUNT}/nfs"  ;;
        *)      echo "Invalid argument: $2. Allowed: 'tftp' or 'nfs'"; return 4 ;;
    esac
    mkdir -p "${DOCKER_DIR_MOUNT}"
    clean_tmp_mount_dir "${symlink_mount_dir}"

    ln -s "$2" "${symlink_mount_dir}"
    if [ $? -eq 0 ]; then echo "create: ln -s $2 ${symlink_mount_dir}"; fi
}

mount_raw_ubuntu() {
    IMAGE_DIR="${DOWNLOAD_UBUNTU}"
    MOUNT_DIR="${DOWNLOAD_UBUNTU}/tmp_mount"
    download_ubuntu || return 1
    download_netboot_ubuntu || return 2
    mount_raw_image || return 3

    local pxe_default="${DOWNLOAD_UBUNTU}/netboot/pxelinux.cfg/default"
    local kernel="${MOUNT_BASE_DIR}/part1/casper/vmlinuz"
    local initrd="${MOUNT_BASE_DIR}/part1/casper/initrd"
    local netboot="${DOWNLOAD_UBUNTU}/netboot"
    add_menu_item_netboot "${pxe_default}"  "${MENU_ITEM_UBUNTU}"
    initrd_and_kernel_to_netboot "${kernel}" "${initrd}" "${netboot}"
    docker_dhcp_tftp_reconfig_net
    change_bootloader_name_in_dhcp "pxe"
    create_mount_point_for_docker "tftp" "${netboot}"
    create_mount_point_for_docker "nfs" "${MOUNT_BASE_DIR}/part1"
}

check_bz2_archive() {
    [[ "$1" =~ \.bz2$ ]] && return 0
    return 1
}

extract_bz_archive() {
    local path_name="$1"
    local out_dir="$2"
    local out_name="$3"
    local out_file=${out_dir}/${out_name}
    test -d "${out_dir}" || return 1;
    test -f "${out_file}" && {  echo "extract file ${out_file} already exists, skipping ..."; return 2; }
    bzip2 -dkc "${path_name}" > "${out_file}"
}

extract_tar_archive() {
    local archive="$1"
    local out_dir="$2"
    mkdir -p "$out_dir"

    tar -xzf "$archive" -C "$out_dir"
    [[ $? -ne 0 ]] && { echo "Error: tar -xzf $archive -C $out_dir"; return 1; }
    echo "Success! tar -xzf $archive -C $out_dir"
}

delete_image_bz2() {
    local path_img="$1"
    [[ -f "${path_img}" ]] || return 1

    echo "Delete ${path_img} image?"
    read -p "Unsaved changes will be lost (yes/no):" flag_delete
    if [ "$flag_delete" = "yes" ]; then rm "${path_img}"; return $?
    else echo "exiting ..."; return 2; fi
}

set_env_raw_rpi4() {
    if find_name_image && select_yocto_image; then
        IMAGE_NAME="${IMAGE_SEL}"
        IMAGE_DIR="${YO_DIR_IMAGE}/${YO_M}"
        MOUNT_DIR="${IMAGE_DIR}/tmp_mount"
        if check_bz2_archive "${IMAGE_SEL}"; then
            mkdir -p "${MOUNT_DIR}"
            IMAGE_NAME="${IMAGE_SEL%.bz2}"
            extract_bz_archive "${IMAGE_DIR}/${IMAGE_SEL}" "${MOUNT_DIR}" "${IMAGE_NAME}"
            IMAGE_DIR="${MOUNT_DIR}"
        fi
        return 0
    fi
    return 1
}

mount_raw_rpi4() {
    if ! set_env_raw_rpi4; then return 1; fi

    mount_raw_image
    change_bootloader_name_in_dhcp "raspberry"
    raspberry_pi4_cmdline_for_nfs "${MOUNT_BASE_DIR}/part1"
    create_mount_point_for_docker "tftp" "${MOUNT_BASE_DIR}/part1"
    create_mount_point_for_docker "nfs" "${MOUNT_BASE_DIR}/part2"
    # problem with video adapter: used fake kms (old driver)
    sed -i "s|^dtoverlay=vc4-kms-v3d|#&\n dtoverlay=vc4-fkms-v3d|g" "${MOUNT_BASE_DIR}/part1/config.txt"
}

umount_raw_rpi4() {
    if ! set_env_raw_rpi4; then return 1; fi

    umount_raw_image
    if check_bz2_archive "${IMAGE_SEL}"; then
        delete_image_bz2 "${MOUNT_DIR}/${IMAGE_NAME}"
    fi
}

example_yocto_demo_minimal_rpi4() {
    local proj_demo="${YO_DIR_PROJECTS}/yocto-demo-minimal"
    mkdir -p "${proj_demo}"
    cd ${proj_demo}
    repo init -u https://github.com/berserktv/bs-manifest -m raspberry/scarthgap/yocto-demo-minimal.xml
    repo sync
    # first start (create build)
    ./shell.sh
    # script for start VSCode
    echo "#!/bin/bash" > start-vscode.sh
    echo "cd sources/meta-raspberrypi" >> start-vscode.sh
    echo "code ." >> start-vscode.sh
    chmod u+x start-vscode.sh
    # start new VSCode instance
    cd sources/meta-raspberrypi
    git clone https://github.com/berserktv/vscode-yocto-helper.git .vscode
    # rm -fr .vscode/.git
    code .
}

start_netboot_rpi4() {
    mount_raw_rpi4
    DOCKER_DIR='docker/dhcp_tftp_nfs'
    start_session_docker
}

stop_docker() {
    local docker_name_tag="$1"
    local hash=$(docker ps -aq --filter "ancestor=${docker_name_tag}")
    [[ $? -eq 0 ]] && docker stop "${hash}"
}

start_ubuntu_24_04() {
    #IMAGE_NAME="ubuntu-22.04.1-desktop-amd64.iso"
    IMAGE_NAME="ubuntu-24.04.2-desktop-amd64.iso"
    IMAGE_UBUNTU_URL="http://releases.ubuntu.com/24.04.2"
    DOCKER_DIR='docker/dhcp_tftp_nfs'
    stop_docker "dhcp_tftp_nfs:buster-slim"
    mount_raw_ubuntu && start_session_docker
}

save_orig() {
    local file="$1"
    local flag=0
    [[ -f "${file}.orig" ]] || { cp "${file}" "${file}.orig" && echo "first save: ${file} => ${file}.orig"; flag=1; }
    [[ -z "$2" ]] && return 0

    if [ "$2" == "off_symlink" ]; then
        # first save
        [[ "$flag" == "1" && -L "${file}" ]] && mv "${file}" "${file}.off"
    fi
}

restore_orig() {
    local file="$1"
    [[ -f "${file}" ]] && cp "${file}" "${file}.old" && echo "Save: ${file} => ${file}.old"
    [[ -f "${file}.orig" ]] && cp "${file}.orig" "${file}" && echo "Restore: ${file}.orig => ${file}"
}

restore_image_rpi4() {
    if ! set_env_raw_rpi4; then return 1; fi

    mount_raw_image
    local mount_dir="${MOUNT_BASE_DIR}/part1"
    for file in config.txt cmdline.txt; do
        restore_orig "${mount_dir}/${file}"
    done
    umount_raw_image
}

mount_raw_kali() {
    IMAGE_DIR="${DOWNLOAD_KALI}"
    IMAGE_NAME="kali-linux-2024.4-installer-amd64.iso"
    MOUNT_DIR="${DOWNLOAD_KALI}/tmp_mount"
    download_kali || return 1
    download_netboot_kali || return 2
    mount_raw_image || return 3

    local pxe_default="${DOWNLOAD_KALI}/netboot/pxelinux.cfg/default"
    local kernel="${MOUNT_BASE_DIR}/part1/install.amd/vmlinuz"
    local initrd="${MOUNT_BASE_DIR}/part1/install.amd/initrd.gz"
    local netboot="${DOWNLOAD_KALI}/netboot"
    add_menu_item_netboot "${pxe_default}" "${MENU_ITEM_UBUNTU}"
    initrd_and_kernel_to_netboot "${kernel}" "${initrd}" "${netboot}"
    docker_dhcp_tftp_reconfig_net
    change_bootloader_name_in_dhcp "pxe"
    create_mount_point_for_docker "tftp" "${netboot}"
    create_mount_point_for_docker "nfs" "${MOUNT_BASE_DIR}/part1"
}

start_kali_24_4() {
    IMAGE_NAME="kali-linux-2024.4-installer-amd64.iso"
    IMAGE_KALI_URL="https://cdimage.kali.org/kali-2024.4"
    DOCKER_DIR='docker/dhcp_tftp_nfs'
    stop_docker "dhcp_tftp_nfs:buster-slim"
    mount_raw_kali && start_session_docker
}
