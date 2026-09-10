#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SEED_TEMPLATE="$PROJECT_DIR/seed/user-data"
OUTPUT_IMAGE="${OUTPUT_IMAGE:-$PROJECT_DIR/debian-13-generic-sysinit.qcow2}"
OUTPUT_SEED="${OUTPUT_SEED:-$PROJECT_DIR/debian-13-generic-sysinit-seed.iso}"

# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

USER_NAME="${USER_NAME:-devops}"
USER_PASSWORD="${USER_PASSWORD:-devops}"

DEBIAN_BASE_URL="https://cloud.debian.org/images/cloud/trixie/latest"
DEBIAN_SHA512_URL="$DEBIAN_BASE_URL/SHA512SUMS"
DEBIAN_IMAGE_NAME_REMOTE="debian-13-generic-amd64.qcow2"
DEBIAN_IMAGE_URL="$DEBIAN_BASE_URL/$DEBIAN_IMAGE_NAME_REMOTE"
DEBIAN_IMAGE_CACHED="$PROJECT_DIR/$DEBIAN_IMAGE_NAME_REMOTE"

WORK_DIR="$(mktemp -d /tmp/debian-image-build.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

preflight_checks() {
  local cmd
  for cmd in cloud-localds qemu-img curl sha512sum; do
    command -v "$cmd" &>/dev/null || { echo "ERROR: $cmd not found"; exit 1; }
  done
  [[ -f "$SEED_TEMPLATE" ]] || { echo "ERROR: Seed template not found at $SEED_TEMPLATE"; exit 1; }
}

download_and_verify_image() {
  echo "[1/4] Downloading Debian 13 generic cloud image..."
  if [[ -f "$DEBIAN_IMAGE_CACHED" ]]; then
    echo "      Using cached $DEBIAN_IMAGE_NAME_REMOTE"
  else
    curl -L --progress-bar -o "$DEBIAN_IMAGE_CACHED" "$DEBIAN_IMAGE_URL"
  fi

  echo "[2/4] Verifying SHA512..."
  local checksum_content expected_sha actual_sha
  checksum_content="$(curl -fsSL --connect-timeout 5 --max-time 30 "$DEBIAN_SHA512_URL")"
  expected_sha="$(awk -v name="$DEBIAN_IMAGE_NAME_REMOTE" '$2 == name { print $1; exit }' <<<"$checksum_content")"
  [[ -n "$expected_sha" ]] || { echo "ERROR: Could not resolve SHA512 for $DEBIAN_IMAGE_NAME_REMOTE"; exit 1; }

  actual_sha="$(sha512sum "$DEBIAN_IMAGE_CACHED" | awk '{print $1}')"
  if [[ "$expected_sha" != "$actual_sha" ]]; then
    echo "ERROR: SHA512 mismatch"
    echo "  expected: $expected_sha"
    echo "  actual:   $actual_sha"
    exit 1
  fi
  echo "      SHA512 OK"
}

create_seed_iso() {
  echo "[3/4] Generating seed ISO (user=$USER_NAME)..."
  local user_data="$WORK_DIR/user-data"
  local meta_data="$WORK_DIR/meta-data"
  local ssh_pubkey

  mkdir -p "$(dirname "$OUTPUT_SEED")"

  ssh_pubkey="$(resolve_ssh_pubkey)"
  [[ -n "$ssh_pubkey" ]] || { echo "ERROR: No SSH public key found (checked ~/.ssh/ and 1Password agent)"; exit 1; }

  render_cloud_init_user_data "$SEED_TEMPLATE" "$user_data" "$USER_NAME" "$USER_PASSWORD" "$ssh_pubkey"
  write_cloud_init_meta_data "$meta_data" "debian-sysinit"

  cloud-localds "$WORK_DIR/seed.iso" "$user_data" "$meta_data"
  cp "$WORK_DIR/seed.iso" "$OUTPUT_SEED"
}

create_overlay_image() {
  echo "[4/4] Creating QCOW2 overlay (20G)..."
  mkdir -p "$(dirname "$OUTPUT_IMAGE")"
  rm -f "$OUTPUT_IMAGE"

  local output_dir backing_file
  output_dir="$(dirname "$OUTPUT_IMAGE")"
  backing_file="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$DEBIAN_IMAGE_CACHED" "$output_dir")"

  qemu-img create -f qcow2 -F qcow2 -b "$backing_file" "$OUTPUT_IMAGE" 20G
}

preflight_checks
download_and_verify_image
create_seed_iso
create_overlay_image

echo ""
echo "Cloud image: $OUTPUT_IMAGE"
echo "Seed ISO:    $OUTPUT_SEED"
echo "Base:        $DEBIAN_IMAGE_CACHED"
