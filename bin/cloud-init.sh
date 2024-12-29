#!/bin/bash

OWNER=ksuderman
NAME=galaxy-k8s-boot
REPO=${REPO:-https://github.com/$OWNER/$NAME.git}
BRANCH=${BRANCH:-1-dockerize-rke}

cd /home/ubuntu
git clone $REPO --branch $BRANCH
cd $NAME
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cd ../
chown -R ubuntu:ubuntu $NAME

