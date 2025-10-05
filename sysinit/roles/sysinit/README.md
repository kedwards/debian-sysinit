# Sysinit Role

[![Ansible Galaxy](https://img.shields.io/ansible/role/sysinit.svg)](https://galaxy.ansible.com/kedwards/sysinit)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/kedwards/sysinit/blob/main/LICENSE)

An Ansible role for system initialization and development environment configuration.

## Requirements

- Ansible >= 11.8.0
- SSH key configured for Git operations (`~/.ssh/id_rsa`) or (`~/.ssh/id_ed25519`)
- Git configured with global user.name and user.email
- Sudo privileges for host file modifications
- Python 3 and pip3 for pre-commit installation

## Supported Platforms

- Debian
- Ubuntu
- Fedora
- CentOs
- Arch

## Role Variables

All variables are defined in `defaults/main.yml` and can be overridden:

## Dependencies

This role has no external role dependencies but requires the following Ansible collections:
- `ansible.posix`
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
    - sysinit
```

### Command Line Usage
```bash
# Run the full role
ansible-playbook -i inventory playbook.yml

# Run specific tool installation
ansible-playbook -i inventory playbook.yml -e tools='chrome dbeaver'

# Check mode (dry run)
ansible-playbook -i inventory playbook.yml --check

# Provide Git identity to the playbook
ansible-playbook -i inventory playbook.yml -K -e "git_user_name=Your Name" -e "git_user_email=you@example.com"
```

**Note:** If you use the top-level `install.sh`, you can instead export:
```bash
export GIT_USER_NAME="Your Name"
export GIT_USER_EMAIL="you@example.com"
```
The installer will pass these values into Ansible for you.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with distributions
5. Submit a pull request
