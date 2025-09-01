#!/usr/bin/env bash

# start some needed services if on wsl
if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
  sudo ln -fs /run/resolvconf/resolv.conf /etc/resolv.conf
  sudo service resolvconf start >/dev/null 2>&1
fi

if ! [ -f /var/run/docker.pid ]; then
  (sudo dockerd -l fatal &)
fi
sudo service docker start >/dev/null 2>&1

# Start ssh-agent on login
SSH_ENV="$HOME/.ssh/agent-environment"

function start_agent {
  echo "Initialising new SSH agent..."
  /usr/bin/ssh-agent | sed 's/^echo/#echo/' >"${SSH_ENV}"
  chmod 600 "${SSH_ENV}"
  . "${SSH_ENV}" >/dev/null
  /usr/bin/ssh-add >/dev/null 2>&1
}

# Source SSH settings, if applicable
if [ -f "${SSH_ENV}" ]; then
  . "${SSH_ENV}" >/dev/null
  #ps ${SSH_AGENT_PID} doesn't work under cywgin
  ps -ef | grep ${SSH_AGENT_PID} | grep ssh-agent$ >/dev/null || {
    start_agent >/dev/null 2>&1
  }
else
  start_agent >/dev/null 2>&1
fi

if [ -n "$BASH_VERSION" ]; then
  # include .bashrc if it exists
  if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
  fi
fi
