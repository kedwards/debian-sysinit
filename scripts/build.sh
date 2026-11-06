#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Default user
USER_NAME="${USER_NAME:-devops}"
USER_PASSWORD="${USER_PASSWORD:-devops}"

# Target disk for the whole-disk / free-space entries
# /dev/nvme0n1  = NVMe (default)
# /dev/sda      = bare metal SATA / IDE
# /dev/vda      = virtio — use this for QEMU/VM testing (DISK=/dev/vda)
DISK="${DISK:-/dev/nvme0n1}"

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

create_preseed_config() {
  echo "Rendering preseed variants ..."
  render_preseed_variants "$PRESEED_TEMPLATE" "$WORK_DIR" \
    "$DISK" "$USER_NAME" "$USER_PASSWORD" "$SSH_PUB_KEY"

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
# Write both isolinux (BIOS) and grub (UEFI) bootloader configs, one entry per
# network x partitioning variant (see render_preseed_variants).
#
# preseed/file=/preseed-<net>-<part>.cfg points to the file inside the initrd.
# Fully answered variants boot with auto=true + priority=critical and no
# prompts. Variants that need input (manual partitioning, or WiFi without
# baked-in credentials) drop auto=true/quiet and use priority=high so d-i asks
# only the un-preseeded questions and the rest stays unattended.
#
# The first entry (Ethernet, whole disk) is the default; its cmdline is kept
# identical to the original so the automated QEMU test keeps passing.
# ---------------------------------------------------------------------------
configure_bootloaders() {
  echo "Configuring bootloaders ..."

  local wifi_label="WiFi"
  [[ -n "${WIFI_SSID:-}" ]] && wifi_label="WiFi, baked-in network"

  local isolinux_cfg grub_cfg
  isolinux_cfg=$'default install-wired-disk\ntimeout 50\n'
  grub_cfg=$'set default=0\nset timeout=5\n'

  local part part_label net net_label label params unattended
  for part in disk free manual; do
    case "$part" in
      disk)   part_label="Install, ERASES WHOLE DISK" ;;
      free)   part_label="Dual-boot, use biggest free space" ;;
      manual) part_label="Dual-boot, choose partitions" ;;
    esac
    for net in wired wifi; do
      case "$net" in
        wired) net_label="Ethernet" ;;
        wifi)  net_label="$wifi_label" ;;
      esac

      unattended=1
      [[ "$part" == manual ]] && unattended=0
      [[ "$net" == wifi && -z "${WIFI_SSID:-}" ]] && unattended=0
      if (( unattended )); then
        params="auto=true priority=critical preseed/file=/preseed-$net-$part.cfg quiet"
      else
        params="priority=high preseed/file=/preseed-$net-$part.cfg"
      fi
      label="$part_label ($net_label)"

      isolinux_cfg+=$'\n'"label install-$net-$part"$'\n'
      isolinux_cfg+="    menu label $label"$'\n'
      [[ "$net-$part" == wired-disk ]] && isolinux_cfg+=$'    menu default\n'
      isolinux_cfg+=$'    kernel /install.amd/vmlinuz\n'
      isolinux_cfg+="    append vga=788 initrd=/install.amd/initrd.gz $params ---"$'\n'

      grub_cfg+=$'\n'"menuentry \"$label\" {"$'\n'
      grub_cfg+="    linux /install.amd/vmlinuz vga=788 $params ---"$'\n'
      grub_cfg+=$'    initrd /install.amd/initrd.gz\n}\n'
    done
  done

  printf '%s' "$isolinux_cfg" > "$ISO_EXTRACT/isolinux/isolinux.cfg"
  printf '%s' "$grub_cfg" > "$ISO_EXTRACT/boot/grub/grub.cfg"
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
