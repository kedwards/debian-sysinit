#!/bin/bash

sysinit_path="$HOME/sysinit"
packages="curl git"

trap cleanup ERR EXIT

cleanup() {
  if command -v deactivate &>/dev/null; then
    deactivate
  fi
}

function getPackageManager() {
  local pm;

  declare -A osInfo;
  osInfo[/etc/redhat-release]=yum
  osInfo[/etc/arch-release]=pacman
  osInfo[/etc/debian_version]=apt-get

  for f in "${!osInfo[@]}"
  do
    if [[ -f $f ]]; then
      pm="${osInfo[$f]}"
    fi
  done
  echo "$pm"
}

case $(getPackageManager) in
  "apt-get")
    sudo sh -c "apt-get update; apt-get upgrade -y; apt-get install $packages -y; apt autoremove -y"
    ;;
  "pacman")
    sudo sh -c "pacman -Syu; echo 'yes' | pacman -S --noconfirm $packages"
    ;;
  "yum")
    sudo ish -c "yum update; yum install -y $packages"
    ;;
  *)
    echo "Unsupported package manager"
    exit 1
    ;;
esac

curl https://mise.run | sh
eval "$(~/.local/bin/mise activate bash)"
mise use --global uv

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
ansible-playbook playbook.yml -k --ask-vault-pass
