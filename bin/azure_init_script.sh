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
USER=ubuntu
HOST=$(curl -s ipconfig.me)

#-------------------------------
RESERVED_CORES=2
RESERVED_MEM_MB=6144

if [[ ! -e /mnt/block_storage ]] ; then
  mdkir /mnt/block_storage
fi
mount /dev/sdc /mnt/block_storage

sudo apt update
sudo apt install -y software-properties-common git
sudo apt-add-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible

git clone https://github.com/ksuderman/galaxy-k8s-boot.git --branch azure
cd galaxy-k8s-boot

cat inventories/locahost.template | sed "s/__USER__/$USER/" | sed "s/__HOST__/$HOST/" > inventories/localhost

#sed -i "s|extra_server_args=\"--tls-san localhost --disable traefik --v=4\"|extra_server_args=\"--tls-san $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4) --disable traefik --v=4\"|" inventories/localhost

ansible-playbook -i inventories/localhost playbook.yml --extra-vars "kube_cloud_provider=azure" --extra-vars "job_max_cores=$(($(nproc) - $RESERVED_CORES))" --extra-vars "job_max_mem=$(($(free -m | awk '/^Mem:/{print $2}') - $RESERVED_MEM_MB))" --extra-vars "application=$APPLICATION" --extra-vars "galaxy_api_key=$GALAXY_API_KEY" --extra-vars "pulsar_api_key=$PULSAR_API_KEY"
