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
