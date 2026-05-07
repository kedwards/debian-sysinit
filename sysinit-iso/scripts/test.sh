#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# ---------------------------------------------------------------------------
# Configuration — all overridable via environment
# ---------------------------------------------------------------------------
ISO="${TEST_ISO:-}"
SSH_PORT="${SSH_PORT:-2222}"
SSH_USER="${SSH_USER:-devops}"
KEEP_TEST_DISK="${KEEP_TEST_DISK:-0}"
QEMU_DISPLAY="${QEMU_DISPLAY:-none}"

INSTALL_TIMEOUT="${INSTALL_TIMEOUT:-300}"
BOOT_TIMEOUT="${BOOT_TIMEOUT:-60}"
BOOTSTRAP_TIMEOUT="${BOOTSTRAP_TIMEOUT:-1800}"

# If TEST_DISK is not set, create a temp disk and remove it on exit
REMOVE_TEST_DISK_ON_EXIT=0
if [[ -z "${TEST_DISK:-}" ]]; then
  TEST_DISK="$(mktemp -u /tmp/sysinit-test-XXXXXX.qcow2)"
  REMOVE_TEST_DISK_ON_EXIT=1
fi

# Serial log captures installer + first-boot console output for debugging
SERIAL_LOG="$(mktemp /tmp/sysinit-serial-XXXXXX.log)"

# Test counters — initialised early so set -u never fires on them
PASS=0
FAIL=0

# QEMU process tracking
QEMU_PID=""

# SSH auth — populated by setup_ssh_test_auth (from common.sh)
SSH_KEY=""
SSH_AUTH_SOCK_OVERRIDE=""

# ---------------------------------------------------------------------------
cleanup() {
  if [[ -n "$QEMU_PID" ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
    kill "$QEMU_PID" 2>/dev/null || true
    wait "$QEMU_PID" 2>/dev/null || true
  fi
  if [[ "$REMOVE_TEST_DISK_ON_EXIT" == "1" && "$KEEP_TEST_DISK" != "1" ]]; then
    rm -f "$TEST_DISK"
  fi
  rm -f "$SERIAL_LOG"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
preflight_checks() {
  local required_cmds=(qemu-system-x86_64 qemu-img ssh)
  for cmd in "${required_cmds[@]}"; do
    command -v "$cmd" &>/dev/null || { echo "ERROR: $cmd not found"; exit 1; }
  done

  [[ -n "$ISO" && -f "$ISO" ]] || {
    echo "ERROR: ISO not found — set TEST_ISO or run scripts/build-iso.sh first"
    exit 1
  }
}

# ---------------------------------------------------------------------------
# Run a command over SSH to the booted VM.
# ---------------------------------------------------------------------------
ssh_cmd() {
  local ssh_args=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o ConnectTimeout=5
    -o BatchMode=yes
    -p "$SSH_PORT"
  )
  [[ -n "$SSH_KEY" ]] && ssh_args+=(-i "$SSH_KEY")

  # shellcheck disable=SC2029
  if [[ -n "$SSH_AUTH_SOCK_OVERRIDE" ]]; then
    SSH_AUTH_SOCK="$SSH_AUTH_SOCK_OVERRIDE" ssh "${ssh_args[@]}" "${SSH_USER}@localhost" "$@" 2>/dev/null
  else
    ssh "${ssh_args[@]}" "${SSH_USER}@localhost" "$@" 2>/dev/null
  fi
}

# ---------------------------------------------------------------------------
# assert <description> <ssh command...>
#   Runs the command over SSH and records pass/fail.
#
# assert_output <description> <expected_output> <ssh command...>
#   Runs the command over SSH and checks stdout matches expected_output exactly.
# ---------------------------------------------------------------------------
assert() {
  local desc="$1"; shift
  if ssh_cmd "$@"; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc"
    FAIL=$((FAIL + 1))
  fi
}

assert_output() {
  local desc="$1"
  local expected="$2"
  shift 2
  local actual
  actual="$(ssh_cmd "$@" || true)"
  if [[ "$actual" == "$expected" ]]; then
    echo "  PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc (expected: '$expected', got: '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

# ---------------------------------------------------------------------------
# Boot QEMU and wait for the installer to complete (QEMU exits on its own
# because the install image is launched with -no-reboot).
# ---------------------------------------------------------------------------
run_installer() {
  echo "Creating test disk: $TEST_DISK"
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
      echo "Serial log tail:"
      tail -30 "$SERIAL_LOG" 2>/dev/null || true
      exit 1
    fi
  done

  wait "$QEMU_PID" || true
  QEMU_PID=""
  echo ""
  echo "  Installer finished after ${elapsed}s"
}

# ---------------------------------------------------------------------------
# Boot the installed disk and wait for SSH to become available.
# ---------------------------------------------------------------------------
boot_installed_disk() {
  echo "Booting installed disk ..."
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

  echo "Waiting for SSH on port $SSH_PORT (up to ${BOOT_TIMEOUT}s) ..."
  local elapsed=0
  while ! ssh_cmd true; do
    if ! kill -0 "$QEMU_PID" 2>/dev/null; then
      echo ""
      echo "ERROR: QEMU exited unexpectedly during first boot"
      echo "Serial log tail:"
      tail -30 "$SERIAL_LOG" 2>/dev/null || true
      exit 1
    fi
    sleep 5
    elapsed=$((elapsed + 5))
    printf "\r  ...%ss elapsed" "$elapsed"
    if [[ $elapsed -ge $BOOT_TIMEOUT ]]; then
      echo ""
      echo "ERROR: Timed out after ${BOOT_TIMEOUT}s waiting for SSH"
      echo "Serial log tail:"
      tail -30 "$SERIAL_LOG" 2>/dev/null || true
      exit 1
    fi
  done
  echo ""
  echo "  SSH available after ${elapsed}s"
}

# ---------------------------------------------------------------------------
wait_for_bootstrap() {
  echo "Waiting for sysinit bootstrap service (up to ${BOOTSTRAP_TIMEOUT}s) ..."
  local elapsed=0
  while ! ssh_cmd "test -f /opt/sysinit/.bootstrapped"; do
    if ssh_cmd "systemctl is-failed sysinit-bootstrap.service" 2>/dev/null; then
      echo ""
      echo "ERROR: sysinit-bootstrap.service failed:"
      ssh_cmd "journalctl -u sysinit-bootstrap --no-pager -n 50" || true
      exit 1
    fi
    sleep 15
    elapsed=$((elapsed + 15))
    printf "\r  ...%ss elapsed" "$elapsed"
    if [[ $elapsed -ge $BOOTSTRAP_TIMEOUT ]]; then
      echo ""
      echo "ERROR: Timed out after ${BOOTSTRAP_TIMEOUT}s waiting for bootstrap"
      ssh_cmd "journalctl -u sysinit-bootstrap --no-pager -n 50" || true
      exit 1
    fi
  done
  echo ""
  echo "  Bootstrap complete after ${elapsed}s"
}

# ---------------------------------------------------------------------------
run_assertions() {
  echo "Running assertions ..."
  assert       "cloud-init completed"                "cloud-init status --wait"
  assert       "bootstrap sentinel exists"           "test -f /opt/sysinit/.bootstrapped"
  assert       "bootstrap script installed"          "test -x /usr/local/lib/sysinit/bootstrap.sh"
  assert       "mise installed"                      "test -x \$HOME/.local/bin/mise"
  assert       "chezmoi installed"                   "bash -lc 'CHEZMOI_PATH=\"\$(\"\$HOME\"/.local/bin/mise which chezmoi 2>/dev/null)\" && test -n \"\$CHEZMOI_PATH\" && test -x \"\$CHEZMOI_PATH\"'"
  assert       "systemd-resolved active"             "systemctl is-active systemd-resolved"
  assert       "AWS SSM installed"                   "command -v session-manager-plugin >/dev/null 2>&1 || command -v sessionmanagerplugin >/dev/null 2>&1"
  assert       "docker installed"                    "command -v docker >/dev/null 2>&1"
  assert       "docker service active"               "systemctl is-active docker"
  assert       "$SSH_USER is in docker group"        "id -nG | grep -qw docker"
  assert       "$SSH_USER has NOPASSWD sudo"         "sudo -n true"
  assert       "authorized_keys present"             "test -s \$HOME/.ssh/authorized_keys"
  assert_output "home directory owner"               "$SSH_USER" "stat -c %U \$HOME"
  assert       "bootstrap service active/exited"     "systemctl is-active sysinit-bootstrap.service"
  assert       "bootstrap service not failed"        "! systemctl is-failed sysinit-bootstrap.service"
  assert       "/opt/sysinit owned by $SSH_USER"     "[ \"\$(stat -c %U /opt/sysinit)\" = $SSH_USER ]"

  echo ""
  echo "Results: ${PASS} passed, ${FAIL} failed"
  if [[ $FAIL -eq 0 ]]; then
    echo "ALL TESTS PASSED"
  else
    echo "SOME TESTS FAILED"
    echo "Serial log: $SERIAL_LOG"
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
preflight_checks
setup_ssh_test_auth
run_installer
boot_installed_disk
wait_for_bootstrap
run_assertions
