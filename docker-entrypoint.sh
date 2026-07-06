#!/usr/bin/env bash
set -euo pipefail

uid="$(id -u)"
gid="$(id -g)"

if ! getent passwd "$uid" >/dev/null 2>&1; then
  wrapper_dir="$(mktemp -d /tmp/nss-wrapper.XXXXXX)"
  passwd_file="$wrapper_dir/passwd"
  group_file="$wrapper_dir/group"
  home_dir="${HOME:-/tmp}"

  cp /etc/passwd "$passwd_file"
  cp /etc/group "$group_file"

  printf 'sysinit:x:%s:%s:sysinit:%s:/bin/bash\n' "$uid" "$gid" "$home_dir" >> "$passwd_file"
  if ! getent group "$gid" >/dev/null 2>&1; then
    printf 'sysinit:x:%s:\n' "$gid" >> "$group_file"
  fi

  export NSS_WRAPPER_PASSWD="$passwd_file"
  export NSS_WRAPPER_GROUP="$group_file"
  if [[ -n "${LD_PRELOAD:-}" ]]; then
    export LD_PRELOAD="libnss_wrapper.so:$LD_PRELOAD"
  else
    export LD_PRELOAD="libnss_wrapper.so"
  fi
fi

exec "$@"
