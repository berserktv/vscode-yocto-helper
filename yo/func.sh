#!/bin/bash

# корневой каталог yocto, где будет располагаться каталог build, относительно текущего каталога
YO_R="../.."
YO_M=`cat $YO_R/build/conf/local.conf | grep "^MACHINE " | cut -d"'" -f2`
YO_DIR_IMAGE="$YO_R/build/tmp/deploy/images"
YO_IMAGE_NAME=""
YO_EXT=".wic .rootfs.wic .rpi-sdimg .wic.bz2"
LI_DISK=""

# общие функции для работы с IDE vscode
IP_COMP="192.168.0.1"
USER_COMP="user"
KEY_ID="computer_id_rsa"
gen_send_ssh_key() {
    ssh-keygen -t rsa -q -N '' -f ~/.ssh/${KEY_ID}
    ssh-copy-id -i ~/.ssh/${KEY_ID}.pub ${USER_COMP}@${IP_COMP}
    ##if [ "$1" == "manual" ]; then # manual copy pub key
    ##    scp ~/.ssh/${KEY_ID}.pub ${USER_COMP}@${IP_COMP}:/home/${USER_COMP}/.ssh/authorized_keys
    ##fi    
}

CONTAINER_ID=""
CONTAINER_NAME=""
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

ALGORITMS="HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa"
ssh_config_add_negotiate() {
    if [ -z "$1" ]; then echo "error: ssh_config_add_negotiate(), arg1 IP address ..."; return 1; fi
    if ! cat ~/.ssh/config | grep -q "$1"; then
        echo "Host $1" >> ~/.ssh/config
        echo "  User ${USER_COMP}"
        echo "  HostkeyAlgorithms +ssh-rsa" >> ~/.ssh/config
        echo "  PubkeyAcceptedAlgorithms +ssh-rsa" >> ~/.ssh/config
    fi
}
