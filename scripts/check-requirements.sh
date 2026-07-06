#!/usr/bin/env bash
set -euo pipefail

MISSING=0

check_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf 'OK: %s\n' "$cmd"
  else
    printf 'MISSING: %s\n' "$cmd" >&2
    MISSING=1
  fi
}

REQUIRED_CMDS=(
  bash
  cloud-localds
  curl
  ssh
  qemu-system-x86_64
  qemu-img
  sha256sum
  sha512sum
  python3
  xorriso
  cpio
  gzip
  dd
)

for cmd in "${REQUIRED_CMDS[@]}"; do
  check_cmd "$cmd"
done

if [[ "$MISSING" -ne 0 ]]; then
  echo "One or more required tools are missing." >&2
  exit 1
fi

echo "All required tools are installed."
