#!/bin/bash

set -euo pipefail

packages="curl git gpg"

if [[ -p /dev/stdin ]] && [[ "${BASH_SOURCE[0]}" == "stdin" ]]; then
  script_dir="$HOME/sysinit"
else
  script_dir="$(dirname "$(realpath "$0")")"
fi

trap cleanup ERR EXIT

cleanup() {
  if command -v deactivate >/dev/null; then
    deactivate
  fi
  sudo rm -rf "$script_dir/.venv" "$mise_installer/mise_install.sh"
}

function getPackageManager() {
  local pm

  declare -A osInfo
  osInfo['/etc/redhat-release']=yum
  osInfo['/etc/arch-release']=pacman
  osInfo['/etc/debian_version']=apt-get

  for f in "${!osInfo[@]}"; do
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

# Install mise
mise_installer=$(mktemp -d)
gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 0x7413A06D
curl https://mise.jdx.dev/install.sh.sig | gpg --decrypt >"$mise_installer/mise_install.sh"
sh "$mise_installer/mise_install.sh"

# Add mise to PATH and activate it
export PATH="$HOME/.local/bin:$PATH"
echo "eval \"\$($HOME/.local/bin/mise activate bash)\"" >>~/.bashrc
eval "$("$HOME"/.local/bin/mise activate bash)"

if [ -d "$script_dir" ]; then
  git -C "$script_dir" pull
else
  git clone -b main --single-branch https://github.com/kedwards/sysinit.git "$script_dir"
fi

# Install uv
cd "$script_dir"
mise trust -a
mise use --global uv
uv venv --clear

# shellcheck disable=SC1091
source ".venv/bin/activate"
uv pip install -e .

ansible-playbook playbook.yml -K --ask-vault-pass
