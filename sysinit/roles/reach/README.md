# Sysinit Role

[![Ansible Galaxy](https://img.shields.io/ansible/role/sysinit.svg)](https://galaxy.ansible.com/kedwards/sysinit)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/kedwards/sysinit/blob/main/LICENSE)

An Ansible role for Reach system initialization and development environment configuration. This role automates the setup of development environments by cloning required repositories,
configuring local hosts, setting up pre-commit hooks.

## Purpose

This role is designed to:
- Initialize and configure development environments
- Clone and maintain required repositories
- Set up local development hosts for testing
- Install and configure pre-commit hooks

## Requirements

- Ansible >= 2.9
- SSH key configured for Git operations (`~/.ssh/id_rsa`) or (`~/.ssh/id_ed25519`)
- Sudo privileges for host file modifications
- Python 3 and pip3 for pre-commit installation

## Supported Platforms

- Ubuntu (focal, jammy)
- Debian (bullseye, bookworm)
- Enterprise Linux 8, 9

## Role Variables

All variables are defined in `defaults/main.yml` and can be overridden:

### Directory Configuration
```yaml
# Base directory for withreach development
withreach_dir: "{{ lookup('env','HOME') }}/withreach"

# Development repositories location
dev_repos_dir: "{{ withreach_dir }}/dev/repos"
v2_dir: "{{ dev_repos_dir }}/v2"

```

### Repository Configuration
```yaml
# Main DevOps repository
devops_repo: "git@github.com:withreach/reach-devops.git"

# Repository management script
repo_script: "{{ withreach_dir }}/bin/getRepos.sh"
```

### Configuration Files
```yaml
# VS Code settings
vscode_settings_example: "{{ v2_dir }}/.vscode/settings-example.json"
vscode_settings: "{{ v2_dir }}/.vscode/settings.json"

# Environment files
env_example: "{{ withreach_dir }}/dev/env.example"
env_file: "{{ withreach_dir }}/dev/.env"

# Local configuration
config_local_sample: "{{ v2_dir }}/config_local.sample.yaml"
config_local: "{{ v2_dir }}/config_local.yaml"
```

### Host Configuration
```yaml
# Marker for development hosts in /etc/hosts
hosts_marker: "# Local Development"

# List of development hosts to add
dev_hosts:
  - admin.rch.local
  - admin-api.rch.local
  - checkout.rch.local
  - portal.rch.local
  - reports.rch.local
  - stash.rch.local
  - redirect.rch.local
```

## Dependencies

This role has no external role dependencies but requires the following Ansible collections:
- `community.general`
- `community.docker` (if using Docker-related tasks)

## Usage Example

### Basic Playbook
```yaml
---
- name: Initialize Development Environment
  hosts: localhost
  become: yes
  roles:
    - reach.sysinit
```

### With Custom Variables
```yaml
---
- name: Initialize Development Environment
  hosts: localhost
  become: yes
  vars:
    withreach_dir: "/opt/withreach"
    dev_hosts:
      - custom.local
      - api.custom.local
  roles:
    - reach.sysinit
```

### With Tags
```yaml
---
- name: Initialize Development Environment
  hosts: localhost
  become: yes
  roles:
    - reach.sysinit
  tags:
    - devops
    - repos
    - hosts
```

### Command Line Usage
```bash
# Run the full role
ansible-playbook -i inventory playbook.yml

# Run specific tasks
ansible-playbook -i inventory playbook.yml --tags "devops,hosts"

# Check mode (dry run)
ansible-playbook -i inventory playbook.yml --check

# Skip host modifications
ansible-playbook -i inventory playbook.yml --skip-tags "hosts"
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with different distributions
5. Submit a pull request

## License

MIT

## Author Information

This role was created by kedwards for system initialization and development environment setup.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and changes.
