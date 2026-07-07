#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Default user
USER_NAME="${USER_NAME:-devops}"
USER_PASSWORD="${USER_PASSWORD:-devops}"

# Target disk
# /dev/vda      = virtio (QEMU default)
# /dev/sda      = bare metal SATA / IDE
# /dev/nvme0n1  = NVMe
DISK="${DISK:-/dev/vda}"

# Debian netinstall
ISOARCH="amd64"
BASE_URL="https://cdimage.debian.org/debian-cd/current/$ISOARCH/iso-cd"
PRESEED_TEMPLATE="$PROJECT_DIR/preseed.cfg.tmpl"
SEED_TEMPLATE="$PROJECT_DIR/seed/user-data"
WORK_DIR="$(mktemp -d /tmp/debian-iso-build.XXXXXX)"
ISO_EXTRACT="$WORK_DIR/iso"
trap 'chmod -R +w "$WORK_DIR" 2>/dev/null; rm -rf "$WORK_DIR"' EXIT

# ---------------------------------------------------------------------------
preflight_checks() {
  local REQUIRED_CMDS=(xorriso cpio gzip dd curl sha256sum python3)
  for cmd in "${REQUIRED_CMDS[@]}"; do
    command -v "$cmd" &>/dev/null || { echo "ERROR: $cmd not found"; exit 1; }
  done
}

# ---------------------------------------------------------------------------
download_and_verify_iso() {
  local iso_info
  iso_info="$(resolve_debian_netinst_iso)" || exit 1

  ISO_FILE="${iso_info%|*}"
  EXPECTED_SHA="${iso_info#*|}"
  ISO_DOWNLOAD="$PROJECT_DIR/$ISO_FILE"
  OUTPUT_ISO="${OUTPUT_ISO:-$PROJECT_DIR/${ISO_FILE/-amd64-netinst/-sysinit}}"

  if [[ ! -f "$ISO_DOWNLOAD" ]]; then
    echo "Downloading $ISO_FILE ..."
    curl -L --progress-bar --connect-timeout 15 -o "$ISO_DOWNLOAD" "$BASE_URL/$ISO_FILE"
  else
    echo "Found cached ISO: $ISO_DOWNLOAD"
  fi

  echo "Verifying SHA256 ..."
  local actual_sha
  actual_sha="$(sha256sum "$ISO_DOWNLOAD" | awk '{print $1}')"
  if [[ "$EXPECTED_SHA" != "$actual_sha" ]]; then
    echo "ERROR: SHA256 mismatch"
    echo "  expected: $EXPECTED_SHA"
    echo "  actual:   $actual_sha"
    exit 1
  fi
  echo "SHA256 OK"
}

# ---------------------------------------------------------------------------
extract_iso() {
  echo "Extracting ISO ..."
  mkdir -p "$ISO_EXTRACT"
  xorriso -osirrox on -indev "$ISO_DOWNLOAD" -extract / "$ISO_EXTRACT"
  chmod -R +w "$ISO_EXTRACT"
}

# ---------------------------------------------------------------------------
# Render the preseed template with shared substitutions, replacing the
# @@NETWORK_CONFIG@@ placeholder with the contents of the given network snippet.
render_preseed_variant() {
  local net_snippet="$1"
  local output="$2"

  sed -e "s|@@DISK@@|$DISK|g" \
      -e "s|@@SSH_PUB_KEY@@|$SSH_PUB_KEY|g" \
      -e "s|@@USER_NAME@@|$USER_NAME|g" \
      -e "s|@@USER_PASSWORD@@|$USER_PASSWORD|g" \
      "$PRESEED_TEMPLATE" \
    | awk -v net="$net_snippet" '
        /@@NETWORK_CONFIG@@/ { while ((getline ln < net) > 0) print ln; next }
        { print }
      ' > "$output"
}

create_preseed_config() {
  echo "Rendering preseed variants ..."

  # Each variant differs only in its network block, injected in place of the
  # @@NETWORK_CONFIG@@ placeholder. All other substitutions are shared.
  #
  #   preseed.cfg            wired DHCP, fully unattended (default boot entry)
  #   preseed-wifi.cfg       interactive: prompts for interface/SSID/passphrase
  #   preseed-baked-wifi.cfg baked WiFi creds (only when WIFI_SSID+WIFI_PASSWORD set)

  # Wired (default) — matches the original unattended behavior.
  local wired_net="$WORK_DIR/net-wired.cfg"
  {
    printf 'd-i netcfg/choose_interface select auto\n'
    printf 'd-i netcfg/get_hostname string debian\n'
    printf 'd-i netcfg/get_domain string local\n'
    printf 'd-i netcfg/disable_dhcp boolean false\n'
  } > "$wired_net"

  # Interactive WiFi — leave interface/SSID/passphrase un-preseeded so d-i
  # prompts for them. This boots at priority=high (see configure_bootloaders),
  # so only these un-answered network questions surface; the rest stay unattended.
  local wifi_prompt_net="$WORK_DIR/net-wifi-prompt.cfg"
  {
    printf 'd-i netcfg/get_hostname string debian\n'
    printf 'd-i netcfg/get_domain string local\n'
  } > "$wifi_prompt_net"

  render_preseed_variant "$wired_net" "$WORK_DIR/preseed.cfg"
  render_preseed_variant "$wifi_prompt_net" "$WORK_DIR/preseed-wifi.cfg"

  # Baked "baked WiFi" — only when both SSID and passphrase are supplied.
  if [[ -n "${WIFI_SSID:-}" && -n "${WIFI_PASSWORD:-}" ]]; then
    local baked_wifi_net="$WORK_DIR/net-baked-wifi.cfg"
    {
      printf 'd-i netcfg/choose_interface select %s\n' "${WIFI_INTERFACE:-wlp0s20f3}"
      printf 'd-i netcfg/get_hostname string %s\n'    "${WIFI_HOSTNAME:-debian}"
      printf 'd-i netcfg/get_domain string %s\n'      "${WIFI_DOMAIN:-local}"
      printf 'd-i netcfg/wireless_security_type select wpa\n'
      printf 'd-i netcfg/wireless_show_essids select %s\n' "$WIFI_SSID"
      printf 'd-i netcfg/wireless_wpa string %s\n'   "$WIFI_PASSWORD"
    } > "$baked_wifi_net"
    render_preseed_variant "$baked_wifi_net" "$WORK_DIR/preseed-baked-wifi.cfg"
  fi

  echo "Rendering NoCloud user-data ..."
  render_cloud_init_user_data "$SEED_TEMPLATE" "$WORK_DIR/sysinit-user-data" "$USER_NAME" "$USER_PASSWORD" "$SSH_PUB_KEY"
  cp "$WORK_DIR/sysinit-user-data" "$ISO_EXTRACT/sysinit-user-data"
}

# ---------------------------------------------------------------------------
# Inject preseed.cfg into the initrd so it is available before any hardware
# enumeration (cdrom mount, disk detection, etc.).
#
# Debian initrds are structured as a concatenated binary:
#   [uncompressed microcode cpio] + [gzip-compressed main cpio]
#
# Strategy:
#   1. Find the byte offset of the gzip magic bytes (0x1f 0x8b) to locate
#      the start of the compressed main cpio.
#   2. Split: keep the uncompressed prefix as-is, decompress the main cpio.
#   3. Append preseed.cfg as a new cpio entry at the root of the filesystem.
#   4. Recompress the main cpio and reassemble prefix + compressed main.
# ---------------------------------------------------------------------------
inject_preseed_to_initrd() {
  echo "Injecting preseed.cfg into initrd ..."

  local initrd_orig="$ISO_EXTRACT/install.amd/initrd.gz"
  local initrd_work="$WORK_DIR/initrd.gz"
  local prefix="$WORK_DIR/initrd_prefix.cpio"
  local main_cpio="$WORK_DIR/initrd_main.cpio"

  cp "$initrd_orig" "$initrd_work"

  # Find the offset of the gzip magic number (1f 8b) using Python for portability.
  # 'binoffset' or 'xxd' approaches vary across distros; Python is reliable.
  local gzip_offset
  gzip_offset=$(python3 -c "
import sys
data = open('$initrd_work', 'rb').read()
offset = data.find(b'\x1f\x8b')
if offset < 0:
    sys.stderr.write('ERROR: No gzip stream found in initrd\n')
    sys.exit(1)
print(offset)
")

  echo "  initrd gzip stream starts at byte offset: $gzip_offset"

  # Split at the gzip boundary
  dd if="$initrd_work" bs=1 count="$gzip_offset" of="$prefix" 2>/dev/null
  dd if="$initrd_work" bs=1 skip="$gzip_offset" 2>/dev/null | gunzip > "$main_cpio"

  # Append every preseed variant as a cpio entry at / of the initrd filesystem.
  # We cd into WORK_DIR so the cpio paths are bare filenames (no leading /),
  # matching the preseed/file=/preseed*.cfg boot parameters.
  (cd "$WORK_DIR" && ls preseed*.cfg | cpio -H newc -o -A -F "$main_cpio")

  # Reassemble: uncompressed prefix + recompressed main cpio.
  # NOTE: We do NOT chmod -w here — the trap cleanup (rm -rf $WORK_DIR) needs
  # write permission, and there is no benefit to locking files in a temp dir.
  { cat "$prefix"; gzip -9n < "$main_cpio"; } > "$initrd_orig"

  echo "  initrd injection complete"
}

# ---------------------------------------------------------------------------
# Write both isolinux (BIOS) and grub (UEFI) bootloader configs.
#
# preseed/file=/preseed.cfg  points to the file inside the initrd filesystem.
# auto=true + priority=critical suppress interactive prompts.
# ---------------------------------------------------------------------------
configure_bootloaders() {
  echo "Configuring bootloaders ..."

  # The default (index 0) Ethernet entry is fully unattended and wired — its
  # cmdline is kept identical to the original so the automated QEMU test keeps
  # passing. The WiFi entries are non-default. The interactive "enter WiFi"
  # entry drops auto=true/quiet and uses priority=high so d-i prompts only for
  # the un-preseeded network questions. The "baked WiFi" entry is emitted only
  # when preseed-baked-wifi.cfg was rendered (WIFI_SSID + WIFI_PASSWORD set).
  local have_home_wifi=0
  [[ -f "$WORK_DIR/preseed-baked-wifi.cfg" ]] && have_baked_wifi=1

  cat > "$ISO_EXTRACT/isolinux/isolinux.cfg" <<'EOF'
default install
timeout 50

label install
    menu label ^Automated Install (Ethernet)
    menu default
    kernel /install.amd/vmlinuz
    append vga=788 initrd=/install.amd/initrd.gz auto=true priority=critical preseed/file=/preseed.cfg quiet ---

label wifi
    menu label Automated Install (enter ^WiFi)
    kernel /install.amd/vmlinuz
    append vga=788 initrd=/install.amd/initrd.gz priority=high preseed/file=/preseed-wifi.cfg ---
EOF

  if [[ "$have_baked_wifi" == "1" ]]; then
    cat >> "$ISO_EXTRACT/isolinux/isolinux.cfg" <<'EOF'

label bakedwifi
    menu label Automated Install (^baked WiFi)
    kernel /install.amd/vmlinuz
    append vga=788 initrd=/install.amd/initrd.gz auto=true priority=critical preseed/file=/preseed-baked-wifi.cfg quiet ---
EOF
  fi

  cat > "$ISO_EXTRACT/boot/grub/grub.cfg" <<'EOF'
set default=0
set timeout=5

menuentry "Automated Install (Ethernet)" {
    linux /install.amd/vmlinuz vga=788 auto=true priority=critical preseed/file=/preseed.cfg quiet ---
    initrd /install.amd/initrd.gz
}

menuentry "Automated Install (enter WiFi)" {
    linux /install.amd/vmlinuz vga=788 priority=high preseed/file=/preseed-wifi.cfg ---
    initrd /install.amd/initrd.gz
}
EOF

  if [[ "$have_baked_wifi" == "1" ]]; then
    cat >> "$ISO_EXTRACT/boot/grub/grub.cfg" <<'EOF'

menuentry "Automated Install (baked WiFi)" {
    linux /install.amd/vmlinuz vga=788 auto=true priority=critical preseed/file=/preseed-baked-wifi.cfg quiet ---
    initrd /install.amd/initrd.gz
}
EOF
  fi
}

# ---------------------------------------------------------------------------
recompute_md5sums() {
  echo "Recomputing md5sums ..."
  pushd "$ISO_EXTRACT" >/dev/null
  chmod +w md5sum.txt
  # -follow dereferences symlinks (needed for debian-installer symlink targets).
  # The Debian ISO contains a './debian' symlink that loops back to '.', which
  # causes 'find -follow' to detect a filesystem loop and exit non-zero.
  # We suppress that specific warning by filtering it from stderr while keeping
  # all other errors visible.
  find . -follow -type f ! -name md5sum.txt -print0 \
    2> >(grep -v 'File system loop detected' >&2) \
    | xargs -0 md5sum > md5sum.txt || true
  chmod -w md5sum.txt
  popd >/dev/null
}

# ---------------------------------------------------------------------------
generate_iso() {
  echo "Building output ISO: $OUTPUT_ISO ..."

  local mbr_bin="$WORK_DIR/isohdpfx.bin"
  dd if="$ISO_DOWNLOAD" bs=1 count=432 of="$mbr_bin" 2>/dev/null

  local efi_img
  efi_img=$(find "$ISO_EXTRACT" -name "efi.img" | sort | head -1)
  if [[ -z "$efi_img" ]]; then
    echo "ERROR: No efi.img found in $ISO_EXTRACT" >&2
    find "$ISO_EXTRACT" -name "*.img" >&2
    exit 1
  fi
  # Strip the ISO_EXTRACT prefix — xorriso wants the path relative to the source tree
  efi_img="${efi_img#$ISO_EXTRACT/}"

  xorriso -as mkisofs -r \
    -V "Debian Sysinit Installer" \
    -o "$OUTPUT_ISO" \
    -J -joliet-long \
    -l \
    -cache-inodes \
    -isohybrid-mbr "$mbr_bin" \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -boot-load-size 4 \
    -boot-info-table \
    -no-emul-boot \
    -eltorito-alt-boot \
    -e "$efi_img" \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -isohybrid-apm-hfsplus \
    "$ISO_EXTRACT"

  echo "Done: $OUTPUT_ISO"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
preflight_checks
download_and_verify_iso

SSH_PUB_KEY="$(resolve_ssh_pubkey)"
[[ -z "$SSH_PUB_KEY" ]] && { echo "ERROR: No SSH public key found (checked ~/.ssh/ and 1Password agent)"; exit 1; }

extract_iso
create_preseed_config
inject_preseed_to_initrd
configure_bootloaders
recompute_md5sums
generate_iso
