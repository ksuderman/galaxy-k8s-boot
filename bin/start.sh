#!/usr/bin/env bash

BRANCH=${BRANCH:-pulsar-gcp}
SERVER=${SERVER:-ks-gcp-test}
REPO=${REPO:-https://github.com/ksuderman/galaxy-k8s-boot}

echo "Launching ${SERVER} with hybrid GCP Batch configuration"

bin/launch_vm.sh $SERVER \
  --git-repo $REPO \
  --git-branch $BRANCH \
  --disk-size 256 \
  -f values/values.yml \
  -f values/batch.yml \
  -f values/v25.1-batch.yml
#  -f values/resource-params.yml


