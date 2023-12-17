#!/bin/bash

SYSINIT_PATH=$HOME/sysinit
RELEASE=$(cat /etc/os-release | grep '^ID=' | awk '{ split($0, a, "="); print a[2]}')
CODENAME=$(lsb_release -cs)

(sudo apt update && sudo apt upgrade -y && sudo apt install git python3-venv - && sudo apt autoremove -y) || exit 1
if [ ! -d $HOME/.sysinit ]; then
  python3 -m venv $HOME/.sysinit
fi
. $HOME/.sysinit/bin/activate
[ -d "${SYSINIT_PATH}" ] || git clone -b main --single-branch https://github.com/kedwards/sysinit.git "$SYSINIT_PATH"
pip install -r "${SYSINIT_PATH}/requirements.txt" && ansible-galaxy install -r "${SYSINIT_PATH}/requirements.yml"
ansible-playbook "${SYSINIT_PATH}/playbook.yml" -K --ask-vault-pass --tags system

# AWSVPNClient requires deprecated libssl 1.0
# wget http://snapshot.debian.org/archive/debian/20170705T160707Z/pool/main/o/openssl/libssl1.0.0_1.0.2l-1%7Ebpo8%2B1_amd64.deb
# wget http://snapshot.debian.org/archive/debian/20190501T215844Z/pool/main/g/glibc/multiarch-support_2.28-10_amd64.deb
# sudo dpkg -i multiarch-support*.deb libssl1.0.0*.deb

