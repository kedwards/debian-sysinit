#!/bin/bash

SYSINIT_PATH=$HOME/sysinit

trap cleanup ERR EXIT

cleanup() {
  if command -v deactivate &> /dev/null; then
  	deactivate
    rm -fr $HOME/.sysinit
  fi
}

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

(apt update && apt upgrade -y && apt autoremove -y) || exit 1

curl -LsSf https://astral.sh/uv/install.sh | sh
source "$HOME/.cargo/env

uv venv $HOME/.sysinit
source $HOME/.sysinit/bin/activate

if [ -d "${SYSINIT_PATH}" ]; then
  git -C "${SYSINIT_PATH}" pull
else
  git clone -b main --single-branch https://github.com/kedwards/sysinit.git "$SYSINIT_PATH"
fi

uv pip install -r "${SYSINIT_PATH}/requirements.txt"

ansible-playbook "${SYSINIT_PATH}/playbook.yml" -K --ask-vault-pass --tags system
