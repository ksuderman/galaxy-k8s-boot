#!/usr/bin/env bash

# Integration test instance: GalaxyAI (Vertex/Gemini) + Interactive Tools (incl.
# Orbit) + GPU jobs on GCP Batch, all on one cluster. Deploys from the `isis`
# branch, which merges `batch-gpu` (GPU Batch runner + TPV gpu routing) with
# `interactive-tools` (AI backends, TLS/hostname, IT proxy + wildcard certs).

REPO=https://github.com/ksuderman/galaxy-k8s-boot
BRANCH=isis

# The SERVER and CLOUD variables MUST BE set.
CLOUD=isis
SERVER=ks-${CLOUD}-test

# No local model engine (Vertex serves the LLM, Batch serves the GPU jobs), so a
# standard machine is plenty -- same shape as the gemini/its instances.
MACHINE_TYPE=t2d-standard-8

# Route GalaxyAI to Google Vertex AI (Gemini) via the LiteLLM front door. LiteLLM
# authenticates with the VM service account (ADC over the GCE metadata server) --
# no API key. PREREQ: the VM service account needs roles/aiplatform.user.
#
# AI_MASTER_KEY is pinned (NOT auto-generated) because mixins/orbit-it.yml
# hardcodes LOOM_LLM_API_KEY with the same value -- Galaxy IT env vars are
# literals (no secretKeyRef), so Orbit can only reach LiteLLM if the two match.
AI_BACKEND=vertex
AI_MASTER_KEY=sk-its-orbit-test

# HTTPS + stable IP. ks-isis-ip-east4 (34.85.149.203) is a reserved static IP in
# us-east4. PREREQ: DNS for isis.galaxy.useanvil.org -> 34.85.149.203, and (for
# ITs) the delegated interactivetool.isis.galaxy.useanvil.org Cloud DNS zone --
# the playbook manages the zone, but the NS delegation must exist in the parent.
ZONE=us-east4-c
ADDRESS=ks-isis-ip-east4
GALAXY_HOSTNAME=isis.galaxy.useanvil.org
ACME_EMAIL=suderman@jhu.edu
EXPOSE_LITELLM=true
ENABLE_INTERACTIVE_TOOLS=true

# Mixin order matters (later -f wins on merge):
#   its       -- GalaxyAI branding/tuning for the Vertex backend (proven on `its`)
#   orbit-it  -- registers Orbit as a custom Interactive Tool
#   batch-gpu -- MUST follow `its`: overrides the image with ksuderman/galaxy-gpu
#                (GPU Batch runner + ChatGXY, both verified in that build) and
#                adds the TPV gpus routing + gpu_boot_image rule
MIXINS=(its orbit-it batch-gpu postinstall-ks)

# Galaxy's NFS PVC plus co-tenant PVCs (RabbitMQ etc.); a reserve keeps Galaxy
# from claiming the whole disk.
DISK_SIZE=1024
NFS_RESERVE=64

# Source the base script so the hi function is defined for the DESCRIPTION
DIR=$(dirname $(realpath $0))
source $DIR/start_base.sh

DESCRIPTION=$(cat <<EOF
    Quick-start wrapper around $(hi launch_vm.sh) for the isis integration
    instance: GalaxyAI backed by Vertex AI (Gemini) behind LiteLLM, Interactive
    Tools (including Orbit) under a wildcard-TLS subdomain, and GPU jobs
    dispatched to GCP Batch on L4 VMs -- all on one cluster.
EOF
)
main "$@"
