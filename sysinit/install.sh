#!/usr/bin/env bash

set -o errexit
# set -o nounset
set -o pipefail

if (( EUID != 0 ))
then
  echo "You must be root to run this file." 1>&2
  exit 100
fi

if [ -z "$1" ]
then
  echo "You must provide a sudo password." 1>&2
  exit 101
else
  SUDO_PASS=$1
fi

SYSINIT_PATH=/home/${SUDO_USER}/sysinit
RELEASE=$(cat /etc/os-release | grep '^ID=' | awk '{ split($0, a, "="); print a[2]}')
CODENAME=$(lsb_release -cs)

if [ -f /usr/bin/pkcon ]
then
#   pkcon update
  apt-get install -y ansible git
fi


if [ ! -d ${SYSINIT_PATH} ]
then
  git clone -b master --single-branch https://github.com/kedwards/sysinit.git ${SYSINIT_PATH}
  cd ${SYSINIT_PATH}
else
  cd ${SYSINIT_PATH} && \
  git pull
fi

sudo -u ${SUDO_USER} ansible-galaxy collection install community.general
su -c "ansible-playbook -i inventory/hosts.yml project/playbook.yml --tags req -e 'ansible_sudo_pass=${SUDO_PASS}'" ${SUDO_USER}
