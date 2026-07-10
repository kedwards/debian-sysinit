#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Renders the preseed.cfg variants from preseed.cfg.tmpl and checks their
# syntax with debconf-set-selections -c — without downloading or touching
# the installer ISO. Use this for a fast iterate-on-the-template loop; run
# scripts/build.sh (or scripts/test.sh) for a full build/boot verification.

USER_NAME="${USER_NAME:-devops}"
USER_PASSWORD="${USER_PASSWORD:-devops}"
DISK="${DISK:-/dev/vda}"

PRESEED_TEMPLATE="$PROJECT_DIR/preseed.cfg.tmpl"
WORK_DIR="${OUTPUT_DIR:-$PROJECT_DIR/build}"
mkdir -p "$WORK_DIR"

command -v debconf-set-selections &>/dev/null || { echo "ERROR: debconf-set-selections not found"; exit 1; }

SSH_PUB_KEY="$(resolve_ssh_pubkey)"
[[ -z "$SSH_PUB_KEY" ]] && { echo "ERROR: No SSH public key found (checked ~/.ssh/ and 1Password agent)"; exit 1; }

render_preseed_variants "$PRESEED_TEMPLATE" "$WORK_DIR" \
  "$DISK" "$USER_NAME" "$USER_PASSWORD" "$SSH_PUB_KEY" \
  "${WIFI_INTERFACE:-auto}" "${WIFI_HOSTNAME:-debian}" "${WIFI_DOMAIN:-local}" \
  "${WIFI_SSID:-}" "${WIFI_PASSWORD:-}"


echo "Rendered to $WORK_DIR:"
ls "$WORK_DIR"/preseed*.cfg

echo "Verifying preseed syntax (debconf-set-selections -c) ..."
verify_preseed_files "$WORK_DIR"
