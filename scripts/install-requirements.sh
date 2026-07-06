#!/usr/bin/env bash
set -euo pipefail

if ! command -v apt-get >/dev/null 2>&1; then
  echo "ERROR: apt-get is required to install dependencies on this system" >&2
  exit 1
fi

APT_PACKAGES=(
  bash
  cloud-image-utils
  coreutils
  cpio
  curl
  gzip
  openssh-client
  python3
  qemu-system-x86
  qemu-utils
  xorriso
)

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  APT_CMD=(apt-get)
elif command -v sudo >/dev/null 2>&1; then
  APT_CMD=(sudo apt-get)
else
  echo "ERROR: run as root or install sudo to install dependencies" >&2
  exit 1
fi

"${APT_CMD[@]}" update
"${APT_CMD[@]}" install -y "${APT_PACKAGES[@]}"
