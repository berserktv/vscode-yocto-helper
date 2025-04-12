#!/bin/bash

DIR_INSTALL="$HOME/yocto/vscode-yocto-helper"

sudo apt install -y snap
sudo snap install --classic code
code --install-extension seunlanlege.action-buttons

sudo apt-get update
sudo apt install -y expect git repo make
sudo apt install -y docker.io

sudo usermod -aG docker $USER
sudo usermod -aG dialout $USER
exec su - $USER

mkdir -p "${DIR_INSTALL}"
cd "${DIR_INSTALL}"

git clone https://github.com/berserktv/vscode-yocto-helper.git .vscode
code .




