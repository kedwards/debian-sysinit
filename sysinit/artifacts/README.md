# Ansible Runner Artifacts

## Runner Artifacts Directory Hierarchy

This directory will contain the results of Runner invocation grouped under an identifier directory. This identifier can be supplied to Runner directly and if not given, an identifier will be generated as a UUID. This is how the directory structure looks from the top level:

```
├── artifacts
│   └── identifier
├── env
├── inventory
├── profiling_data
├── project
└── roles
```

The artifact directory itself contains a particular structure that provides a lot of extra detail from a running or previously-run invocation of Ansible/Runner:

```
├── artifacts
│   └── 37f639a3-1f4f-4acb-abee-ea1898013a25
│       ├── fact_cache
│       │   └── localhost
│       ├── job_events
│       │   ├── 1-34437b34-addd-45ae-819a-4d8c9711e191.json
│       │   ├── 2-8c164553-8573-b1e0-76e1-000000000006.json
│       │   ├── 3-8c164553-8573-b1e0-76e1-00000000000d.json
│       │   ├── 4-f16be0cd-99e1-4568-a599-546ab80b2799.json
│       │   ├── 5-8c164553-8573-b1e0-76e1-000000000008.json
│       │   ├── 6-981fd563-ec25-45cb-84f6-e9dc4e6449cb.json
│       │   └── 7-01c7090a-e202-4fb4-9ac7-079965729c86.json
│       ├── rc
│       ├── status
│       └── stdout
```

The rc file contains the actual return code from the Ansible process.

The status file contains one of three statuses suitable for displaying:

  success: The Ansible process finished successfully

  failed: The Ansible process failed

  timeout: The Runner timeout (see env/settings - Settings for Runner itself)

The stdout file contains the actual stdout as it appears at that moment.

