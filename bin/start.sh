#!/usr/bin/env bash

#BRANCH=41-fix-nfs
BRANCH=${BRANCH:-new-gcp-batch-runner-testing}
SERVER=${SERVER:-ks-batch-test}
REPO=${REPO:-https://github.com/ksuderman/galaxy-k8s-boot}

echo "Launching ${SERVER}"

bin/launch_vm.sh $SERVER \
  --git-repo $REPO \
  --git-branch $BRANCH \
  --disk-size 256 \
  -f values/values.yml \
  -f values/batch.yml \
  -f values/rules.yml \
  -f values/resource-params.yml \
  -f values/v26.0.yml

#  -f values/wait.yml \
#  -f values/v25.1-batch.yml

