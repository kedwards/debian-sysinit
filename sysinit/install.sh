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
  script_dir="$(dirname "$(realpath "$0")")"
fi

cleanup() {
  if command -v deactivate >/dev/null; then
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
    uv venv --clear
    # shellcheck disable=SC1091
    source ".venv/bin/activate"
    uv pip install -e .
  else
    # shellcheck disable=SC1091
    source ".venv/bin/activate"
  fi
}

# Run ansible playbook
run_ansible() {
  ansible-playbook playbook.yml \
    -K \
    --ask-vault-pass \
    -e "git_user_name=${GIT_USER_NAME}" \
    -e "git_user_email=${GIT_USER_EMAIL}" \
    -e "git_signing_key=${GIT_SIGNING_KEY}"
}

# Check and collect required Git configuration
setup_git_config() {
  echo "Checking Git configuration..."

  # Check for environment variables first
  GIT_USER_NAME="${GIT_USER_NAME:-$(git config --global user.name 2>/dev/null || true)}"
  GIT_USER_EMAIL="${GIT_USER_EMAIL:-$(git config --global user.email 2>/dev/null || true)}"
  GIT_SIGNING_KEY="${GIT_SIGNING_KEY:-$(git config --global user.signingkey 2>/dev/null || true)}"

  # Prompt for missing required values
  if [ -z "$GIT_USER_NAME" ]; then
    read -p "Enter your Git user name: " GIT_USER_NAME
  fi

  if [ -z "$GIT_USER_EMAIL" ]; then
    read -p "Enter your Git email: " GIT_USER_EMAIL
  fi

  # Signing key is optional
  if [ -z "$GIT_SIGNING_KEY" ]; then
    read -p "Enter your Git signing key (optional, press Enter to skip): " GIT_SIGNING_KEY
  fi

  # Validate required fields
  if [ -z "$GIT_USER_NAME" ] || [ -z "$GIT_USER_EMAIL" ]; then
    echo "Error: Git user name and email are required"
    exit 1
  fi

  # Export for use in ansible
  export GIT_USER_NAME
  export GIT_USER_EMAIL
  export GIT_SIGNING_KEY

  echo "Git configuration set:"
  echo "  Name: $GIT_USER_NAME"
  echo "  Email: $GIT_USER_EMAIL"
  echo "  Signing Key: ${GIT_SIGNING_KEY:-<not set>}"
}

# Setup SSH agent for GitHub access
setup_ssh_agent() {
  local ssh_env="$HOME/.ssh/agent-env"

  echo "Setting up SSH agent for Ansible..."

  # Ensure .ssh directory exists
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  # Kill any existing ssh-agent if running
  if [ -f "$ssh_env" ]; then
    source "$ssh_env" >/dev/null 2>&1 || true
    if [ -n "${SSH_AGENT_PID:-}" ] && kill -0 "$SSH_AGENT_PID" 2>/dev/null; then
      echo "Killing existing SSH agent (PID: $SSH_AGENT_PID)"
      kill "$SSH_AGENT_PID" 2>/dev/null || true
    fi
  fi

  # Start fresh SSH agent
  echo "Starting new SSH agent..."
  ssh-agent > "$ssh_env"
  chmod 600 "$ssh_env"
  
  # Source the agent environment
  # shellcheck disable=SC1090
  source "$ssh_env" >/dev/null
  
  # Verify agent is running
  if [ -z "${SSH_AGENT_PID:-}" ] || ! kill -0 "$SSH_AGENT_PID" 2>/dev/null; then
    echo "Error: Failed to start SSH agent"
    exit 1
  fi
  
  echo "SSH agent started (PID: $SSH_AGENT_PID)"

  # Look for SSH keys to add
  local keys_found=false
  local keys_added=false
  
  for key in ~/.ssh/id_rsa ~/.ssh/id_ed25519 ~/.ssh/id_ecdsa; do
    if [ -f "$key" ]; then
      keys_found=true
      echo "Found SSH key: $key"
      
      # Check if key is encrypted
      if grep -q "ENCRYPTED" "$key" 2>/dev/null; then
        echo "Key $key is encrypted, prompting for passphrase..."
      fi
      
      # Try to add the key
      if ssh-add "$key" 2>/dev/null; then
        echo "Successfully added $key"
        keys_added=true
        break
      else
        echo "Failed to add $key (may need passphrase or key is invalid)"
      fi
    fi
  done

  # Check if any keys were found
  if [ "$keys_found" = false ]; then
    echo "No SSH keys found in ~/.ssh/"
    echo "Please generate an SSH key pair:"
    echo "  ssh-keygen -t ed25519 -C \"your_email@example.com\""
    echo "Then run this script again."
    exit 1
  fi

  # Check if any keys were successfully added
  if [ "$keys_added" = false ]; then
    echo "No SSH keys could be loaded. This might be due to:"
    echo "  - Encrypted keys requiring passphrase"
    echo "  - Invalid or corrupted key files"
    echo "  - Permission issues"
    echo ""
    echo "Please manually add your key:"
    echo "  source $ssh_env"
    echo "  ssh-add ~/.ssh/id_ed25519  # or your key file"
    echo "Then run this script again."
    exit 1
  fi

  # Verify keys are loaded
  echo "Loaded SSH keys:"
  ssh-add -l

  # Export environment for Ansible
  export SSH_AUTH_SOCK
  export SSH_AGENT_PID
  
  # Also export to a file that can be sourced later
  cat > "$HOME/.ssh/current-agent" << EOF
export SSH_AUTH_SOCK="$SSH_AUTH_SOCK"
export SSH_AGENT_PID="$SSH_AGENT_PID"
EOF
  chmod 600 "$HOME/.ssh/current-agent"
}

# Main execution with better error handling
main() {
  install_packages
  install_mise
  # sync_repo
  # setup_git_config
  # setup_ssh_agent
  setup_python_env
  run_ansible
}

# Run main function
main "$@"
