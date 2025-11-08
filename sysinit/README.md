# Linux System Initialization

An opinionated script to initialize your Linux system.

## Distros

This release has been tested on the following distributions, and should work on all distros based from:

- Arch
- CentOS
- Debian
- Fedora
- Ubuntu

## Prerequisites (Mandatory)

Before running the installer, ensure you have:

- **Sudo privileges** on the machine
- **Git identity configured globally**:
  ```bash
  git config --global user.name "Your Name"
  git config --global user.email "you@example.com"
  ```

  or

  ```bash
  export GIT_USER_NAME="Your Name"
  export GIT_USER_EMAIL="you@example.com"
  ```

  *Why: The installer passes your Git identity into the Ansible role and will fail if not provided. It will prompt if missing, but will exit if you leave either value blank.*

- **An SSH key present and loadable by ssh-agent**:
  - Recommended to use ed25519 keys
  - Check for an existing key:
    ```bash
    ls ~/.ssh/id_ed25519 ~/.ssh/id_rsa
    ```
  - If you don't have one, generate a key:
    ```bash
    ssh-keygen -t ed25519 -C "your_email@example.com"
    ```
  - Add it to your agent (if needed):
    ```bash
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_ed25519
    ```
  *Why: The installer needs SSH access to clone private repositories. If no usable key is found, it exits with instructions to generate one.*

## Usage

**Option 1: One-liner (audited remotely)**
```bash
wget -O - https://raw.githubusercontent.com/kedwards/sysinit/refs/heads/main/install.sh | bash
```

**Option 2: Clone locally, review, then run**
```bash
git clone https://github.com/kedwards/sysinit.git
cd sysinit
./install.sh
```

**Option 3: Run Ansible directly (manual, for advanced users)**

The installer bootstraps tooling and a virtual environment for you; if you prefer, you can run the playbook directly:
- Ensure Python 3.11+ and dependencies are installed (uv/mise steps are handled by install.sh)
- Install dependencies:
  ```bash
  pip install -r requirements.txt
  ansible-galaxy install -r requirements.yml
  ```
- Pass Git identity to the playbook (required):
  ```bash
  ansible-playbook playbook.yml -K -e "git_user_name=Your Name" -e "git_user_email=you@example.com"
  ```

## Development

This project uses [Task](https://taskfile.dev) for automation. After cloning:

```bash
# Install dependencies
task install-deps

# Install pre-commit hooks
task install-hooks

# See all available tasks
task --list-all

# Run linting
task lint

# Run tests
task molecule-test
```

**Available Development Commands:**
- `task lint` - Run all linters (pre-commit, ansible-lint, shellcheck)
- `task syntax-check` - Ansible syntax validation
- `task molecule-test` - Full Molecule test suite
- `task molecule-converge` - Quick converge for development
- `task scan-secrets` - Detect secrets in code
- `task clean` - Remove build artifacts

**Notes:**
- The installer will start an ssh-agent and attempt to load a default SSH key (id_ed25519, id_rsa). If none are found or loadable, it exits with guidance.
- The playbook targets localhost by default and will ask for sudo (-K) to perform system changes.
