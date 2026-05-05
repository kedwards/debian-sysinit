#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ISO="${TEST_ISO:-}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_USER="${SSH_USER:-devops}"
QEMU_DISPLAY="${QEMU_DISPLAY:-gtk}"
TEST_DISK="${TEST_DISK:-}"
INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-300}"
SERIAL_LOG="$(mktemp /tmp/sysinit-serial-XXXXXX.log)"
QEMU_PID=""

cleanup() {
  if [[ -n "$QEMU_PID" ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
    echo ""
    echo "Stopping VM..."
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  rm -f "$SERIAL_LOG"
}
trap cleanup EXIT

preflight_checks() {
  for cmd in qemu-system-x86_64 qemu-img; do
    command -v "$cmd" &>/dev/null || { echo "ERROR: $cmd not found"; exit 1; }
  done
  [[ -n "$ISO" && -f "$ISO" ]] || { echo "ERROR: ISO not found — run 'task build' first"; exit 1; }
  [[ -n "$TEST_DISK" ]] || { echo "ERROR: TEST_DISK not set"; exit 1; }
}

run_installer() {
  echo "Creating disk: $TEST_DISK"
  mkdir -p "$(dirname "$TEST_DISK")"
  rm -f "$TEST_DISK"
  qemu-img create -f qcow2 "$TEST_DISK" 20G

  echo "Starting installer (up to ${INSTALL_TIMEOUT}s) ..."
  qemu-system-x86_64 \
    -enable-kvm \
    -m 2048 \
    -smp 2 \
    -drive "file=$ISO,media=cdrom,readonly=on" \
    -drive "file=$TEST_DISK,format=qcow2,if=virtio" \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" \
    -device e1000,netdev=net0 \
    -device virtio-rng-pci \
    -serial "file:$SERIAL_LOG" \
    -boot once=d \
    -no-reboot \
    -display "$QEMU_DISPLAY" \
    &
  QEMU_PID=$!

  local elapsed=0
  while kill -0 "$QEMU_PID" 2>/dev/null; do
    sleep 10
    elapsed=$((elapsed + 10))
    printf "\r  ...%ss elapsed" "$elapsed"
    if [[ $elapsed -ge $INSTALL_TIMEOUT ]]; then
      echo ""
      echo "ERROR: Timed out after ${INSTALL_TIMEOUT}s waiting for installer"
      tail -30 "$SERIAL_LOG" 2>/dev/null || true
      exit 1
    fi
  done

  wait "$QEMU_PID" || true
  QEMU_PID=""
  echo ""
  echo "  Installer finished after ${elapsed}s"
}

boot_for_login() {
  echo ""
  echo "Booting installed disk..."
  qemu-system-x86_64 \
    -enable-kvm \
    -m 2048 \
    -smp 2 \
    -drive "file=$TEST_DISK,format=qcow2,if=virtio" \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" \
    -device e1000,netdev=net0 \
    -device virtio-rng-pci \
    -serial "file:$SERIAL_LOG" \
    -display "$QEMU_DISPLAY" \
    &
  QEMU_PID=$!

  echo ""
  echo "  Disk:  $TEST_DISK"
  echo "  SSH:   ssh -p ${SSH_PORT} ${SSH_USER}@localhost"
  echo ""
  echo "  Close the VM window or Ctrl-C to stop."
  echo ""

  wait "$QEMU_PID" || true
  QEMU_PID=""
}

preflight_checks
run_installer
boot_for_login
