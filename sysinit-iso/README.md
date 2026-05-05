# sysinit-iso

Builds a custom Debian netinst ISO for unattended `sysinit` installs.

The generated ISO starts from the current Debian `amd64` netinst image, injects a rendered preseed file into the installer initrd, and rewrites the BIOS and UEFI bootloader entries so the installer runs automatically.

## What this repository contains

- `Taskfile.yml` — convenience tasks for building, cleaning, and running the QEMU-based test flow
- `preseed.cfg.tmpl` — the unattended Debian installer template
- `scripts/build.sh` — downloads, verifies, modifies, and rebuilds the ISO
- `scripts/test.sh` — boots the generated ISO in QEMU, completes an install, then verifies first boot over SSH
- `scripts/lib/common.sh` — shared SSH key discovery and test helpers

## What the generated installer does

By default, the custom ISO:

- installs Debian 13 (Trixie) from the current netinst image
- performs an unattended install using LVM on a target disk
- creates a `devops` user with password `devops`
- adds the user to `sudo` with passwordless sudo
- installs `openssh-server`, `sudo`, `cloud-init`, and `qemu-guest-agent`
- injects your SSH public key into the installed system
- enables SSH and `qemu-guest-agent`

## Prerequisites

For builds:

- `bash`
- `curl`
- `sha256sum`
- `python3`
- `xorriso`
- `cpio`
- `gzip`
- `dd`

For tests:

- `qemu-system-x86_64`
- `qemu-img`
- `ssh`
- KVM access is recommended for reasonable test speed

Optional:

- `task` if you want to use `Taskfile.yml`
- a local SSH public/private key pair in `~/.ssh/`, or a 1Password SSH agent

## SSH key handling

The build and test scripts try to discover SSH credentials automatically:

- public key: `SSH_PUBKEY` environment variable, then `~/.ssh/id_ed25519.pub`, then `~/.ssh/id_rsa.pub`, then the 1Password SSH agent
- private key for tests: `~/.ssh/id_ed25519`, then `~/.ssh/id_rsa`, then the 1Password SSH agent

If no usable SSH key is found, the build or test command exits with an error.

## Usage

### Build the custom ISO

Using Task:

```bash path=null start=null
task build
```

Using the script directly:

```bash path=null start=null
bash scripts/build.sh
```

The build script will:

1. download the current Debian `amd64` netinst ISO if it is not already cached in the repository root
2. verify its SHA256 checksum
3. render `preseed.cfg.tmpl` with your selected values
4. inject the rendered preseed into the installer initrd
5. rebuild the ISO as a new `*-sysinit.iso` artifact in the repository root

### Run the automated test

Using Task:

```bash path=null start=null
task test
```

Using the script directly:

```bash path=null start=null
TEST_ISO=./debian-13.4.0-sysinit.iso bash scripts/test.sh
```

The test flow:

1. creates a fresh qcow2 disk
2. boots the generated ISO in QEMU
3. waits for the unattended install to finish
4. boots the installed disk
5. connects over SSH and verifies the expected user, SSH, and sudo setup

## Common configuration

These environment variables are supported through `Taskfile.yml` and/or the scripts:

- `USER_NAME` — install user name, default `devops`
- `USER_PASSWORD` — install user password, default `devops`
- `SSH_PUBKEY` — explicit public key content to inject
- `SSH_PORT` — forwarded host SSH port for tests, default `2222`
- `QEMU_DISPLAY` — `gtk` or `none`
- `KEEP_TEST_DISK` — set to `1` to preserve the qcow2 disk after tests
- `DISK` / `INSTALL_DISK` — target install disk inside the guest, default `/dev/vda`
- `OUTPUT_ISO` — output path for the generated ISO when calling `scripts/build.sh` directly
- `TEST_ISO` — ISO path to boot when calling `scripts/test.sh` directly
- `TEST_DISK` — qcow2 path to use during testing

Examples:

```bash path=null start=null
USER_NAME=alice USER_PASSWORD=changeme task build
```

```bash path=null start=null
SSH_PORT=2223 QEMU_DISPLAY=none KEEP_TEST_DISK=1 task test
```

```bash path=null start=null
DISK=/dev/nvme0n1 OUTPUT_ISO=./custom-sysinit.iso bash scripts/build.sh
```

## Output artifacts

Typical generated files in the repository root:

- upstream Debian netinst ISO, for example `debian-13.4.0-amd64-netinst.iso`
- custom ISO, for example `debian-13.4.0-sysinit.iso`
- test disk image, for example `debian-13.4.0-sysinit.qcow2`

These artifacts are ignored by git.

## Notable implementation details

- The preseed file is placed inside `install.amd/initrd.gz`, so it is available early in the installer boot process.
- Both `isolinux` and `grub` configs are rewritten, so the ISO works for BIOS and UEFI boots.
- The original Debian ISO checksum is verified before any modification occurs.
- The rebuilt ISO refreshes `md5sum.txt` before packing the final image.

## Notes

- The defaults are convenient for local testing, not hardened production installs.
- Passwordless sudo and the default `devops/devops` credentials should be overridden for any real use.
