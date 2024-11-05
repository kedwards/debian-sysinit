#!/bin/bash

sysinit_path="$HOME/sysinit"
packages="curl git"

trap cleanup ERR EXIT

cleanup() {
  if command -v deactivate &> /dev/null; then
    deactivate
  fi
}

. /etc/os-release

if [ "$ID" = "debian" -o "$ID" = "ubuntu" ];
then
  sudo sh -c "apt-get update; apt-get upgrade -y; apt-get install $packages -y; apt autoremove -y"
elif [ "$ID" = "arch" ]; then
  sudo sh -c "echo 'yes' | pacman -S $packages"
elif [ "$ID" = "rocky" ]; then
  sudo dnf install -y $packages
fi

command -v uv &> /dev/null || curl -LsSf https://astral.sh/uv/install.sh | sh
source "$HOME/.cargo/env"

if [ ! -d "$HOME/.venv/sysinit" ]; then
  uv venv "$HOME/.venv/sysinit"
fi
source "$HOME/.venv/sysinit/bin/activate"

if [ -d "${sysinit_path}" ]; then
  git -C "${sysinit_path}" pull
else
  git clone -b main --single-branch https://github.com/kedwards/sysinit.git "$sysinit_path"
fi

uv pip install -r "${sysinit_path}/requirements.txt"

cd "${sysinit_path}" || exit 1
ansible-playbook playbook.yml -K --ask-vault-pass

if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  mkdir -p "$HOME/.tmux/plugins"
  git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi
