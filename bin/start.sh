#!/usr/bin/env bash

BRANCH=${BRANCH:-pulsar-gcp}
SERVER=${SERVER:-ks-gcp-test}
REPO=${REPO:-https://github.com/ksuderman/galaxy-k8s-boot}

cd $(dirname $(realpath $0))
echo "Launching ${SERVER} with hybrid GCP Batch configuration"

./launch_vm.sh $SERVER \
  --git-repo $REPO \
  --git-branch $BRANCH \
  --disk-size 256 \
  -f values/values.yml \
  -f values/wait.yml \
  -f values/v26.0.yml 
#  -f values/batch.yml \
#  -f values/rules.yml \
#  -f values/resource-params.yml
