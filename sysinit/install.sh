#!/usr/bin/env bash

if [ ! -d ~/keca_init ]
then
  git clone -b master --single-branch https://github.com/kedwards/keca_init.git ~/keca_init
else
  cd ~/keca_init
  git pull
fi

source ~/keca_init/init.sh
