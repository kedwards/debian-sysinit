#!/bin/bash

SYSINIT_PATH=$HOME/sysinit

trap cleanup ERR EXIT

cleanup() {
  if command -v deactivate &> /dev/null; then
    deactivate
  fi
}

. /etc/os-release

if [ "$ID" = "debian" ];
then
  sudo sh -c "apt-get update; apt-get upgrade -y; apt-get install curl git; apt autoremove -y"
else
  sudo sh -c "echo 'yes' | pacman -S curl git"
fi

curl -LsSf https://astral.sh/uv/install.sh | sh
source "$HOME/.cargo/env"

if [ ! -d "$HOME/.venv/sysinit" ]; then
  uv venv "$HOME/.venv/sysinit"
fi
source "$HOME/.venv/sysinit/bin/activate"

if [ -d "${SYSINIT_PATH}" ]; then
  git -C "${SYSINIT_PATH}" pull
else
  git clone -b main --single-branch https://github.com/kedwards/sysinit.git "$SYSINIT_PATH"
fi

uv pip install -r "${SYSINIT_PATH}/requirements.txt"

cd "${SYSINIT_PATH}" || exit 1
ansible-playbook playbook.yml -K --ask-vault-pass -e apps='["mise"]'

if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi
