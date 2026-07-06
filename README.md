# sysinit-iso

Builds and tests Debian `sysinit` bootstrap media through two local workflows:

- a remastered Debian netinst ISO for unattended installer-based installs
- a Debian generic cloud image overlay with a NoCloud seed ISO for first-boot bootstrap

Both workflows are intended for local QEMU-based validation and rely on the same shared SSH/test helpers.

## What this repository contains

- `Taskfile.yml` — convenience tasks for ISO and cloud-image build/test flows
- `preseed.cfg.tmpl` — the unattended Debian installer template used by the ISO flow
- `seed/user-data` — cloud-init template used by the cloud-image flow
- `scripts/build.sh` — downloads, verifies, modifies, and rebuilds the Debian installer ISO
- `scripts/test.sh` — boots the generated ISO in QEMU and validates the installed system
  plus first-boot cloud-init and `sysinit` bootstrap behavior
- `scripts/build-image.sh` — downloads the Debian generic cloud image, generates a NoCloud seed ISO, and creates a QCOW2 overlay
- `scripts/test-image.sh` — boots the cloud image in QEMU and validates the first-boot bootstrap path
- `scripts/lib/common.sh` — shared SSH key discovery, cloud-init rendering, and QEMU helper functions
- `scripts/lib/cloud-image-test.sh` — shared cloud-image test harness

## What each workflow does

### Installer ISO workflow

The custom ISO:

- starts from the current Debian 13 `amd64` netinst image
- injects a rendered preseed file into the installer initrd
- rewrites BIOS and UEFI boot entries so the installer runs automatically
- installs Debian with LVM on the selected target disk
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
- `DISK` / `INSTALL_DISK` — target install disk inside the ISO guest, default `/dev/vda`
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
