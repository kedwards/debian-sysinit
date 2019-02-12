# keca Init
Script to initialize my desktop

## Description

Script to setup [Ansible](http://www.ansible.com/), which then configres my dektop system.

## Installation

* Run the following command:

```
curl -s https://raw.githubusercontent.com/kedwards/keca_init/master/install.sh | source /dev/stdin
```

or

```
bash <(curl -sL http://bit.ly/2oz3TN5)
```

Note: the previous command(s) will get a script from this repository and run it immediately, performing all the needed
steps to install everything (the same steps described in "Manual installation").
If you don't want to run it, you can do a manual installation.

-----

## Manual installation

* Go to your home directory:

```
cd ~
```

* Clone this repository:

```
git clone https://github.com/kedwards/keca_init
```

* Enter the repository directory:

```
cd keca_init
```

* Run the bootstrap script:

```
source ./install.sh
```

All the prerequisites will be installed and Ansible will run from: /usr/local/etc/ansible/.

A file /etc/ansible/hosts will be created with a default (127.0.0.1) host.

A file ~/.ansible.cfg will be created with default configurations, including setting paramiko as the transport to allow
using passwords.

A bootstrap script will be added to .zshrc in $HOME, every time you start babun it will update Ansible and setup the
environment. If you don't want to update Ansible every time (it takes some time), you can edit ~/.zshrc and set
BOOTSTRAP_ANSIBLE_UPDATE=0.

