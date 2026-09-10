#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source=scripts/lib/cloud-image-test.sh
source "$SCRIPT_DIR/lib/cloud-image-test.sh"

IMAGE="${IMAGE:-$PROJECT_DIR/debian-13-generic-sysinit.qcow2}"
SEED_ISO="${SEED_ISO:-$PROJECT_DIR/debian-13-generic-sysinit-seed.iso}"
BUILD_HINT="${BUILD_HINT:-task image:build}"
SSH_PORT="${SSH_PORT:-2224}"
SSH_USER="${SSH_USER:-devops}"
CLOUDINIT_TIMEOUT="${CLOUDINIT_TIMEOUT:-300}"
BOOTSTRAP_TIMEOUT="${BOOTSTRAP_TIMEOUT:-1800}"
QEMU_DISPLAY="${QEMU_DISPLAY:-none}"

run_cloud_image_test
