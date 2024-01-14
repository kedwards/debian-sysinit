#!/bin/bash

trap cleanup ERR EXIT

cleanup() {
  if command -v deactivate &> /dev/null; then
  	deactivate
 	rm -fr $HOME/.sysinit
  fi
}

SYSINIT_PATH=$HOME/sysinit
RELEASE=$(cat /etc/os-release | grep '^ID=' | awk '{ split($0, a, "="); print a[2]}')
CODENAME=$(lsb_release -cs)

(sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y) || exit 1

sudo apt install git python3-venv -y

if [ ! -d $HOME/.sysinit ]; then
  python3 -m venv $HOME/.sysinit
fi
. $HOME/.sysinit/bin/activate

[ -d "${SYSINIT_PATH}" ] || git clone -b main --single-branch https://github.com/kedwards/sysinit.git "$SYSINIT_PATH"

pip install -r "${SYSINIT_PATH}/requirements.txt"

ansible-playbook "${SYSINIT_PATH}/playbook.yml" -K --ask-vault-pass --tags system

