#!/bin/bash

CURDIR=$(pwd)
DOCKER_DIR=""
DOCKER_DIR_MOUNT="/tmp/docker"
DOCKER_DHCP_TFTP="docker/dhcp_tftp_nfs"
IP_TFTP="10.0.7.1"
IMAGE_NAME=""
IMAGE_DIR=""
IMAGE_SEL=""
MOUNT_DIR=""
DOWNLOAD_DIR="$HOME/distrib"
DOWNLOAD_RASPIOS="${DOWNLOAD_DIR}/raspios"
CMDLINE_RPI4="docker/dhcp_tftp_nfs/rpi/cmdline.txt"
ENABLE_UART_RPI4="docker/dhcp_tftp_nfs/rpi/enable_uart.txt"
# Repository of this project: https://github.com/berserktv/vscode-yocto-helper
# This project is licensed under the MIT License. autor: Alexander Demachev. See the [LICENSE.MIT]

# общие функции для работы с IDE vscode
docker_dhcp_tftp_reconfig_net() {
    cd "${DOCKER_DHCP_TFTP}"
    ./reconfig_net.sh
    cd "${CURDIR}"
}

start_session_docker() {
    cd "${DOCKER_DIR}"
    make build && make run
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
    sync
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

start_netboot_rpi4() {
    DOCKER_DIR='docker/dhcp_tftp_nfs'
    stop_docker "dhcp_tftp_nfs:buster-slim"
    mount_raw_rpi4 && start_session_docker
}

set_env_raw_raspios() {
    IMAGE_DIR="${DOWNLOAD_RASPIOS}"
    #IMAGE_NAME="2024-11-19-raspios-bookworm-arm64.img"
    IMAGE_NAME="2025-05-13-raspios-bookworm-arm64.img"
    MOUNT_DIR="${DOWNLOAD_RASPIOS}/tmp_mount"
    DOCKER_DIR='docker/dhcp_tftp_nfs'
}

stop_docker() {
    local docker_name_tag="$1"
    local hash=$(docker ps -aq --filter "ancestor=${docker_name_tag}")
    [[ $? -eq 0 ]] && docker stop "${hash}"
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

start_netboot_raspios() {
    set_env_raw_raspios
    stop_docker "dhcp_tftp_nfs:buster-slim"
    mount_raw_raspios && start_session_docker
}

