#!/usr/bin/env bash

# The SERVER and CLOUD variables MUST BE set.
CLOUD=gpu
SERVER=ks-${CLOUD}-test

# GPU zone + machine. T4 lives in us-east4-a/-b (NOT the default us-east4-c).
# n1-standard-8 (30GB) leaves host-RAM headroom for the full Galaxy stack while
# the model runs in GPU VRAM. launch_vm.sh auto-attaches a T4 (GPU_TYPE default)
# with maintenance-policy=TERMINATE because AI_BACKEND=ollama-gpu.
ZONE=us-east4-a
MACHINE_TYPE="n1-standard-8"

# GPU machine image with the NVIDIA driver (610, T4) + container toolkit baked in
# (built from ks-gpu-test on 2026-07-08). Avoids a fragile ~10min driver install
# at boot; gpu_setup.yml then only verifies the driver is present.
MACHINE_IMAGE="galaxy-k8s-boot-gpu-debian12-v2026-07-09"

# Self-hosted Ollama on a GPU behind LiteLLM, running qwen2.5:7b (ollama_model_gpu).
# The playbook installs the NVIDIA driver + container toolkit at boot (gpu_setup)
# and deploys the NVIDIA device plugin. AI_MASTER_KEY is auto-generated.
AI_BACKEND=ollama-gpu

# ChatGXY/GalaxyAI dev image + branding + the CPU-oriented agent tuning (safe for
# the 7b model too; relax later if qwen2.5:7b handles tool-calling well on GPU).
MIXINS=(gpu)

# Ollama's model cache shares the data disk (blockstorage); reserve headroom so
# Galaxy does not claim the whole disk.
DISK_SIZE=256
NFS_RESERVE=32

# The chatgxy branch (which carries ai_backend=ollama-gpu support) lives on the
# personal fork; push it before launching (ansible-pull fetches REPO@BRANCH).
REPO=https://github.com/ksuderman/galaxy-k8s-boot
BRANCH=chatgxy

# Source the base script so the hi function is defined for the DESCRIPTION
DIR=$(dirname $(realpath $0))
source $DIR/start_base.sh

DESCRIPTION=$(cat <<EOF
    Quick-start wrapper around $(hi launch_vm.sh) with preset defaults for
    launching a Galaxy Kubernetes VM with GalaxyAI enabled, backed by a
    self-hosted GPU Ollama engine (NVIDIA T4) behind a LiteLLM front door.
EOF
)
main "$@"
