resolve_ssh_pubkey() {
  local ssh_pubkey="${SSH_PUBKEY:-}"

  if [[ -z "$ssh_pubkey" ]]; then
    local keyfile
    for keyfile in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub ~/.ssh/id_ecdsa.pub; do
      [[ -f "$keyfile" ]] && ssh_pubkey="$(cat "$keyfile")" && break
    done
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
