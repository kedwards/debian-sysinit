#!/bin/zsh

# start some needed services if on wsl
if [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
  sudo ln -fs /run/resolvconf/resolv.conf /etc/resolv.conf
  sudo service resolvconf start >/dev/null 2>&1

  if ! [ -f /var/run/docker.pid ]; then
    (sudo dockerd -l fatal &)
  fi

  sudo service docker start >/dev/null 2>&1
fi

# load profile scripts
if [ -d ~/.profile.d ]; then
  for i in ~/.profile.d/*; do
    if [ -f "$i" ]; then
      source $i
    fi
  done
fi
