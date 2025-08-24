# SSH Agent Automation for Ansible

This playbook now includes automatic SSH agent setup to handle GitHub authentication seamlessly.

## What's New

The playbook now automatically:

1. **Starts SSH agent** if not already running
2. **Creates a helper script** at `~/.ssh/setup-agent.sh` 
3. **Sets up environment** for SSH key authentication
4. **Runs git operations** with proper SSH agent context

## Usage Options

### Option 1: Use the Wrapper Script (Recommended)

```bash
# This handles SSH agent setup automatically
./run-playbook.sh -K
```

The wrapper script will:
- Start SSH agent if needed
- Prompt for your SSH key passphrase
- Run the playbook with proper environment

### Option 2: Manual Setup

If you prefer to manage SSH agent manually:

```bash
# Start SSH agent and add key
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_rsa

# Run playbook normally
ansible-playbook playbook.yml -K
```

### Option 3: Use the Generated Helper Script

The playbook creates a helper script at `~/.ssh/setup-agent.sh`:

```bash
# Set up SSH agent
~/.ssh/setup-agent.sh

# Source the environment
source ~/.ssh/agent-env

# Run playbook
ansible-playbook playbook.yml -K
```

## Files Created

- `~/.ssh/setup-agent.sh` - SSH agent setup script
- `~/.ssh/agent-env` - SSH agent environment variables
- `./run-playbook.sh` - Wrapper script for running playbook

## How It Works

1. **SSH Configuration Tasks**: The `ssh.yml` tasks now automatically set up SSH agent
2. **Git Tasks**: All git operations run as user (not root) with `become: no`
3. **Environment Variables**: SSH agent variables are passed to git tasks
4. **Key Detection**: Supports both RSA (`id_rsa`) and Ed25519 (`id_ed25519`) keys

## Troubleshooting

### If git still fails with permission errors:

1. Check if keys are loaded:
   ```bash
   source ~/.ssh/agent-env
   ssh-add -l
   ```

2. Test GitHub connection:
   ```bash
   source ~/.ssh/agent-env
   ssh -T git@github.com
   ```

3. Manually add your key:
   ```bash
   source ~/.ssh/agent-env
   ssh-add ~/.ssh/id_rsa
   ```

### If SSH agent isn't working:

1. Kill any existing agents:
   ```bash
   pkill ssh-agent
   rm ~/.ssh/agent-env
   ```

2. Use the wrapper script:
   ```bash
   ./run-playbook.sh -K
   ```

## Benefits

- ✅ **No more manual SSH setup** before running playbook
- ✅ **Automatic SSH agent management**
- ✅ **Works across terminal sessions**
- ✅ **Secure passphrase handling**
- ✅ **Clear error messages and instructions**
