# debian-sysinit

Monorepo for Debian `sysinit` bootstrap workflows.

## Repository layout

- `sysinit-iso/` — current and supported implementation for Debian installer ISO and cloud-image bootstrap workflows
- `sysinit/` — deprecated legacy Ansible implementation retained for history, reference, and possible future rework

## Migration notes

This repository preserves the Git history of the original standalone repositories while consolidating them into one canonical location.

The initial import keeps each implementation independently runnable and does not attempt to merge or deduplicate their bootstrap logic.
