#!/bin/bash

DIR_INSTALL="$HOME/yocto/vscode-yocto-helper"
install_repo() {
    sudo apt install -y repo && return 0

    sudo curl -o /usr/local/bin/repo \
         https://commondatastorage.googleapis.com/git-repo-downloads/repo \
    && sudo chmod a+x /usr/local/bin/repo
}

sudo apt install -y snap || sudo apt install -y snapd
sudo snap install --classic code
code --install-extension seunlanlege.action-buttons

sudo apt-get update
install_repo
sudo apt install -y expect git picocom make
sudo apt install -y docker.io

sudo usermod -aG docker $USER
sudo usermod -aG dialout $USER

mkdir -p "${DIR_INSTALL}"
cd "${DIR_INSTALL}"
git clone https://github.com/berserktv/vscode-yocto-helper.git .vscode

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
