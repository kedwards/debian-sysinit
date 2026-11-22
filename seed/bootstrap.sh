#!/usr/bin/env bash
# Debian workstation bootstrap. Run as the target user (needs sudo), e.g.:
#   curl -fsSL https://raw.githubusercontent.com/kedwards/debian-sysinit/main/seed/bootstrap.sh | bash
# Also embedded into seed/user-data at build time (see render_cloud_init_user_data).
# Headless base only; mise tools and the optional i3 desktop / GUI apps are installed afterwards by chezmoi.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

USER_NAME="${USER_NAME:-$(id -un)}"
if [[ "$USER_NAME" == "root" ]]; then
  echo "Run as a regular user with sudo, or set USER_NAME" >&2
  exit 1
fi
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
BOOTSTRAP_ROOT="/opt/sysinit"
BOOTSTRAP_SENTINEL="${BOOTSTRAP_ROOT}/.bootstrapped"

log() {
  printf '[sysinit-bootstrap] %s\n' "$*"
}

sudo mkdir -p "$BOOTSTRAP_ROOT"
sudo chown "$USER_NAME:$USER_NAME" "$BOOTSTRAP_ROOT"

log "Installing base packages"
sudo apt-get update
sudo apt-get install -y \
  ca-certificates \
  curl \
  gcc \
  git \
  gnupg \
  make \
  unzip

log "Installing AWS Session Manager plugin"
if ! command -v session-manager-plugin >/dev/null 2>&1 && ! command -v sessionmanagerplugin >/dev/null 2>&1; then
  tmp_deb="$(mktemp /tmp/session-manager-plugin.XXXXXX.deb)"
  curl -fsSL -o "$tmp_deb" https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb
  sudo dpkg -i "$tmp_deb"
  rm -f "$tmp_deb"
fi

if command -v session-manager-plugin >/dev/null 2>&1 && ! command -v sessionmanagerplugin >/dev/null 2>&1; then
  sudo ln -sf "$(command -v session-manager-plugin)" /usr/local/bin/sessionmanagerplugin
fi

log "Installing Docker"
if [[ ! -f /etc/apt/sources.list.d/docker.sources ]]; then
  . /etc/os-release
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" | sudo tee /etc/apt/keyrings/docker.asc >/dev/null
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/${ID}
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF
fi

sudo apt-get update
sudo apt-get install -y \
  bash-completion \
  containerd.io \
  docker-buildx-plugin \
  docker-ce \
  docker-ce-cli \
  docker-compose-plugin
sudo groupadd -f docker
sudo usermod -aG docker "$USER_NAME"
sudo systemctl enable docker
sudo systemctl start docker

log "Installing mise"
if [[ ! -x "$USER_HOME/.local/bin/mise" ]]; then
  tmp_dir="$(mktemp -d /tmp/mise-install.XXXXXX)"
  mkdir -p "$USER_HOME/.local/bin"
  gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys 0x7413A06D
  curl -fsSL https://mise.jdx.dev/install.sh.sig | gpg --decrypt >"$tmp_dir/mise-install.sh"
  chmod +x "$tmp_dir/mise-install.sh"
  MISE_INSTALL_PATH="$USER_HOME/.local/bin/mise" sh "$tmp_dir/mise-install.sh"
  rm -rf "$tmp_dir"
fi

log "Installing uv and chezmoi"
env PATH="$USER_HOME/.local/bin:$PATH" "$USER_HOME/.local/bin/mise" use --global --yes uv chezmoi

log "Completing bootstrap"
touch "$BOOTSTRAP_SENTINEL"
