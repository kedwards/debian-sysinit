# Molecule Testing for Sysinit Role

This directory contains Molecule scenarios for testing the `sysinit` Ansible role.

## Overview

The Molecule tests focus on:

1. **Idempotency Testing**: Ensures that running the role multiple times produces the same result
2. **File Creation**: Verifies that expected files and directories are created with correct permissions
3. **System Integration**: Tests hosts file modifications and other system-level changes
4. **Cross-Platform**: Tests on Debian/Ubuntu, Arch, Fedora, and CentOS containers

## Test Scenarios

### Default Scenario (`molecule/default/`)

The default scenario tests:
- Directory structure creation (`/opt/withreach/*`)
- File creation with appropriate permissions
- Hosts file modifications with idempotency
- SSH key setup during preparation
- Essential package installation verification

## Running Tests

### Prerequisites

```bash
pip install "molecule[docker]" molecule-plugins[docker] pytest-testinfra
```

### Full Test Suite

```bash
molecule test
```

### Individual Test Steps

```bash
# Create test instances
molecule create

# Prepare test environment
molecule prepare

# Run the role
molecule converge

# Test idempotency (run role again and verify no changes)
molecule idempotence

# Run verification tests
molecule verify

# Clean up
molecule destroy
```

### Check Syntax Only

```bash
molecule syntax
```

## Test Structure

- `molecule.yml`: Main configuration defining platforms and test sequence
- `converge.yml`: Playbook that applies the role being tested
- `prepare.yml`: Setup required for testing environment
- `side_effect.yml`: Tests for unintended changes
- `tests/test_default.py`: Python tests using testinfra
- `requirements.yml`: Ansible dependencies
