#!/usr/bin/env bash

if [ ! -d ~/keca_init ]
then
  git clone -b master --single-branch https://github.com/kedwards/keca_init.git ~/keca_init
  cd ~/keca_init
else
  cd ~/keca_init
  git pull
fi

source init.sh
ansible-playbook plays/keca.yml
