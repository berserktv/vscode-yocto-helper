#!/bin/bash

DIR_INSTALL="$HOME/yocto/vscode-yocto-helper"

sudo apt install -y snap
sudo snap install --classic code
code --install-extension seunlanlege.action-buttons

sudo apt-get update
sudo apt install -y expect git repo
sudo apt install -y docker.io

sudo usermod -aG docker $USER
newgrp docker

mkdir -p "${DIR_INSTALL}"
cd "${DIR_INSTALL}"

git clone https://github.com/berserktv/vscode-yocto-helper.git .vscode
code .




