#!/bin/bash

# корневой каталог yocto, где будет располагаться каталог build, относительно текущего каталога
YO_R="../.."
find_setup_env() {
    if [ -f "${YO_R}/setup-environment" ]; then return 0; fi
    local tmp_path=".."
    for i in {1..7}; do
        if [ -f "${tmp_path}/setup-environment" ]; then
            YO_R="${tmp_path}"
            return 0;
        fi
        tmp_path="${tmp_path}/.."
    done
    echo "error: 'setup-environment' not found in parent directories, env: 'YO_R' wrong path ..."; return 1
}
find_setup_env

YO_M=`cat $YO_R/build/conf/local.conf | grep "^MACHINE " | cut -d"'" -f2`
YO_DIR_IMAGE="$YO_R/build/tmp/deploy/images"
YO_IMAGE_NAME=""
YO_EXT=".wic .rootfs.wic .rpi-sdimg .wic.bz2"
LI_DISK=""
IP_COMP="192.168.0.1"
USER_COMP="user"
KEY_ID="computer_id_rsa"
CONTAINER_ID=""
CONTAINER_NAME=""
DOCKER_DIR=""
IMAGE_NAME="core-image-minimal-raspberrypi4.rpi-sdimg"
MOUNT_DIR="${YO_DIR_IMAGE}/tmp_mount"
DOWNLOAD_DIR="$HOME/distrib"

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

start_cmd_docker() {
    if [ -z "$1" ]; then
        echo "error: start_cmd_docker(), arg1 command name empty ..."
        return 1;
    fi

    local cmd_args=$1
    local curdir=$(pwd)
    cd $DOCKER_DIR
    if ! find_docker_id; then
        make run_detach
        if ! find_docker_id; then
            echo "failed to start container => make run_detach ..."
            cd $curdir
            return 2;
        fi
    fi

    echo "docker exec -it ${CONTAINER_ID} bash -c \"$cmd_args\""
    docker exec -it ${CONTAINER_ID} bash -c "$cmd_args"
    cd $curdir
}

start_session_docker() {
    local curdir=$(pwd)
    cd $DOCKER_DIR
    make run
    cd $curdir
}

find_name_image() {
    IFS=$' '
    if [ -z "$YO_M" ]; then echo "MACHINE variable not found"; return -1; fi

    for ext in ${YO_EXT}; do
        local find_str=$(ls -1 ${YO_DIR_IMAGE}/${YO_M} | grep "${YO_M}${ext}$")
        if [ -z "$find_str" ]; then
            echo "NAME IMAGE ${ext} is not found => ${YO_DIR_IMAGE}/${YO_M}"
        else 
            YO_IMAGE_NAME="$YO_IMAGE_NAME $find_str"
            echo "find: YO_IMAGE_NAME=$YO_IMAGE_NAME"
        fi
    done

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
    else echo "not find SD card => exit..."; return 1; fi
}

select_dd_info() {
    local j=1
    IFS=$' '
    for i in $LI_DISK; do
        for image in $YO_IMAGE_NAME; do
            if echo "$image" | grep -q ".wic.bz2"; then 
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
                if echo "$image" | grep -q ".wic.bz2"; then 
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
# SERIAL_CONSOLES = "115200;ttyAMA0"; SERIAL_CONSOLES_CHECK = "ttyAMA0:ttyS0" => /etc/inittab
start_qemu_rpi3_64() {
    local curdir=$(pwd)
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
    cd $curdir
}

MOUNT_BASE_DIR=""
get_mount_base() {
    local name_without_ext="${IMAGE_NAME%.*}"
    MOUNT_BASE_DIR="${MOUNT_DIR}/${name_without_ext}"
}

mount_raw_image() {
    find_name_image
    if [[ -z "${YO_DIR_IMAGE}" || -z "${IMAGE_NAME}" || -z "${MOUNT_DIR}" ]]; then
        echo "Error: Set environment variables YO_DIR_IMAGE, IMAGE_NAME, and MOUNT_DIR" >&2
        return 1
    fi

    local image_file="${YO_DIR_IMAGE}/${IMAGE_NAME}"
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
    test -d ${MOUNT_BASE_DIR} || sudo mkdir -p ${MOUNT_BASE_DIR}

    for part_num in {1..4}; do
        local partition="${loop_dev}p${part_num}"
        if [[ -b "${partition}" ]]; then
            local mount_point="${MOUNT_BASE_DIR}/part${part_num}"
            if mountpoint -q "${mount_point}"; then
                echo "Partition ${part_num} is already mounted at ${mount_point}, skipping..."
                continue
            fi

            sudo mkdir -p "${mount_point}"
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
    if [[ -z "${IMAGE_NAME}" || -z "${MOUNT_DIR}" ]]; then
        echo "Error: Set environment variables IMAGE_NAME, and MOUNT_DIR, exit ..." >&2; return 1
    fi

    get_mount_base
    local name_without_ext="${IMAGE_NAME%.*}"
    if [ ! -d ${MOUNT_BASE_DIR} ]; then
        echo "Error: not find ${MOUNT_BASE_DIR}, exit ..." >&2; return 2
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

    local image_file="${YO_DIR_IMAGE}/${IMAGE_NAME}"
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


download_raspios() {
    # arg1 - select version
    test -d "${DOWNLOAD_DIR}/raspios" || mkdir -p "${DOWNLOAD_DIR}/raspios"
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
    if [ -f "${DOWNLOAD_DIR}/raspios/${extracted_file}" ]; then
        echo "File already exists: ${DOWNLOAD_DIR}/raspios/${extracted_file}, skipping ..."; return
    fi

    local download_url="${url}${selected_dir}${selected_file}"
    echo "Downloading file: $selected_file"
    wget -P "${DOWNLOAD_DIR}/raspios" "$download_url"
    if [ $? -ne 0 ]; then echo "Error: Failed to download the file."; return 3
    else echo "Download completed successfully"; fi

    local downloaded_file="${DOWNLOAD_DIR}/raspios/${selected_file}"
    echo "Extracting XZ archive..."
    xz -d "$downloaded_file"
}

raspberry_pi4_cmdline_for_nfs() {
test -f $1/cmdline.txt.orig || cp $1/cmdline.txt $1/cmdline.txt.orig
cat <<-EOF > $1/cmdline.txt
    console=serial0,115200 console=tty1 root=/dev/nfs nfsroot=10.0.7.1:/nfs,hard,nolock rw ip=dhcp rootwait
EOF
}

add_cmdline_for_nfs_raspios() {
    get_mount_base
    if [ -d ${MOUNT_BASE_DIR}/part1 ]; then
        raspberry_pi4_cmdline_for_nfs "${MOUNT_BASE_DIR}/part1"
    fi
}

test_raw_raspios() {
    YO_DIR_IMAGE="${DOWNLOAD_DIR}/raspios"
    IMAGE_NAME="2024-11-19-raspios-bookworm-arm64.img"
    MOUNT_DIR="${YO_DIR_IMAGE}/tmp_mount"
    download_raspios
    mount_raw_image
    add_cmdline_for_nfs_raspios
}
