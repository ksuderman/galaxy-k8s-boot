#!/usr/bin/env bash

BRANCH=${BRANCH:-pulsar-gcp}
SERVER=${SERVER:-ks-hybrid-test}
REPO=${REPO:-https://github.com/ksuderman/galaxy-k8s-boot}

echo "Restarting ${SERVER} with hybrid GCP Batch configuration (reusing existing data)"

bin/launch_vm.sh $SERVER \
  --git-repo $REPO \
  --git-branch $BRANCH \
  --disk-size 256 \
  --reuse-existing-data \
  -f values/hybrid-gcp-batch.yml \
  -f values/test-gcp-batch-comparison.yml \
  -f values/test-toolshed.yml
  