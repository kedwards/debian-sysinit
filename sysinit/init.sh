#!/usr/bin/env bash

apt-get update 

apt-get install git make python-setuptools gcc python-dev libffi-dev libssl-dev python-packaging software-properties-common

if [ $(cat /etc/os-release | grep '^ID=' | awk '{ split($0, a, "="); print a[2]}') == 'ubuntu' ]
then
    apt-add-repository --yes --update ppa:ansible/ansible
elif [ ! -f /etc/apt/sources.list.d/ansible.list ]
then
  echo "deb http://ppa.launchpad.net/ansible/ansible/ubuntu trusty main" | tee /etc/apt/sources.list.d/ansible.list
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 93C4A3FD7BB9C367
fi

apt-get update
apt-get install ansible

