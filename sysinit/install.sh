#!/bin/bash

set -euo pipefail

SYSINIT_REPO="https://github.com/kedwards/sysinit.git"
SCRIPT_DIR="/opt/sysinit"
USER="${USER:-$(whoami)}"

# Default flag values
ENABLE_SSH_SETUP=false
ASK_BECOME_PASS=false

# Display usage information
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Install and configure system using sysinit repository.

OPTIONS:
  -s, --enable-ssh        Enable SSH agent setup (disabled by default)
  -k, --ask-become-pass   Pass -K to ansible-playbook (prompt for sudo password)
  -h, --help              Display this help message

EXAMPLES:
  # Install without SSH setup (default — for ISO/AMI with NOPASSWD sudo)
  $0

  # Install interactively with sudo password prompt
  $0 -k

  # Install with SSH setup enabled
  $0 --enable-ssh -s

  # Download and run with SSH setup enabled
  curl -fsSL https://raw.githubusercontent.com/kedwards/sysinit/main/install-raw.sh | bash -s -- --enable-ssh

EOF
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -s|--enable-ssh)
        ENABLE_SSH_SETUP=true
        shift
        ;;
      -k|--ask-become-pass)
        ASK_BECOME_PASS=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

# Fix ownership of .venv directory and contents
fix_venv_ownership() {
  if [[ -d "$SCRIPT_DIR/.venv" ]]; then
    sudo chown -R "$USER:$USER" "$SCRIPT_DIR/.venv" 2>/dev/null || true
  fi
}

cleanup() {
  if command -v deactivate >/dev/null 2>&1; then
    deactivate || true
  fi
  rm -rf "${mise_installer:-}" || true
  fix_venv_ownership
}
trap cleanup ERR EXIT

# Detect package manager — ordered to handle overlapping release files (e.g. Fedora)
get_package_manager() {
  if [[ -f /etc/fedora-release ]]; then
    echo "dnf"
  elif [[ -f /etc/redhat-release ]]; then
    echo "yum"
  elif [[ -f /etc/debian_version ]]; then
    echo "apt"
  elif [[ -f /etc/arch-release ]]; then
    echo "pacman"
  elif [[ -f /etc/SuSE-release ]]; then
    echo "zypper"
  elif [[ -f /etc/alpine-release ]]; then
    echo "apk"
  else
    echo "unknown"
  fi
}

# Detect packages based on os type
get_packages_for_pm() {
  local pm="$1"
  case "$pm" in
  apt)    echo "curl git gpg" ;;
  pacman) echo "curl git gnupg" ;;
  yum)    echo "curl git gnupg2" ;;
  dnf)    echo "curl git gnupg2 python3-libdnf5" ;;
  zypper) echo "curl git gpg2" ;;
  apk)    echo "curl git gnupg" ;;
  *)      echo "curl git gnupg" ;;
  esac
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
    # shellcheck disable=SC2086
    sudo apt-get install -y $packages
    ;;
  dnf)
    sudo dnf install -y $packages
    ;;
  pacman)
    sudo pacman -Syu --noconfirm
    # shellcheck disable=SC2086
    sudo pacman -S --noconfirm $packages
    ;;
  yum)
    # shellcheck disable=SC2086
    sudo yum install -y $packages
    ;;
  zypper)
    sudo zypper refresh
    # shellcheck disable=SC2086
    sudo zypper install -y $packages
    ;;
  apk)
    sudo apk update
    # shellcheck disable=SC2086
    sudo apk add --no-cache $packages
    ;;
  *)
    echo "Unsupported or unknown package manager"
    exit 1
    ;;
  esac
}

# Install mise to ~/.local/bin and activate
install_mise() {
  local mise_bin="${HOME}/.local/bin/mise"

  if [[ -x "$mise_bin" ]]; then
    echo "mise already installed, skipping installation"
    eval "$("$mise_bin" activate bash)"
    return
  fi

  mkdir -p "${HOME}/.local/bin"
  mise_installer="$(mktemp -d)"
  gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys 0x7413A06D
  curl https://mise.jdx.dev/install.sh.sig | gpg --decrypt >"$mise_installer/mise_install.sh"
  MISE_INSTALL_PATH="$mise_bin" sh "$mise_installer/mise_install.sh"

  eval "$("$mise_bin" activate bash)"
}

# Clone repo, or re-clone if the directory exists but is not a git repo
sync_repo() {
  if [[ -d "$SCRIPT_DIR/.git" ]]; then
    git -C "$SCRIPT_DIR" pull
  else
    rm -rf "$SCRIPT_DIR"
    git clone -b main --single-branch "$SYSINIT_REPO" "$SCRIPT_DIR"
  fi
}

# Setup and activate virtual environment, install required dependencies
setup_python_env() {
  cd "$SCRIPT_DIR"

  export PATH="${HOME}/.local/bin:$PATH"
  if ! command -v mise >/dev/null 2>&1; then
    echo "Error: mise not found in PATH"
    exit 1
  fi

  mise trust -a
  mise use --global uv chezmoi
  eval "$(mise activate bash)"

  if [[ ! -d ".venv" ]] || ! .venv/bin/python -c "import sysinit" 2>/dev/null; then
    if [[ -d ".venv" ]]; then
      sudo chown -R "$USER:$USER" ".venv" 2>/dev/null || sudo rm -rf ".venv"
    fi
    uv venv --clear
    # shellcheck disable=SC1091
    source ".venv/bin/activate"
    uv pip install -r requirements.txt
  else
    # shellcheck disable=SC1091
    source ".venv/bin/activate"
  fi
}

# Run ansible playbook
run_ansible() {
  local become_args=()
  [[ "$ASK_BECOME_PASS" == "true" ]] && become_args=(-K)
  ansible-playbook playbook.yml \
    "${become_args[@]}" \
    -e "git_user_name=${GIT_USER_NAME}" \
    -e "git_user_email=${GIT_USER_EMAIL}"
}

# Check and collect required Git configuration
setup_git_config() {
  GIT_USER_NAME="${GIT_USER_NAME:-$(git config --global user.name 2>/dev/null || true)}"
  GIT_USER_EMAIL="${GIT_USER_EMAIL:-$(git config --global user.email 2>/dev/null || true)}"

  if [[ -z "$GIT_USER_NAME" ]]; then
    GIT_USER_NAME="${USER:-$(whoami)}"
  fi

  if [[ -z "$GIT_USER_EMAIL" ]]; then
    local hostname
    hostname=$(hostname 2>/dev/null || echo "localhost")
    GIT_USER_EMAIL="${USER:-$(whoami)}@${hostname}"
  fi

  echo "Git configuration: $GIT_USER_NAME <$GIT_USER_EMAIL>"

  export GIT_USER_NAME
  export GIT_USER_EMAIL
}

# Setup SSH agent for GitHub access
setup_ssh_agent() {
  local ssh_dir="${HOME}/.ssh"
  local ssh_env="${ssh_dir}/agent-env"
  local existing_agent=false
  local keys_loaded=false
  local is_interactive=false

  if [ -t 0 ] && [ -t 1 ]; then
    is_interactive=true
  fi

  echo "Setting up SSH agent and keys..."

  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"

  # Use existing agent if available with keys loaded
  if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -n "${SSH_AGENT_PID:-}" ]; then
    if kill -0 "$SSH_AGENT_PID" 2>/dev/null && ssh-add -l >/dev/null 2>&1; then
      echo "Found existing SSH agent with keys loaded ($(ssh-add -l | wc -l) keys)"
      export SSH_AUTH_SOCK
      export SSH_AGENT_PID
      return 0
    fi
  fi

  # Check saved agent-env
  if [ -f "$ssh_env" ]; then
    # shellcheck source=/dev/null
    source "$ssh_env" >/dev/null 2>&1 || true
    if [ -n "${SSH_AGENT_PID:-}" ] && kill -0 "$SSH_AGENT_PID" 2>/dev/null; then
      if ssh-add -l >/dev/null 2>&1; then
        echo "Found existing SSH agent in $ssh_env with keys loaded"
        existing_agent=true
        keys_loaded=true
      else
        existing_agent=true
      fi
    fi
  fi

  # Start a new agent if needed
  if [ "$existing_agent" = false ]; then
    if [ -f "$ssh_env" ]; then
      # shellcheck source=/dev/null
      source "$ssh_env" >/dev/null 2>&1 || true
      [ -n "${SSH_AGENT_PID:-}" ] && kill "$SSH_AGENT_PID" 2>/dev/null || true
    fi

    ssh-agent >"$ssh_env"
    chmod 600 "$ssh_env"
    # shellcheck disable=SC1090
    source "$ssh_env" >/dev/null

    if [ -z "${SSH_AGENT_PID:-}" ] || ! kill -0 "$SSH_AGENT_PID" 2>/dev/null; then
      echo "Error: Failed to start SSH agent"
      exit 1
    fi
    echo "SSH agent started"
  fi

  # Load keys if needed
  if [ "$keys_loaded" = false ]; then
    local keys_found=false
    local keys_added=false

    for key in "${HOME}/.ssh/id_ed25519" "${HOME}/.ssh/id_ecdsa" "${HOME}/.ssh/id_rsa"; do
      [ -f "$key" ] || continue
      keys_found=true

      if ssh-add "$key" 2>/dev/null; then
        echo "Loaded $key"
        keys_added=true
        break
      elif [ "$is_interactive" = true ]; then
        if ssh-add "$key"; then
          echo "Loaded $key (with passphrase)"
          keys_added=true
          break
        fi
      fi
    done

    if [ "$keys_found" = false ]; then
      echo "No SSH keys found in ${HOME}/.ssh/ — generate one with: ssh-keygen -t ed25519"
      exit 1
    fi

    if [ "$keys_added" = false ]; then
      echo "SSH keys found but could not be loaded (encrypted and no interactive terminal?)"
      exit 1
    fi
  fi

  if ! ssh-add -l >/dev/null 2>&1; then
    echo "Error: SSH agent running but no keys loaded"
    exit 1
  fi

  echo "SSH agent ready ($(ssh-add -l | wc -l) keys loaded, PID: $SSH_AGENT_PID)"
  export SSH_AUTH_SOCK
  export SSH_AGENT_PID
}

# Main execution
main() {
  parse_args "$@"

  install_packages
  install_mise
  sync_repo
  setup_git_config

  if [[ "$ENABLE_SSH_SETUP" == "true" ]]; then
    setup_ssh_agent
  fi

  setup_python_env
  run_ansible
}

main "$@"
