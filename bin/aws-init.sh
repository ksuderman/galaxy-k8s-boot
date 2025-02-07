#!/bin/bash
set -e

whomai > /run/whoami
sudo mkfs.ext4 /dev/nvme1n1
sudo mkdir -p /mnt/block_storage
sudo mount /dev/nvme1n1 /mnt/block_storage

sudo apt update
sudo apt-add-repository --yes --update ppa:ansible/ansible
sudo apt install -y software-properties-common git ansible

#-------------------------------
# CloudMC configuration
#-------------------------------
# Generate random API keys and store them someplace safe
cat /dev/urandom | tr -dc 'a-zA-Z0-9_+-' | head -c 32 > /root/galaxy_api_key && chmod 400 /root/galaxy_api_key
cat /dev/urandom | tr -dc 'a-zA-Z0-9_+-' | head -c 32 > /root/pulsar_api_key && chmod 400 /root/pulsar_api_key

# Application is either galaxy or pulsar
APPLICATION=galaxy
GALAXY_API_KEY=$(cat /root/galaxy_api_key)
PULSAR_API_KEY=$(cat /root/pulsar_api_key)
#-------------------------------
RESERVED_CORES=2
RESERVED_MEM_MB=6144
cd /home/ubuntu
git clone https://github.com/ksuderman/galaxy-k8s-boot.git --branch ks-testing
cd galaxy-k8s-boot
cat inventories/localhost.template | sed -i "s|__HOST__|$(curl -s ifconfig.me)|" > inventories/localhost
#ansible-playbook -i inventories/localhost playbook.yml --extra-vars "job_max_cores=$(($(nproc) - $RESERVED_CORES))" --extra-vars "job_max_mem=$(($(free -m | awk '/^Mem:/{print $2}') - $RESERVED_MEM_MB))" --extra-vars "application=$APPLICATION" --extra-vars "galaxy_api_key=$GALAXY_API_KEY" --extra-vars "pulsar_api_key=$PULSAR_API_KEY"

