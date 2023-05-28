#!/usr/bin/env bash

export PATH=~/.local/bin:$PATH

SYSINIT_PATH=~/sysinit
RELEASE=$(cat /etc/os-release | grep '^ID=' | awk '{ split($0, a, "="); print a[2]}')
CODENAME=$(lsb_release -cs)

sudo apt-get install -y git

[ ! -d ~/.pyenv ] && curl https://pyenv.run | bash

[ -d "${SYSINIT_PATH}" ] || git clone -b main --single-branch https://github.com/kedwards/sysinit.git "${SYSINIT_PATH}"
cd ${SYSINIT_PATH}

pip install -r requirements.txt
ansible-galaxy install -r requirements.yml

[ -f /etc/apt/keyrings/docker.gpg ] || curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get autoremove -y

ansible-playbook playbook.yml -K --ask-vault-pass --tags core
