#!/bin/bash

FIND_STR=$(grep -m1 "^DIR_INSTALL=" "./install.sh")
if [ -n "${FIND_STR}" ]; then
    DIR_INSTALL=$(echo "${FIND_STR}" | cut -d'"' -f2 | envsubst)
    if [[ -n "${DIR_INSTALL}" && -d "${DIR_INSTALL}" ]]; then
        read -p "Delete project ${DIR_INSTALL} directory? (yes/no):" flag
        if [ "$flag" = "yes" ]; then
            rm -rf "${DIR_INSTALL}"
        fi
    fi
fi

read -p "Remove Docker? (yes/no):" flag
if [ "$flag" = "yes" ]; then
    echo "sudo systemctl stop docker.socket docker"
    sudo systemctl stop docker.socket docker
    echo "sudo apt-get purge -y docker.io"
    sudo apt-get purge -y docker.io
    echo "Updating user groups..."
    sudo gpasswd -d "${USER}" docker
    sudo gpasswd -d "${USER}" dialout
    echo "sudo groupdel docker"
    sudo groupdel docker
fi

read -p "Removing development tools: expect git repo make? (yes/no):" flag
if [ "$flag" = "yes" ]; then
    echo "sudo apt-get purge -y expect repo git make"
    sudo apt-get purge -y expect repo git make
fi

read -p "Removing VSCode? (yes/no):" flag
if [ "$flag" = "yes" ]; then
    echo "sudo snap remove code"
    sudo snap remove code
fi

read -p "Removing snap? (yes/no):" flag
if [ "$flag" = "yes" ]; then
    echo "sudo apt-get purge snap"
    sudo apt-get purge snap || sudo apt-get purge snapd
fi
