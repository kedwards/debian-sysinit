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


RELEASE=$(cat /etc/os-release | grep '^ID=' | awk '{ split($0, a, "="); print a[2]}')
# CODENAME=$(lsb_release -cs)
CODENAME=eoan
ANSIBLE_URL="deb http://ppa.launchpad.net/ansible/ansible/${RELEASE} ${CODENAME} main"

#ANSIBLE_APT_LIST=/etc/apt/sources.list.d/ansible-${RELEASE}-ansible-${CODENAME}.list
ANSIBLE_APT_LIST=/etc/apt/sources.list.d/ansible-${RELEASE}-ansible-${CODENAME}.list

if [ "${RELEASE}" == 'ubuntu' ]
then
  echo "override due to focal release"
  # apt-add-repository --yes --update ppa:ansible/ansible
elif [ "${RELEASE}" == 'debian' ]
then
  echo "${ANSIBLE_URL}" | tee "${ANSIBLE_APT_LIST}"
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367
fi

apt-get update && apt-get install -y ansible

if [ ! -d /home/${SUDO_USER}/keca_sysinit ]
then
  git clone -b master --single-branch https://github.com/kedwards/keca_sysinit.git /home/${SUDO_USER}/keca_sysinit
  cd /home/${SUDO_USER}/keca_sysinit && git pull
fi

cd /home/${SUDO_USER}/keca_sysinit
su -c "ansible-playbook playbook.yml -e 'ansible_sudo_pass=${SUDO_PASS}'" ${SUDO_USER}
