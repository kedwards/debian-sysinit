#!/usr/bin/env bash

if (( EUID != 0 ))
then
  echo "You must be root to run this file." 1>&2
  exit 100
fi

if [ -z "$1" ]
then
  echo "You must provide a sudo password." 1>&2
  exit 100
else
  SUDO_PASS=$1
fi

SYSINIT_PATH=/home/${SUDO_USER}/sysinit

apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367
RELEASE=$(cat /etc/os-release | grep '^ID=' | awk '{ split($0, a, "="); print a[2]}')

# hardcode codename to release of focal and not in ppa yet
CODENAME=$(lsb_release -cs)
# # CODENAME=eoan

ANSIBLE_URL="deb http://ppa.launchpad.net/ansible/ansible/ubuntu ${CODENAME} main"
ANSIBLE_APT_LIST=/etc/apt/sources.list.d/ansible-${CODENAME}.list

# if [ "${RELEASE}" == 'ubuntu' ] &&  [ $CODENAME === 'focal' ]
# then
#   # remove ppa
#   # apt-add-repository --yes --update ppa:ansible/ansible
#   echo "running"
# elif [ "${RELEASE}" == 'debian' ]
# then
#   echo "${ANSIBLE_URL}" | tee "${ANSIBLE_APT_LIST}"
# fi

apt-get update && apt-get install -y ansible

if [ ! -d ${SYSINIT_PATH} ]
then
  git clone -b master --single-branch https://github.com/kedwards/sysinit.git ${SYSINIT_PATH}
fi
cd ${SYSINIT_PATH} && git pull

# cd ${SYSINIT_PATH}

# ansible-galaxy install geerlingguy.nodejs && ansible-galaxy collection install community.general
ansible-galaxy collection install community.general
su -c "ansible-playbook playbook.yml -e 'ansible_sudo_pass=${SUDO_PASS}'" ${SUDO_USER}
