sysinit
=======

Ansible role for system initialization and tool installation.

Requirements
------------

- Ansible 2.9+
- Target systems: Ubuntu, Debian, Arch Linux
- Internet connectivity for downloading tools
- GitHub API token (recommended for higher rate limits)

Role Variables
--------------

The following variables can be set to customize the role behavior:

### Core Variables

- `upgrade`: (boolean, default: `false`) - Forces reinstallation/upgrade of tools even if they already exist
- `github_token`: (string, optional) - GitHub API token for accessing release information

### Mise Plugin Configuration

- `sysinit_mise_plugins`: List of mise plugins to install
- `sysinit_mise_custom_plugins`: List of custom mise plugin configurations

Dependencies
------------

- `community.general` collection for GitHub release lookups
- `ansible.builtin` modules

Example Playbook
----------------

Basic usage:

```yaml
- hosts: servers
  become: true
  roles:
    - sysinit
```

With custom configuration:

```yaml
- hosts: servers
  become: true
  vars:
    upgrade: true
    github_token: "{{ vault_github_token }}"
  roles:
    - sysinit
```


License
-------

BSD
