#!/usr/bin/env bash

SYSINIT_PATH=~/sysinit
RELEASE=$(cat /etc/os-release | grep '^ID=' | awk '{ split($0, a, "="); print a[2]}')
CODENAME=$(lsb_release -cs)

sudo apt-get install -y git

[ ! -d ~/.pyenv ] && curl https://pyenv.run | bash

if [ ! "$(grep '# Load pyenv automatically' ~/.bash_profile)" ]; then
  cat << EOF >> ~/.bash_profile 
  
# Load pyenv automatically
export PYENV_ROOT="\$HOME/.pyenv"
export PATH="\$PYENV_ROOT/bin:\$LOCAL_BIN_PATH:\$PATH"
eval "\$(pyenv init -)"
eval "\$(pyenv virtualenv-init -)"
EOF
fi

. ~/.bash_profile

[ -d "${SYSINIT_PATH}" ] || git clone -b main --single-branch https://github.com/kedwards/sysinit.git "${SYSINIT_PATH}"
cd ${SYSINIT_PATH}

pyenv virtualenv sysinit && pyenv activate sysinit

pip install -r requirements.txt
ansible-galaxy install -r requirements.yml

[ -f /etc/apt/keyrings/docker.gpg ] || curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get autoremove -y

ansible-playbook playbook.yml -K --ask-vault-pass --tags core
