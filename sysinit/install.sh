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
ANSIBLE_URL="deb http://ppa.launchpad.net/ansible/ansible/ubuntu bionic main"
ANSIBLE_APT_LIST=/etc/apt/sources.list.d/download_ansible_launchpad_net.list
ANSIBLE_LIST=$(grep "${ANSIBLE_URL}" "${ANSIBLE_APT_LIST}")

if [ "${RELEASE}" == 'ubuntu' ]
then
  apt-add-repository --yes --update ppa:ansible/ansible
elif [ "${RELEASE}" == 'debian' ]
then
  echo "${ANSIBLE_URL}" | tee "${ANSIBLE_APT_LIST}"
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367
  
  aptget update && apt-get install -y git build-essential
  
  git clone git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git 
  
  cp linux-firmware/iwlwifi-* /lib/firmware/
  git clone https://git.kernel.org/pub/scm/linux/kernel/git/iwlwifi/backport-iwlwifi.git
  
  cd backport-iwlwifi
  make defconfig-iwlwifi-public
  make -j4
  make install
fi

apt-get update && apt-get install -y software-properties-common git ansible

if [ ! -d /home/${SUDO_USER}/keca_sysinit ]
then
  git clone -b master --single-branch https://github.com/kedwards/keca_sysinit.git /home/${SUDO_USER}/keca_sysinit
  cd /home/${SUDO_USER}/keca_sysinit && git pull
fi

cd /home/${SUDO_USER}/keca_sysinit
su -c "ansible-playbook playbook.yml -e 'ansible_sudo_pass=${SUDO_PASS}'" ${SUDO_USER}
