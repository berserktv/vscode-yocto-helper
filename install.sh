#!/bin/bash

DIR_INSTALL="$HOME/yocto/vscode-yocto-helper"

sudo apt install -y snap
sudo snap install --classic code
code --install-extension seunlanlege.action-buttons

sudo apt-get update
sudo apt install -y expect git
sudo apt install -y docker.io

# добавление пользователя в группу докер
sudo usermod -aG docker $USER
# применение группы или можно выйти из пользовательской сессии и войти зановог
newgrp docker

mkdir -p "${DIR_INSTALL}"
cd "${DIR_INSTALL}"

git clone https://github.com/berserktv/vscode-yocto-helper.git .vscode
code .




