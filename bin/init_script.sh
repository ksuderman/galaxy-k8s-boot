#!/bin/bash

# Ensure the script runs with root privileges
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

RESERVED_CORES=2
RESERVED_MEM_MB=6144

sudo apt update
sudo apt install -y software-properties-common git
sudo apt-add-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible

git clone https://github.com/ksuderman/galaxy-k8s-boot.git
cd galaxy-k8s-boot

sed -i "s|extra_server_args=\"--tls-san localhost --disable traefik --v=4\"|extra_server_args=\"--tls-san $(curl -s http://169.254.169.254/latest/meta-data/public-ipv4) --disable traefik --v=4\"|" inventories/localhost

ansible-playbook -i inventories/localhost playbook.yml --extra-vars "kube_cloud_provider=aws" --extra-vars "job_max_cores=$(($(nproc) - $RESERVED_CORES))" --extra-vars "job_max_mem=$(($(free -m | awk '/^Mem:/{print $2}') - $RESERVED_MEM_MB))"
