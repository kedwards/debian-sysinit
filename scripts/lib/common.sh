resolve_ssh_pubkey() {
  local ssh_pubkey="${SSH_PUBKEY:-}"

  if [[ -z "$ssh_pubkey" ]]; then
    local keyfile
    for keyfile in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub; do
      [[ -f "$keyfile" ]] && ssh_pubkey="$(cat "$keyfile")" && break
    done
  fi
  if [[ -z "$ssh_pubkey" && -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
    ssh_pubkey="$(ssh-add -L 2>/dev/null | head -1)"
  fi

  if [[ -z "$ssh_pubkey" && -S "${HOME}/.1password/agent.sock" ]]; then
    ssh_pubkey="$(SSH_AUTH_SOCK="${HOME}/.1password/agent.sock" ssh-add -L 2>/dev/null | head -1)"
  fi

  printf '%s\n' "$ssh_pubkey"
}

is_truthy() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

warn() {
  echo "WARN: $*" >&2
}

setup_ssh_test_auth() {
  SSH_KEY=""
  SSH_AUTH_SOCK_OVERRIDE=""

  local keyfile
  for keyfile in ~/.ssh/id_ed25519 ~/.ssh/id_rsa ~/.ssh/id_ecdsa; do
    [[ -f "$keyfile" ]] && SSH_KEY="$keyfile" && break
  done
  if [[ -z "$SSH_KEY" && -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
    SSH_AUTH_SOCK_OVERRIDE="${SSH_AUTH_SOCK}"
  fi

  if [[ -z "$SSH_KEY" && -S "${HOME}/.1password/agent.sock" ]]; then
    SSH_AUTH_SOCK_OVERRIDE="${HOME}/.1password/agent.sock"
  fi

  if [[ -z "$SSH_KEY" && -z "$SSH_AUTH_SOCK_OVERRIDE" ]]; then
    echo "ERROR: No SSH key found (checked ~/.ssh/ and 1Password agent)"
    exit 1
  fi
}

set_kvm_args() {
  KVM_ARGS=()
  [[ -w /dev/kvm ]] && KVM_ARGS=(-enable-kvm)
}

render_cloud_init_user_data() {
  local template_path="$1"
  local output_path="$2"
  local username="$3"
  local user_password="$4"
  local ssh_pubkey="$5"

  local hashed_password
  hashed_password="$(openssl passwd -6 "$user_password")"

  local bootstrap_path
  bootstrap_path="$(dirname "$template_path")/bootstrap.sh"

  # Inline seed/bootstrap.sh at the placeholder, re-indenting it for the YAML block scalar.
  awk -v script="$bootstrap_path" '
    match($0, /^ *@@BOOTSTRAP_SH@@$/) {
      indent = $0; sub(/@@BOOTSTRAP_SH@@$/, "", indent)
      while ((getline line < script) > 0) print (line == "" ? "" : indent line)
      close(script); next
    }
    { print }
  ' "$template_path" |
    sed -e "s|@@USERNAME@@|$username|g" \
        -e "s|@@SSH_PUBKEY@@|$ssh_pubkey|g" \
        -e "s|@@USER_PASSWORD@@|$user_password|g" \
        -e "s|@@USER_PASSWORD_HASH@@|$hashed_password|g" \
        > "$output_path"
}

write_cloud_init_meta_data() {
  local output_path="$1"
  local hostname="$2"

  cat > "$output_path" <<EOF
instance-id: iid-$(date +%s)
local-hostname: $hostname
EOF
}

resolve_debian_netinst_iso() {
  local isoarch="amd64"
  local base_url="https://cdimage.debian.org/debian-cd/current/$isoarch/iso-cd"
  local sha256_url="$base_url/SHA256SUMS"

  local checksum_content
  checksum_content="$(curl -fsSL --connect-timeout 5 --max-time 30 "$sha256_url" 2>/dev/null || true)"
  [[ -z "$checksum_content" ]] && { echo "ERROR: Failed to fetch SHA256SUMS from $sha256_url" >&2; return 1; }

  local iso_file expected_sha
  iso_file="$(awk '!/edu/ && !/mac/ && /netinst/ { print $2; exit }' <<<"$checksum_content")"
  [[ -z "$iso_file" ]] && { echo "ERROR: Could not determine ISO filename from $sha256_url" >&2; return 1; }

  expected_sha="$(awk -v name="$iso_file" '$2 == name { print $1; exit }' <<<"$checksum_content")"

  echo "$iso_file|$expected_sha"
}

resolve_sysinit_iso() {
  local project_dir="$1"
  local iso_info
  iso_info="$(resolve_debian_netinst_iso)" || return 1

  local iso_file="${iso_info%|*}"
  local sysinit_iso="${iso_file/-amd64-netinst/-sysinit}"
  echo "$project_dir/$sysinit_iso"
}

# ---------------------------------------------------------------------------
# Render the preseed template with shared substitutions, replacing the
# @@NETWORK_CONFIG@@ and @@PARTITIONING@@ placeholders with the contents of the
# given snippet files.
_render_preseed_variant() {
  local template="$1" net_snippet="$2" part_snippet="$3" output="$4"
  local disk="$5" user_name="$6" user_password="$7" ssh_pub_key="$8"

  sed -e "s|@@DISK@@|$disk|g" \
      -e "s|@@SSH_PUB_KEY@@|$ssh_pub_key|g" \
      -e "s|@@USER_NAME@@|$user_name|g" \
      -e "s|@@USER_PASSWORD@@|$user_password|g" \
      "$template" \
    | awk -v net="$net_snippet" -v part="$part_snippet" '
        /@@NETWORK_CONFIG@@/ { while ((getline ln < net) > 0) print ln; close(net); next }
        /@@PARTITIONING@@/   { while ((getline ln < part) > 0) print ln; close(part); next }
        { print }
      ' > "$output"
}

# Render every preseed variant from the shared template into work_dir, one file
# per network x partitioning combination: preseed-<net>-<part>.cfg
#
# Network:
#   wired  DHCP over ethernet, fully unattended
#   wifi   interactive: prompts for interface/SSID/passphrase — unless
#          WIFI_SSID and WIFI_PSK are set at build time, which bakes them in
#          for a hands-off wireless install (private build; the credentials
#          end up in plain text in the ISO, so don't distribute it)
#
# Partitioning:
#   disk    LVM on the whole disk, erasing it (unattended)
#   free    regular partitions in the biggest free space, existing OSes kept
#           (unattended; shrink Windows first)
#   manual  the installer's partitioning screen (interactive)
#
# Without baked-in credentials WiFi stays interactive: d-i's netcfg only speaks
# WPA2-PSK — it cannot negotiate WPA3 or WPA3-transition (PMF) and fails with
# "the exchange of keys and association with the access point failed".
render_preseed_variants() {
  local template="$1" work_dir="$2"
  local disk="$3" user_name="$4" user_password="$5" ssh_pub_key="$6"

  # Wired — leave the choice to d-i's auto interface selection.
  local wired_net="$work_dir/net-wired.cfg"
  {
    printf 'd-i netcfg/choose_interface select auto\n'
    printf 'd-i netcfg/get_hostname string debian\n'
    printf 'd-i netcfg/get_domain string local\n'
    printf 'd-i netcfg/disable_dhcp boolean false\n'
  } > "$wired_net"

  # WiFi — un-preseeded interface/SSID/passphrase make d-i prompt for them
  # (boot priority=high surfaces only those). With WIFI_SSID/WIFI_PSK set,
  # answer them instead.
  local wifi_net="$work_dir/net-wifi.cfg"
  {
    printf 'd-i netcfg/get_hostname string debian\n'
    printf 'd-i netcfg/get_domain string local\n'
  } > "$wifi_net"
  if [[ -n "${WIFI_SSID:-}" ]]; then
    [[ -n "${WIFI_PSK:-}" ]] || { echo "ERROR: WIFI_SSID is set but WIFI_PSK is empty" >&2; return 1; }
    {
      printf 'd-i netcfg/choose_interface select auto\n'
      printf 'd-i netcfg/disable_dhcp boolean false\n'
      printf 'd-i netcfg/wireless_essid string %s\n' "$WIFI_SSID"
      printf 'd-i netcfg/wireless_essid_again string %s\n' "$WIFI_SSID"
      printf 'd-i netcfg/wireless_security_type select wpa\n'
      printf 'd-i netcfg/wireless_wpa string %s\n' "$WIFI_PSK"
    } >> "$wifi_net"
  fi

  local part_disk="$work_dir/part-disk.cfg"
  {
    printf 'd-i partman-auto/disk string %s\n' "$disk"
    printf 'd-i partman-auto/method string lvm\n'
    printf 'd-i partman-auto-lvm/guided_size string max\n'
    printf 'd-i partman-auto/choose_recipe select atomic\n'
    printf 'd-i partman-lvm/confirm boolean true\n'
    printf 'd-i partman-lvm/confirm_nooverwrite boolean true\n'
    printf 'd-i partman-lvm/device_remove_lvm boolean true\n'
    printf 'd-i partman-md/device_remove_md boolean true\n'
    printf 'd-i partman-partitioning/confirm_write_new_label boolean true\n'
    printf 'd-i partman/confirm boolean true\n'
    printf 'd-i partman/confirm_nooverwrite boolean true\n'
    printf 'd-i partman/choose_partition select finish\n'
    printf 'd-i grub-installer/only_debian boolean true\n'
    printf 'd-i grub-installer/bootdev string %s\n' "$disk"
  } > "$part_disk"

  # Dual-boot: keep other OSes, so GRUB must run os-prober and not assume
  # Debian is alone on the disk.
  local part_free="$work_dir/part-free.cfg"
  {
    printf 'd-i partman-auto/disk string %s\n' "$disk"
    printf 'd-i partman-auto/method string regular\n'
    printf 'd-i partman-auto/init_automatically_partition select biggest_free\n'
    printf 'd-i partman-auto/choose_recipe select atomic\n'
    printf 'd-i partman-partitioning/confirm_write_new_label boolean true\n'
    printf 'd-i partman/confirm boolean true\n'
    printf 'd-i partman/confirm_nooverwrite boolean true\n'
    printf 'd-i partman/choose_partition select finish\n'
    printf 'd-i grub-installer/only_debian boolean false\n'
    printf 'd-i grub-installer/with_other_os boolean true\n'
    printf 'd-i grub-installer/bootdev string %s\n' "$disk"
  } > "$part_free"

  local part_manual="$work_dir/part-manual.cfg"
  {
    printf 'd-i grub-installer/only_debian boolean false\n'
    printf 'd-i grub-installer/with_other_os boolean true\n'
  } > "$part_manual"

  local net part
  for net in wired wifi; do
    for part in disk free manual; do
      _render_preseed_variant "$template" "$work_dir/net-$net.cfg" "$work_dir/part-$part.cfg" \
        "$work_dir/preseed-$net-$part.cfg" "$disk" "$user_name" "$user_password" "$ssh_pub_key"
    done
  done
}

# Run debconf-set-selections -c (syntax check, no side effects) against every
# rendered preseed variant in work_dir. Prints PASS/FAIL per file, returns
# non-zero if any file fails.
verify_preseed_files() {
  local work_dir="$1"
  local status=0
  local f output

  for f in "$work_dir"/preseed*.cfg; do
    [[ -f "$f" ]] || continue
    if output="$(debconf-set-selections -c "$f" 2>&1)"; then
      echo "  PASS: $(basename "$f")"
    else
      echo "  FAIL: $(basename "$f")"
      [[ -n "$output" ]] && echo "$output" | sed 's/^/    /'
      status=1
    fi
  done

  return $status
}
