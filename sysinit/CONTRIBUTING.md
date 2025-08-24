# Contributing to sysinit

Thank you for your interest in contributing to sysinit! This document provides guidelines and instructions for contributors.

## Development Setup

### Prerequisites

- Python 3.8 or higher
- Git
- Ansible
- shellcheck (for shell script linting)

### Setting Up Pre-commit Hooks

This project uses pre-commit hooks to ensure code quality and security. These hooks will run automatically before each commit to:

- Detect secrets and sensitive information
- Lint Ansible playbooks and roles
- Check shell scripts for common issues
- Format and validate YAML files

#### Installing Pre-commit

1. **Install development dependencies**:

   Using the provided requirements file (recommended):
   ```bash
   pip install -r requirements-dev.txt
   ```

   Or install pre-commit individually (choose one method):

   Using pip:
   ```bash
   pip install pre-commit
   ```

   Using conda:
   ```bash
   conda install -c conda-forge pre-commit
   ```

   Using your system package manager:
   ```bash
   # Ubuntu/Debian
   sudo apt install pre-commit

   # macOS with Homebrew
   brew install pre-commit

   # Arch Linux
   sudo pacman -S pre-commit
   ```

2. **Install the pre-commit hooks**:
   ```bash
   pre-commit install
   ```

3. **Install additional dependencies**:

   Install detect-secrets for secret scanning:
   ```bash
   pip install detect-secrets
   ```

   Install ansible-lint for Ansible linting:
   ```bash
   pip install ansible-lint
   ```

   Install shellcheck for shell script linting:
   ```bash
   # Ubuntu/Debian
   sudo apt install shellcheck

   # macOS with Homebrew
   brew install shellcheck

   # Arch Linux
   sudo pacman -S shellcheck
   ```

#### Running Pre-commit Hooks

- **Automatic execution**: Hooks will run automatically when you commit changes
- **Manual execution**: Run hooks on all files:
  ```bash
  pre-commit run --all-files
  ```
- **Run specific hook**:
  ```bash
  pre-commit run detect-secrets
  pre-commit run ansible-lint
  pre-commit run shellcheck
  ```

#### Secret Detection Setup

The project uses detect-secrets to prevent accidental commits of sensitive information:

1. **Initialize the secrets baseline** (if needed):
   ```bash
   detect-secrets scan --baseline .secrets.baseline
   ```

2. **Update the baseline** when adding legitimate secrets or configurations:
   ```bash
   detect-secrets scan --baseline .secrets.baseline --force-use-all-plugins
   ```

3. **Audit detected secrets**:
   ```bash
   detect-secrets audit .secrets.baseline
   ```

### Development Workflow

1. **Fork and clone** the repository
2. **Create a feature branch** from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Set up pre-commit hooks** (see above)
4. **Make your changes** following the project conventions
5. **Test your changes** locally
6. **Commit your changes** (pre-commit hooks will run automatically)
7. **Push your branch** and create a pull request

### Code Quality Standards

#### Ansible Best Practices

- Use descriptive task names
- Follow YAML formatting conventions (2-space indentation)
- Use `ansible-lint` recommendations
- Test roles with different target systems when possible
- Document variables and their purposes

#### Shell Script Guidelines

- Use proper shebang (`#!/bin/bash` or `#!/bin/sh`)
- Follow shellcheck recommendations
- Use proper error handling (`set -euo pipefail`)
- Quote variables to prevent word splitting
- Use meaningful function and variable names

#### Security Guidelines

- Never commit secrets, API keys, or sensitive configuration
- Use Ansible Vault for sensitive data
- Review the detect-secrets output carefully
- Use placeholder values in documentation examples

### Troubleshooting Pre-commit Issues

#### Common Issues and Solutions

1. **Pre-commit hook failed due to secrets detection**:
   - Review the detected secrets carefully
   - If it's a false positive, update the `.secrets.baseline` file
   - If it's a real secret, remove it and use proper secret management

2. **Ansible-lint failures**:
   - Review the specific lint errors
   - Fix formatting and best practice violations
   - Some rules can be skipped with comments if justified

3. **Shellcheck failures**:
   - Address shell script issues reported
   - Use proper quoting and error handling
   - Some checks can be disabled with comments if necessary

4. **Hook installation issues**:
   - Ensure you're in the repository root directory
   - Try reinstalling: `pre-commit uninstall && pre-commit install`
   - Check that required tools are installed and in PATH

#### Bypassing Hooks (Not Recommended)

In exceptional cases, you can bypass pre-commit hooks:
```bash
git commit --no-verify -m "Your commit message"
```

**Note**: This should only be used in emergencies and the issues should be fixed in a follow-up commit.

### Getting Help

- Open an issue for bugs or feature requests
- Check existing issues and pull requests first
- Provide clear reproduction steps for bugs
- Include relevant system information (OS, Python version, etc.)

## CI/CD Pipeline

The project uses continuous integration to ensure code quality. All pull requests must pass:

- Pre-commit hook validations
- Secret scanning checks
- Ansible linting
- Shell script validation

Violations of these checks will cause the CI pipeline to fail and prevent merging.
