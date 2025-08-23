#!/bin/bash

DIR_INSTALL="$HOME/yocto/vscode-yocto-helper"

sudo apt install -y snap || sudo apt install -y snapd
sudo snap install --classic code
code --install-extension seunlanlege.action-buttons

sudo apt-get update
sudo apt install -y docker.io

sudo usermod -aG docker $USER

mkdir -p "${DIR_INSTALL}"
cd "${DIR_INSTALL}"
git clone -b RaspbianLoader https://github.com/berserktv/vscode-yocto-helper.git .vscode

echo ""
echo "Important: Docker group changes require a new login session to take effect."
echo "You must fully log out and log back in after installation!"
echo ""
echo "Project will be installed to: ${DIR_INSTALL}"
echo ""

read -p "Reboot system? (yes/no): " flag
if [ "$flag" = "yes" ]; then
    reboot
fi
