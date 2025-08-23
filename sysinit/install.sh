#!/bin/bash

set -euo pipefail

SYSINIT_REPO=https://github.com/withreach/sysinit.git

# Determine script directory
if [[ -p /dev/stdin ]]; then
  # If run via stdin (e.g., curl ... | bash)
  script_dir="$HOME/sysinit"
elif [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  # If sourced or run as file
  script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
else
  # Fallback
  script_dir="$(dirname "$(realpath "$0")")"
fi

cleanup() {
  if command -v deactivate >/dev/null 2>&1; then
    deactivate || true
  fi
  # Only clean up temp files, preserve .venv for idempotency
  rm -rf "${mise_installer:-/tmp}/mise_install.sh" || true
}
trap cleanup ERR EXIT

# Detect packages based on os type
get_packages_for_pm() {
  local pm="$1"
  case "$pm" in
  apt-get)
    echo "curl git gpg"
    ;;
  pacman)
    echo "curl git gnupg"
    ;;
  yum)
    echo "curl git gnupg2"
    ;;
  dnf)
    echo "curl git gnupg2 python3-libdnf5"
    ;;
  *)
    echo "curl git gnupg"
    ;;
  esac
}

# Detect package manager
get_package_manager() {
  declare -A os_info=(
    ["/etc/redhat-release"]="yum"
    ["/etc/arch-release"]="pacman"
    ["/etc/debian_version"]="apt"
    ["/etc/fedora-release"]="dnf"
  )
  for f in "${!os_info[@]}"; do
    if [[ -f "$f" ]]; then
      echo "${os_info[$f]}"
      return
    fi
  done
  echo "unknown"
}

# Install required packages
install_packages() {
  local pm
  pm=$(get_package_manager)
  local packages
  packages=$(get_packages_for_pm "$pm")

  case "$pm" in
  apt)
    sudo apt-get update
    sudo apt-get upgrade -y
    sudo apt-get install -y $packages
    sudo apt-get autoremove -y
    ;;
  dnf)
    sudo dnf update -y
    sudo dnf install -y $packages
    ;;
  pacman)
    sudo pacman -Syu --noconfirm
    sudo pacman -S --noconfirm $packages
    ;;
  yum)
    sudo yum update -y
    sudo yum install -y $packages
    ;;
  *)
    echo "Unsupported or unknown package manager"
    exit 1
    ;;
  esac
}

# Install mise and add
# mise to PATH and activate
install_mise() {
  # Check if mise is already installed
  if command -v "$HOME/.local/bin/mise" >/dev/null 2>&1; then
    echo "mise already installed, skipping installation"
    export PATH="$HOME/.local/bin:$PATH"
    eval "$("$HOME/.local/bin/mise" activate bash)"
    return
  fi

  mise_installer="$(mktemp -d)"
  gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 0x7413A06D
  curl https://mise.jdx.dev/install.sh.sig | gpg --decrypt >"$mise_installer/mise_install.sh"
  sh "$mise_installer/mise_install.sh"
  export PATH="$HOME/.local/bin:$PATH"
  
  # Only add to bashrc if not already present
  if ! grep -q "mise activate bash" ~/.bashrc; then
    echo "eval \"\$($HOME/.local/bin/mise activate bash)\"" >>~/.bashrc
  fi
  eval "$("$HOME/.local/bin/mise" activate bash)"
}

# Clone or pull sysinit repo
sync_repo() {
  if [[ -d "$script_dir" ]]; then
    # @TODO: save users changes if any
    git -C "$script_dir" pull
  else
    git clone -b main --single-branch $SYSINIT_REPO "$script_dir"
  fi
}

# Setup and activate virtual environment
# Install required dependencies
setup_python_env() {
  cd "$script_dir"

  # Ensure mise is in PATH and activated
  export PATH="$HOME/.local/bin:$PATH"
  if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)"
  else
    echo "Error: mise not found in PATH"
    exit 1
  fi

  mise trust -a
  mise use --global uv
  eval "$(mise activate bash)"
  export PATH="$HOME/.local/share/mise/shims:$PATH"
  sleep 2
  mise reshim
  
  # Only create venv if it doesn't exist or if sysinit package isn't installed
  if [[ ! -d ".venv" ]] || ! .venv/bin/python -c "import sysinit" 2>/dev/null; then
    echo "Creating/updating virtual environment..."
    uv venv --clear
    # shellcheck disable=SC1091
    source ".venv/bin/activate"
    uv pip install -e .
  else
    echo "Virtual environment exists and sysinit is installed, activating..."
    # shellcheck disable=SC1091
    source ".venv/bin/activate"
  fi
}

# Run ansible playbook
run_ansible() {
  ansible-playbook playbook.yml -K --ask-vault-pass
}

# Main execution with better error handling
main() {
  install_packages
  install_mise
  # sync_repo
  setup_python_env
  run_ansible
}

# Run main function
main "$@"
