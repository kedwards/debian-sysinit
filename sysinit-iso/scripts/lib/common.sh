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

  sed -e "s|@@USERNAME@@|$username|g" \
      -e "s|@@SSH_PUBKEY@@|$ssh_pubkey|g" \
      -e "s|@@USER_PASSWORD@@|$user_password|g" \
      -e "s|@@USER_PASSWORD_HASH@@|$hashed_password|g" \
      "$template_path" > "$output_path"
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
# @@NETWORK_CONFIG@@ placeholder with the contents of the given network snippet.
_render_preseed_variant() {
  local template="$1" net_snippet="$2" output="$3"
  local disk="$4" user_name="$5" user_password="$6" ssh_pub_key="$7"

  sed -e "s|@@DISK@@|$disk|g" \
      -e "s|@@SSH_PUB_KEY@@|$ssh_pub_key|g" \
      -e "s|@@USER_NAME@@|$user_name|g" \
      -e "s|@@USER_PASSWORD@@|$user_password|g" \
      "$template" \
    | awk -v net="$net_snippet" '
        /@@NETWORK_CONFIG@@/ { while ((getline ln < net) > 0) print ln; next }
        { print }
      ' > "$output"
}

# Render every preseed variant (wired, interactive-wifi, baked-wifi) from the
# shared template into work_dir.
#
#   preseed.cfg            wired DHCP, fully unattended (default boot entry)
#   preseed-wifi.cfg       interactive: prompts for interface/SSID/passphrase
#   preseed-baked-wifi.cfg baked WiFi creds (only when wifi_ssid+wifi_password set)
render_preseed_variants() {
  local template="$1" work_dir="$2"
  local disk="$3" user_name="$4" user_password="$5" ssh_pub_key="$6"
  local wifi_interface="${7:-auto}" wifi_hostname="${8:-debian}" wifi_domain="${9:-local}"
  local wifi_ssid="${10:-}" wifi_password="${11:-}"

  # Wired (default) — matches the original unattended behavior.
  local wired_net="$work_dir/net-wired.cfg"
  {
    printf 'd-i netcfg/choose_interface select auto\n'
    printf 'd-i netcfg/get_hostname string debian\n'
    printf 'd-i netcfg/get_domain string local\n'
    printf 'd-i netcfg/disable_dhcp boolean false\n'
  } > "$wired_net"

  # Interactive WiFi — leave interface/SSID/passphrase un-preseeded so d-i
  # prompts for them. This boots at priority=high, so only these un-answered
  # network questions surface; the rest stay unattended.
  local wifi_prompt_net="$work_dir/net-wifi-prompt.cfg"
  {
    printf 'd-i netcfg/get_hostname string debian\n'
    printf 'd-i netcfg/get_domain string local\n'
  } > "$wifi_prompt_net"

  _render_preseed_variant "$template" "$wired_net" "$work_dir/preseed.cfg" \
    "$disk" "$user_name" "$user_password" "$ssh_pub_key"
  _render_preseed_variant "$template" "$wifi_prompt_net" "$work_dir/preseed-wifi.cfg" \
    "$disk" "$user_name" "$user_password" "$ssh_pub_key"

  # Baked "baked WiFi" — only when both SSID and passphrase are supplied.
  if [[ -n "$wifi_ssid" && -n "$wifi_password" ]]; then
    local baked_wifi_net="$work_dir/net-baked-wifi.cfg"
    {
      printf 'd-i netcfg/choose_interface select %s\n' "$wifi_interface"
      printf 'd-i netcfg/get_hostname string %s\n' "$wifi_hostname"
      printf 'd-i netcfg/get_domain string %s\n' "$wifi_domain"
      printf 'd-i netcfg/disable_dhcp boolean false\n'
      printf 'd-i netcfg/wireless_show_essids select manual\n'
      printf 'd-i netcfg/wireless_essid string %s\n' "$wifi_ssid"
      printf 'd-i netcfg/wireless_security_type select wpa\n'
      printf 'd-i netcfg/wireless_wpa string %s\n' "$wifi_password"
    } > "$baked_wifi_net"
    _render_preseed_variant "$template" "$baked_wifi_net" "$work_dir/preseed-baked-wifi.cfg" \
      "$disk" "$user_name" "$user_password" "$ssh_pub_key"
  fi
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
