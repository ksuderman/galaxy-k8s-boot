#!/bin/bash

# Ensure the script runs with root privileges
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

#-------------------------------
# CloudMC configuration
#-------------------------------
# Application is either galaxy or pulsar
APPLICATION=galaxy
GALAXY_API_KEY=changeme
PULSAR_API_KEY=changeme
#-------------------------------
RESERVED_CORES=2
RESERVED_MEM_MB=6144

sudo apt update
sudo apt install -y software-properties-common git
sudo apt-add-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible

git clone https://github.com/galaxyproject/galaxy-k8s-boot.git /home/$USER/galaxy-k8s-boot
cd /home/$USER/galaxy-k8s-boot

cat inventories/localhost.template | sed "s/__HOST__/$(curl -s ifconfig.me)/" | sed "s/__USER__/$USER/" > inventories/localhost

ansible-playbook -i inventories/localhost playbook.yml --extra-vars "job_max_cores=$(($(nproc) - $RESERVED_CORES))" --extra-vars "job_max_mem=$(($(free -m | awk '/^Mem:/{print $2}') - $RESERVED_MEM_MB))" --extra-vars "application=$APPLICATION" --extra-vars "galaxy_api_key=$GALAXY_API_KEY" --extra-vars "pulsar_api_key=$PULSAR_API_KEY"
