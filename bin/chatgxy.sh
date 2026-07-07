#!/usr/bin/env bash

# The SERVER and CLOUD variables MUST BE set.
CLOUD=chatgxy
SERVER=ks-${CLOUD}-test

# Deploy the galaxy-min:dev image (mixins/dev.yml) because ChatGXY is only
# available in Galaxy dev, not the released images.
MIXINS=(dev multiuser admins logo)

# Enable ChatGXY with a self-hosted, CPU-only Ollama engine behind LiteLLM.
# AI_MASTER_KEY is left unset so launch_vm.sh auto-generates one.
AI_BACKEND=ollama-cpu

# Bigger data disk with reserved headroom so Galaxy keeps ample storage while
# the Ollama model cache and RabbitMQ (which share this disk) have room.
# 512GB -> ~476Gi pool, minus 64Gi reserve -> ~412Gi to Galaxy.
DISK_SIZE=512
NFS_RESERVE=64

# The chatgxy branch lives on the personal fork used for test deploys; push it
# there before launching (ansible-pull fetches REPO@BRANCH on the VM).
REPO=https://github.com/ksuderman/galaxy-k8s-boot
BRANCH=chatgxy

# Source the base script so the hi function is defined for the DESCRIPTION
DIR=$(dirname $(realpath $0))
source $DIR/start_base.sh

DESCRIPTION=$(cat <<EOF
    Quick-start wrapper around $(hi launch_vm.sh) with preset defaults for
    launching a Galaxy Kubernetes VM with ChatGXY enabled, backed by a
    self-hosted CPU-only Ollama engine behind a LiteLLM front door.
EOF
)
main "$@"
