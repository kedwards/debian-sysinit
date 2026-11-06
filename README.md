# Debian Sysinit

Builds and tests Debian `sysinit` bootstrap media through two local workflows:

- a remastered Debian netinst ISO for unattended installer-based installs
- a Debian generic cloud image overlay with a NoCloud seed ISO for first-boot bootstrap

Both workflows are intended for local QEMU-based validation and rely on the same shared SSH/test helpers.

## What this repository contains

- `Taskfile.yml` — convenience tasks for ISO and cloud-image build/test flows
- `preseed.cfg.tmpl` — the unattended Debian installer template used by the ISO flow
- `seed/user-data` — cloud-init template used by the cloud-image flow
- `seed/bootstrap.sh` — Debian-only bootstrap (packages, systemd-resolved, Docker, AWS SSM plugin, mise + uv + chezmoi,
  Nerd Font, Ghostty). It is inlined into `seed/user-data` at render time, and can also be run on its own on a
  stock Debian install (see below). chezmoi installs the mise tools afterwards.
- `scripts/build.sh` — downloads, verifies, modifies, and rebuilds the Debian installer ISO
- `scripts/render-preseed.sh` — renders the preseed variants from the template and checks their
  syntax, without touching the installer ISO
- `scripts/test.sh` — boots the generated ISO in QEMU and validates the installed system
  plus first-boot cloud-init and `sysinit` bootstrap behavior
- `scripts/build-image.sh` — downloads the Debian generic cloud image, generates a NoCloud seed ISO, and creates a QCOW2 overlay
- `scripts/test-image.sh` — boots the cloud image in QEMU and validates the first-boot bootstrap path
- `scripts/lib/common.sh` — shared SSH key discovery, cloud-init rendering, preseed rendering/verification, and QEMU helper functions
- `scripts/lib/cloud-image-test.sh` — shared cloud-image test harness
- `reference/full-preseed-dump.cfg` — a `debconf-get-selections --installer` dump captured after a
  successful manual install; the master list of valid `d-i` question names, owners, and types for
  cross-checking `preseed.cfg.tmpl` by hand

## What each workflow does

### Boot menu

The custom ISO has one entry per partitioning mode and network type:

| Partitioning | Ethernet | WiFi |
|---|---|---|
| **Install, ERASES WHOLE DISK** — LVM on `DISK`, unattended | default entry, auto-selected after a short timeout | prompts for network |
| **Dual-boot, use biggest free space** — regular partitions in the largest free area of `DISK`, other OSes kept, unattended | unattended | prompts for network |
| **Dual-boot, choose partitions** — the installer's partitioning screen | prompts for partitioning only | prompts for network and partitioning |

For a Windows/Debian dual boot, shrink the Windows partition first (from Windows, Disk Management),
then use either dual-boot entry. "Biggest free space" is fully automatic; "choose partitions" lets you
reuse an existing EFI partition or pick the layout yourself. GRUB runs os-prober, so Windows is added to
the boot menu. The "free space" mode has not been tried against a real Windows disk; check the result
before relying on it.

The default `DISK` is `/dev/nvme0n1`. Override it for other hardware, e.g. `DISK=/dev/sda`. For QEMU/VM
testing use `DISK=/dev/vda` (virtio); `task iso:test` already builds with it. The dual-boot "choose
partitions" entries ignore `DISK`.

### WiFi

By default WiFi credentials are not baked into the image: the installer prompts for the interface, SSID,
and WPA passphrase. Prefer a wired connection (a USB-C dock or phone USB tethering both appear as
ethernet and work with the Ethernet entries). The installer's `netcfg` only speaks WPA2-PSK; it cannot
negotiate WPA3 or WPA3-transition (PMF) and fails with *"the exchange of keys and association with the
access point failed"*.

WiFi also requires wireless firmware in the installer. Current Debian 13 netinst images bundle
`non-free-firmware` (including `firmware-iwlwifi`), so Intel adapters appear automatically.

**Private hands-off wireless build.** Set `WIFI_SSID` and `WIFI_PSK` at build time and the WiFi entries
use them instead of prompting, so they run as unattended as the Ethernet ones:

```bash path=null start=null
WIFI_SSID='my-network' WIFI_PSK='passphrase' task iso:build
```

The credentials are stored in plain text inside the ISO (and in `build/` if you run `task preseed:render`),
so it works only for that network and the ISO must not be shared. Build it, use it, delete it. WPA2-PSK
networks only. The label of the WiFi entries changes to "WiFi, baked-in network".

### Installer ISO workflow

The custom ISO:

- starts from the current Debian 13 `amd64` netinst image
- injects the rendered preseed files (one per network x partitioning variant) into the installer initrd
- rewrites BIOS and UEFI boot entries so the installer runs automatically
- installs Debian with LVM on the target disk, or alongside an existing OS (see the boot menu)
- creates a `devops` user by default
- installs `openssh-server`, `sudo`, `curl`, `git`, `gnupg`, `cloud-init`, and `qemu-guest-agent`
- injects your SSH public key and enables SSH access
- seeds local NoCloud data so cloud-init configures and starts `sysinit-bootstrap.service` on first boot

### Cloud image workflow

The cloud-image path:

- downloads the current Debian 13 generic cloud image
- verifies its SHA512 checksum
- renders `seed/user-data` with your SSH key and chosen username
- builds a NoCloud seed ISO with `cloud-localds`
- creates a QCOW2 overlay backed by the downloaded Debian base image
- boots the VM and runs a local `sysinit` cloud-init bootstrap on first boot
- validates bootstrap completion, SSH access, sudo setup, Docker, systemd-resolved, and tool installation

### Bootstrap a stock Debian install (no custom ISO)

Run as your regular user (needs sudo):

```bash path=null start=null
curl -fsSL https://raw.githubusercontent.com/kedwards/debian-sysinit/main/seed/bootstrap.sh | bash
```

It is idempotent and writes `/opt/sysinit/.bootstrapped` when done. Then apply your dotfiles with
`chezmoi init --apply <repo>` to get the mise tools. Log out and back in for the `docker` group.

## Prerequisites

Common tools:

- `bash`
- `curl`
- `ssh`
- `qemu-system-x86_64`
- `qemu-img`
- `sha256sum`
- `sha512sum`

ISO workflow:

- `python3`
- `xorriso`
- `cpio`
- `gzip`
- `dd`

Cloud image workflow:

- `cloud-localds`

Optional:

- `task` if you want to use `Taskfile.yml`
- a local SSH public/private key pair in `~/.ssh/`, or a 1Password SSH agent
- KVM access for faster QEMU runs

## SSH key handling

The build and test scripts try to discover SSH credentials automatically:

- public key: `SSH_PUBKEY`, then `~/.ssh/id_ed25519.pub`, `~/.ssh/id_rsa.pub`, `~/.ssh/id_ecdsa.pub`, then the 1Password SSH agent
- private key for tests: `~/.ssh/id_ed25519`, `~/.ssh/id_rsa`, `~/.ssh/id_ecdsa`, then the 1Password SSH agent

If no usable SSH key is found, the build or test command exits with an error.

## Usage

### Build the custom installer ISO

```bash path=null start=null
task build
```

or:

```bash path=null start=null
bash scripts/build.sh
```

### Render and verify the preseed files

```bash path=null start=null
task preseed:render
```

or:

```bash path=null start=null
bash scripts/render-preseed.sh
```

Renders the six `preseed-<net>-<part>.cfg` variants from `preseed.cfg.tmpl` into `build/`,
then checks each with
`debconf-set-selections -c` — the standard Debian syntax checker, run with no side effects. This
is much faster than `task build` since it skips downloading and repacking the installer ISO; use
it while iterating on `preseed.cfg.tmpl`. If a question name/type is wrong, cross-check it against
`reference/full-preseed-dump.cfg`.

### Test the installer ISO workflow

```bash path=null start=null
task test
```

or:

```bash path=null start=null
TEST_ISO=./debian-13.4.0-sysinit.iso bash scripts/test.sh
```

The ISO test flow now:

1. installs Debian from the custom ISO
2. boots the installed disk
3. waits for SSH
4. waits for first-boot cloud-init to seed and start `sysinit-bootstrap.service`
5. asserts bootstrap completion, Docker, `systemd-resolved`, `mise`, `chezmoi`, sudo, and service health

### Build the cloud image overlay and seed ISO

```bash path=null start=null
task image:build
```

or:

```bash path=null start=null
bash scripts/build-image.sh
```

### Test the cloud image workflow

```bash path=null start=null
task image:test
```

or:

```bash path=null start=null
IMAGE=./debian-13-generic-sysinit.qcow2 SEED_ISO=./debian-13-generic-sysinit-seed.iso bash scripts/test-image.sh
```

### Manual cloud image boot and SSH

```bash path=null start=null
task image:run
task image:ssh
```

## Common configuration

These environment variables are supported through `Taskfile.yml` and/or the scripts:

- `USER_NAME` — install/bootstrap user name, default `devops`
- `USER_PASSWORD` — install user password for the ISO path, default `devops`
- `SSH_PUBKEY` — explicit public key content to inject
- `SSH_PORT` — forwarded host SSH port, default `2222`
- `QEMU_DISPLAY` — `gtk` or `none`
- `KEEP_TEST_DISK` — set to `1` to preserve the ISO qcow2 disk after tests
- `DISK` — target install disk for the whole-disk and free-space entries, default `/dev/nvme0n1`; use `/dev/vda` in VMs
- `WIFI_SSID`, `WIFI_PSK` — bake a WiFi network into the ISO for a private hands-off wireless build
- `OUTPUT_ISO` — output path for `scripts/build.sh`
- `TEST_ISO` — ISO path for `scripts/test.sh`
- `TEST_DISK` — ISO test disk path for `scripts/test.sh`
- `OUTPUT_IMAGE` — output cloud overlay path for `scripts/build-image.sh`
- `OUTPUT_SEED` — output seed ISO path for `scripts/build-image.sh`
- `IMAGE` — cloud image overlay path for `scripts/test-image.sh`
- `SEED_ISO` — seed ISO path for `scripts/test-image.sh`

Examples:

```bash path=null start=null
USER_NAME=alice USER_PASSWORD=changeme task build
```

```bash path=null start=null
SSH_PORT=2223 QEMU_DISPLAY=none KEEP_TEST_DISK=1 task test
```

```bash path=null start=null
USER_NAME=alice OUTPUT_IMAGE=./custom-cloud.qcow2 OUTPUT_SEED=./custom-seed.iso bash scripts/build-image.sh
```

## Output artifacts

Typical generated files in the repository root:

- upstream Debian netinst ISO, for example `debian-13.4.0-amd64-netinst.iso`
- custom installer ISO, for example `debian-13.4.0-sysinit.iso`
- installer test disk, for example `debian-13.4.0-sysinit.qcow2`
- upstream Debian cloud image, `debian-13-generic-amd64.qcow2`
- custom cloud overlay, `debian-13-generic-sysinit.qcow2`
- NoCloud seed ISO, `debian-13-generic-sysinit-seed.iso`

These artifacts are ignored by git.

## Notable implementation details

- The ISO workflow injects the preseed file into `install.amd/initrd.gz`, so it is available early in the installer boot process.
- Both `isolinux` and `grub` configs are rewritten, so the ISO works for BIOS and UEFI boots.
- The ISO workflow refreshes `md5sum.txt` before packing the final image.
- The cloud-image workflow uses a QCOW2 overlay backed by the downloaded Debian base image, so repeated tests can start from a clean overlay without duplicating the base image.
- Both workflows render the same cloud-init `user-data`, so the first-boot bootstrap behavior stays aligned between the ISO and cloud-image paths.

## Notes

- The defaults are convenient for local testing, not hardened production installs.
- Passwordless sudo and the default `devops` credentials should be overridden for any real use.
