#!/usr/bin/env bash
if [[ -e .kubeconfig ]] ; then
  rm .kubeconfig
fi
gcloud compute scp ubuntu@ks-dev-batch:/home/ubuntu/.kube/config ~/.kube/configs/gcp
kshim local gcp
kubectl create secret generic gcp-batch-key \
  --from-file=key.json=/Users/suderman/.secret/galaxy-batch-key.json \
  --namespace galaxy