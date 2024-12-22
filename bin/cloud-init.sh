#!/bin/bash

#pwd > /home/ubuntu/cloud-init.start
#whoami >> /home/ubuntu/cloud-init.start
cd /home/ubuntu
git clone https://github.com/ksuderman/galaxy-k8s-boot --branch 1-docker
cd galaxy-k8s-boot
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cd ../
chown -R ubuntu:ubuntu galaxy-k8s-boot
#touch /home/ubuntu/cloud-init.end

