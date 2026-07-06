#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/common.sh"

TEST_IMAGE="${TEST_IMAGE:-$(mktemp -u /tmp/sysinit-test-XXXXXX.qcow2)}"
SERIAL_LOG="${SERIAL_LOG:-$(mktemp /tmp/sysinit-serial-XXXXXX.log)}"
QEMU_PID=""
SSH_HOST="${SSH_HOST:-127.0.0.1}"
SSH_KEY=""
SSH_AUTH_SOCK_OVERRIDE=""
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

ssh_cmd() {
  local ssh_args=(
    -F /dev/null
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=5
    -o BatchMode=yes
    -p "$SSH_PORT"
  )
  [[ -n "$SSH_KEY" ]] && ssh_args+=(-i "$SSH_KEY")

  if [[ -n "$SSH_AUTH_SOCK_OVERRIDE" ]]; then
    SSH_AUTH_SOCK="$SSH_AUTH_SOCK_OVERRIDE" ssh "${ssh_args[@]}" "$SSH_USER@$SSH_HOST" "$@" 2>/dev/null
  else
    ssh "${ssh_args[@]}" "$SSH_USER@$SSH_HOST" "$@" 2>/dev/null
  fi
}

assert() {
  local desc="$1"; shift
  if ssh_cmd "$@"; then
    pass "$desc"
  else
    fail "$desc"
  fi
}

cleanup_cloud_image_test() {
  if [[ -n "$QEMU_PID" ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
    echo "Stopping QEMU (PID $QEMU_PID)..."
    kill "$QEMU_PID" 2>/dev/null || true
  fi
  rm -f "$TEST_IMAGE" "$SERIAL_LOG"
}

trap cleanup_cloud_image_test EXIT

require_cloud_image_test_prereqs() {
  local cmd
  for cmd in qemu-system-x86_64 qemu-img ssh; do
    command -v "$cmd" &>/dev/null || { echo "ERROR: $cmd not found"; exit 1; }
  done
}

resolve_backing_file() {
  local backing_file
  backing_file="$(qemu-img info "$IMAGE" | sed -n 's/^backing file: //p' | sed 's/ (actual path:.*)//' | head -1)"

  python3 - "$IMAGE" "$backing_file" <<'PY'
import os
import sys

image_path = sys.argv[1]
backing_file = sys.argv[2]

if os.path.isabs(backing_file):
    print(backing_file)
else:
    print(os.path.abspath(os.path.join(os.path.dirname(image_path), backing_file)))
PY
}

wait_for_ssh() {
  local elapsed=0

  echo "[2/3] Waiting for SSH on port $SSH_PORT (up to ${CLOUDINIT_TIMEOUT}s)..."
  while ! ssh_cmd true; do
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
      echo "ERROR: QEMU exited unexpectedly"
      echo "Serial log tail:"
      tail -30 "$SERIAL_LOG" 2>/dev/null || true
      exit 1
    fi

    sleep 5
    elapsed=$((elapsed + 5))
    if [[ $elapsed -ge $CLOUDINIT_TIMEOUT ]]; then
      echo "ERROR: Timed out after ${CLOUDINIT_TIMEOUT}s waiting for SSH"
      echo "Serial log tail:"
      tail -30 "$SERIAL_LOG" 2>/dev/null || true
      exit 1
    fi
    printf "\r  ...%ss elapsed" "$elapsed"
  done

  echo ""
  echo "  SSH available after ${elapsed}s"
}

wait_for_bootstrap() {
  local boot_elapsed=0

  echo "      Waiting for bootstrap service (up to ${BOOTSTRAP_TIMEOUT}s)..."
  while ! ssh_cmd "test -f /opt/sysinit/.bootstrapped"; do
    if ssh_cmd "systemctl is-failed sysinit-bootstrap.service" 2>/dev/null; then
      echo ""
      echo "ERROR: sysinit-bootstrap.service failed:"
      ssh_cmd "journalctl -u sysinit-bootstrap --no-pager -n 50" || true
      exit 1
    fi

    sleep 15
    boot_elapsed=$((boot_elapsed + 15))
    if [[ $boot_elapsed -ge $BOOTSTRAP_TIMEOUT ]]; then
      echo ""
      echo "ERROR: Bootstrap timed out after ${BOOTSTRAP_TIMEOUT}s"
      ssh_cmd "journalctl -u sysinit-bootstrap --no-pager -n 50" || true
      exit 1
    fi
    printf "\r  ...%ss elapsed" "$boot_elapsed"
  done

  echo ""
  echo "  Bootstrap complete after ${boot_elapsed}s"
}

run_common_assertions() {
  echo "[3/3] Running assertions..."

  assert "bootstrap sentinel exists"       "test -f /opt/sysinit/.bootstrapped"
  assert "bootstrap script installed"      "test -x /usr/local/lib/sysinit/bootstrap.sh"
  assert "mise installed"                  "test -x \$HOME/.local/bin/mise"
  assert "chezmoi installed"               "bash -lc 'CHEZMOI_PATH=\"\$("\$HOME"/.local/bin/mise which chezmoi 2>/dev/null)\" && test -n \"\$CHEZMOI_PATH\" && test -x \"\$CHEZMOI_PATH\"'"
  assert "systemd-resolved active"         "systemctl is-active systemd-resolved"
  assert "AWS SSM installed"               "command -v session-manager-plugin >/dev/null 2>&1 || command -v sessionmanagerplugin >/dev/null 2>&1"
  assert "docker installed"                "command -v docker >/dev/null 2>&1"
  assert "docker service active"           "systemctl is-active docker"
  assert "$SSH_USER is in docker group"    "id -nG | grep -qw docker"
  assert "$SSH_USER has NOPASSWD sudo"      "sudo -n true"
  assert "authorized_keys present"         "test -s \$HOME/.ssh/authorized_keys"
  assert "bootstrap service active/exited" "systemctl is-active sysinit-bootstrap.service"
  assert "bootstrap service not failed"    "! systemctl is-failed sysinit-bootstrap.service"
  assert "/opt/sysinit owned by $SSH_USER" "[ \"\$(stat -c %U /opt/sysinit)\" = $SSH_USER ]"

  echo ""
  echo "Results: ${PASS} passed, ${FAIL} failed"
  if [[ $FAIL -eq 0 ]]; then
    echo "ALL TESTS PASSED"
  else
    echo "SOME TESTS FAILED"
    exit 1
  fi
}

run_cloud_image_test() {
  require_cloud_image_test_prereqs

  [[ -f "$IMAGE" ]] || { echo "ERROR: Cloud image not found — run ${BUILD_HINT} first"; exit 1; }
  [[ -f "$SEED_ISO" ]] || { echo "ERROR: Seed ISO not found — run ${BUILD_HINT} first"; exit 1; }

  BASE_IMAGE="$(resolve_backing_file)"
  [[ -f "$BASE_IMAGE" ]] || { echo "ERROR: Base image not found at $BASE_IMAGE"; exit 1; }

  setup_ssh_test_auth
  set_kvm_args

  echo "Base:     $BASE_IMAGE"
  echo "Seed:     $SEED_ISO"
  [[ -n "$SSH_KEY" ]] && echo "SSH key:  $SSH_KEY" || echo "SSH key:  1Password agent"
  echo "SSH port: $SSH_PORT"
  [[ ${#KVM_ARGS[@]} -gt 0 ]] && echo "KVM:      enabled" || echo "KVM:      disabled (slow)"
  echo ""

  echo "[1/3] Creating fresh test overlay and booting (cloud-init ~1-2 min)..."
  qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMAGE" "$TEST_IMAGE" 20G

  qemu-system-x86_64 \
    "${KVM_ARGS[@]}" \
    -m 2048 \
    -smp 2 \
    -drive "file=$TEST_IMAGE,format=qcow2,if=virtio" \
    -drive "file=$SEED_ISO,media=cdrom,readonly=on" \
    -netdev "user,id=net0,hostfwd=tcp:${SSH_HOST}:${SSH_PORT}-:22" \
    -device e1000,netdev=net0 \
    -device virtio-rng-pci \
    -display "$QEMU_DISPLAY" \
    -serial "file:$SERIAL_LOG" \
    &
  QEMU_PID=$!

  wait_for_ssh
  wait_for_bootstrap
  run_common_assertions
}
