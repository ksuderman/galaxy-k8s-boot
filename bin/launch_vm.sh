#!/bin/bash

# Galaxy Kubernetes Boot VM Launch Script
# This script handles VM creation with automatic persistent disk management

set -e

# Default values
BOOT_DISK_SIZE="100GB"
DISK_SIZE="150GB"
POSTGRES_DISK_SIZE="10GB"
# GiB reserved on the NFS/block-storage disk so Galaxy's PVC does NOT claim the
# whole disk. Leaves room for co-tenant PVCs on that disk (Ollama model cache,
# RabbitMQ) plus filesystem overhead. galaxy_persistence_size = PV_SIZE - reserve.
NFS_RESERVE="${NFS_RESERVE:-30}"
# GPU selection for --ai-backend=ollama-gpu. The user asks for a GPU *model*
# (--gpu-type) and a desired vCPU count (--gpu-cpus); the script picks the right
# machine type and decides how the GPU is requested. Each GPU model lives in one
# machine family, and the family dictates the mechanism:
#   t4   -> N1 family, FLEXIBLE attach: n1-standard-<cpus> + --accelerator (count
#           = --gpu-count). Cheapest, 16GB VRAM, fits qwen2.5:7b (us-east4-a/-b).
#   l4   -> G2 family, BUNDLED:  g2-standard-<cpus>   (24GB VRAM, fits 14b).
#   a100 -> A2 family, BUNDLED:  a2-highgpu-<n>g      (40GB VRAM).
#   h100 -> A3 family, BUNDLED:  a3-highgpu-<n>g      (80GB VRAM).
# BUNDLED families ship the GPU with the machine type and reject --accelerator;
# --gpu-cpus is rounded up to the smallest valid size in the chosen family. GPUs
# cannot live-migrate, so maintenance-policy is forced to TERMINATE in every case.
GPU_TYPE="${GPU_TYPE:-t4}"        # t4 | l4 | a100 | h100
GPU_CPUS="${GPU_CPUS:-8}"         # desired vCPUs; rounded up to a valid machine size
GPU_COUNT="${GPU_COUNT:-1}"       # number of accelerators (T4/N1 flexible attach only)
# Optional override of the GPU Ollama model (role default ollama_model_gpu, normally
# qwen2.5:7b). Set via --gpu-model, e.g. qwen2.5:14b on an L4's 24GB of VRAM. Empty
# leaves the role default untouched.
GPU_MODEL="${GPU_MODEL:-}"
# Optional override of the Ollama model-cache PVC size (role default
# ollama_storage_size, 20Gi). Set via --ollama-storage-size, e.g. 40Gi for a ~20GB
# qwen2.5:32b that won't fit the 20Gi default. Empty leaves the role default untouched.
GPU_STORAGE="${GPU_STORAGE:-}"
DISK_TYPE="pd-balanced"
GALAXY_CHART="cloudve/galaxy"
GALAXY_CHART_VERSION="6.8.1"
GALAXY_DEPS_CHART="cloudve/galaxy-deps"
GALAXY_DEPS_VERSION="1.1.1"
GIT_BRANCH="anvil"
GIT_REPO="https://github.com/galaxyproject/galaxy-k8s-boot.git"
MACHINE_IMAGE="galaxy-k8s-boot-v2026-06-30"
MACHINE_TYPE="e2-standard-4"
MACHINE_TYPE_SET=false
PROJECT="anvil-and-terra-development"
VM_USER="debian"
ZONE="us-east4-c"
RESTORE_GALAXY=false
AI_BACKEND="none"
AI_MASTER_KEY=""
# HTTPS: when GALAXY_HOSTNAME is set, Galaxy is served over TLS at that FQDN via a
# Let's Encrypt cert (cert-manager). ADDRESS attaches a reserved GCP static IP (name
# or IP) so the VM's public IP matches the hostname's DNS record. ACME_EMAIL is the
# Let's Encrypt account email (required when a hostname is set).
GALAXY_HOSTNAME=""
ADDRESS=""
ACME_EMAIL=""
# Publish LiteLLM's OpenAI-compatible API under /llm on the HTTPS host (for Orbit and
# other OpenAI-compatible clients). Requires --hostname. Off by default.
EXPOSE_LITELLM=false
# Enable Galaxy Interactive Tools on the local cluster: routes interactive_tool.* to
# the KubernetesJobRunner and sets up the per-instance Cloud DNS zone + wildcard TLS.
# Requires --hostname (the IT subdomain derives from it). Off by default.
ENABLE_INTERACTIVE_TOOLS=false
# Provision the VM as a Spot (preemptible) instance: ~60-91% cheaper, but GCP can
# reclaim it at any time. Requires maintenance-policy=TERMINATE. Off by default.
SPOT="${SPOT:-false}"
# GCP Batch job-name prefix so Batch jobs are identifiable per cluster. Explicit
# --job-id-prefix wins; when empty it defaults to the sanitized instance name below.
JOB_ID_PREFIX="${JOB_ID_PREFIX:-}"
PROFILE=""
PROFILE_SET=false

# Parse command line arguments
DISK_NAME=""
DRY_RUN=""
POSTGRES_DISK_NAME=""
EPHEMERAL_ONLY=false
GALAXY_VALUES_FILES=()  # Array to hold multiple values files
INSTANCE_NAME=""
SSH_KEY=""

usage() {
    cat << EOF
Usage: $0 [OPTIONS] INSTANCE_NAME

Launch a Galaxy Kubernetes VM with automatic persistent disk management.

Required Arguments:
  INSTANCE_NAME       Name of the VM instance to create

Options:
  -b, --git-branch BRANCH           Git branch to deploy (default: $GIT_BRANCH)
  -d, --disk-name DISK_NAME         Name of NFS persistent disk (default: galaxy-data-INSTANCE_NAME)
      --dry-run                     Saves the cloud-init user data and exits
      --spot                        Provision a Spot (preemptible) VM: ~60-91% cheaper
                                    but reclaimable by GCP at any time (uses separate
                                    PREEMPTIBLE_* quota; forces maintenance-policy=TERMINATE)
  -e, --ephemeral-only              Create VM without persistent disk
  -f, --values FILE                 Helm values file (can be specified multiple times, default: values/values.yml)
  -i, --machine-image IMAGE         Machine image name (default: $MACHINE_IMAGE)
  -k, --ssh-key SSH_KEY             SSH public key for VM user (required)
  -u, --user USER                   VM user account name (default: $VM_USER)
  -m, --machine-type TYPE           Machine type (default: $MACHINE_TYPE)
  -p, --project PROJECT             GCP project ID (default: $PROJECT)
  -r, --git-repo REPO               Git repository URL (default: $GIT_REPO)
  -s, --disk-size SIZE              Size of NFS persistent disk (default: $DISK_SIZE)
      --nfs-reserve GIB             GiB reserved on the data disk so Galaxy's PVC does not
                                    claim the whole disk, leaving room for co-tenant PVCs
                                    (Ollama, RabbitMQ) (default: $NFS_RESERVE)
  -z, --zone ZONE                   GCP zone (default: $ZONE)
  --galaxy-chart CHART              Galaxy Helm chart location (default: $GALAXY_CHART)
  --galaxy-chart-version VERSION    Galaxy Helm chart version (default: $GALAXY_CHART_VERSION)
  --galaxy-deps-chart CHART         Galaxy dependencies chart location (default: $GALAXY_DEPS_CHART)
  --galaxy-deps-version VERSION     Galaxy dependencies chart version (default: $GALAXY_DEPS_VERSION)
  --postgres-disk DISK_NAME         Name of PostgreSQL disk (default: galaxy-postgres-INSTANCE_NAME)
  --postgres-disk-size SIZE         Size of PostgreSQL disk (default: $POSTGRES_DISK_SIZE)
  --restore-galaxy                  Auto-detect and restore Galaxy from existing data
  --profile PROFILE                 Post-install import profile file passed to galaxy-helm's
                                    postInstallJob.imports (sets galaxy_import_profile).
                                    Pass '' to disable post-install imports. When omitted the
                                    role default (files/profiles/anvil.yaml) is used.
  --ai-backend BACKEND              ChatGXY inference backend: none, ollama-cpu,
                                    ollama-gpu, vllm-gpu, external, vertex
                                    (default: $AI_BACKEND).
                                    Anything other than 'none' deploys a LiteLLM
                                    front door (and Ollama for the ollama-* options)
                                    and enables ChatGXY in Galaxy. Requires a Galaxy
                                    image that includes ChatGXY (e.g. add
                                    '-f mixins/dev.yml').
  --ai-master-key KEY               Key Galaxy presents to LiteLLM. Auto-generated
                                    when omitted and --ai-backend is not 'none'.
  --gpu-type TYPE                   GPU model for --ai-backend ollama-gpu: t4, l4,
                                    a100, h100 (default: $GPU_TYPE). Selects the
                                    machine family and how the GPU is attached.
  --gpu-cpus N                      Desired vCPUs for the GPU VM; rounded up to the
                                    smallest valid machine size in the GPU's family
                                    (default: $GPU_CPUS). Ignored if --machine-type
                                    is given explicitly.
  --gpu-count N                     Number of accelerators to attach (T4/N1 only;
                                    other GPU types set the count by machine type)
                                    (default: $GPU_COUNT).
  --gpu-model MODEL                 Override the GPU Ollama model (role default
                                    ollama_model_gpu, e.g. qwen2.5:14b on an L4).
                                    Only meaningful with --ai-backend ollama-gpu.
  --ollama-storage-size SIZE        Override the Ollama model-cache PVC size (role
                                    default ollama_storage_size 20Gi; e.g. 40Gi for
                                    a ~20GB qwen2.5:32b). Only with --ai-backend ollama-gpu.
  --job-id-prefix PREFIX            Prefix for GCP Batch job names, so Batch jobs are
                                    identifiable per cluster (default: sanitized
                                    INSTANCE_NAME). Must match ^[a-z]([a-z0-9-]*[a-z0-9])?$.
  --hostname FQDN                   Serve Galaxy over HTTPS at this hostname. Issues a
                                    Let's Encrypt cert via cert-manager (HTTP-01), so
                                    the FQDN's DNS must resolve to the VM's public IP
                                    and ports 80/443 must be open. Requires --acme-email.
                                    Pair with --address for a stable IP.
  --address NAME|IP                 Attach a reserved GCP static external IP (address
                                    name or IP) instead of an ephemeral one. Must be in
                                    the same region as --zone.
  --acme-email EMAIL                Let's Encrypt account email (expiry/renewal
                                    notices). Required with --hostname.
  --expose-litellm                  Publish LiteLLM's OpenAI-compatible API at
                                    https://<hostname>/llm/v1 (for Orbit and other
                                    OpenAI-compatible clients). Requires --hostname;
                                    the endpoint is protected by the LiteLLM key.
  --interactive-tools               Enable Galaxy Interactive Tools on the local
                                    cluster: route interactive_tool.* to Kubernetes
                                    and set up the per-instance Cloud DNS zone +
                                    wildcard TLS. Requires --hostname.
  -h, --help, help                  Show this help message

Examples:
  # Launch VM with new or existing disk
  $0 -k "ssh-rsa AAAAB3..." my-galaxy-vm

  # Launch VM with specific machine image
  $0 -k "ssh-rsa AAAAB3..." -i galaxy-k8s-boot-v2026-02-25 my-galaxy-vm

  # Launch VM with specific disk names
  $0 -k "ssh-rsa AAAAB3..." -d galaxy-shared-disk --postgres-disk galaxy-postgres-disk my-galaxy-vm

  # Create VM without persistent storage (testing only)
  $0 -k "ssh-rsa AAAAB3..." --ephemeral-only my-galaxy-vm

  # Launch VM with specific Galaxy chart versions
  $0 -k "ssh-rsa AAAAB3..." --galaxy-chart-version "6.0.0" --galaxy-deps-version "1.1.0" my-galaxy-vm

  # Launch VM with custom Galaxy chart location
  $0 -k "ssh-rsa AAAAB3..." --galaxy-chart "ksuderman/galaxy" --galaxy-chart-version "6.7.0" my-galaxy-vm

  # Launch VM with custom Galaxy and Galaxy-deps chart locations
  $0 -k "ssh-rsa AAAAB3..." --galaxy-chart "ksuderman/galaxy" --galaxy-deps-chart "ksuderman/galaxy-deps" my-galaxy-vm

  # Launch VM with multiple Helm values files (order matters - later files override earlier ones)
  $0 -k "ssh-rsa AAAAB3..." -f values/values.yml -f mixins/v26.1.yml my-galaxy-vm
  $0 -k "ssh-rsa AAAAB3..." --values values/values.yml --values mixins/multiuser.yml --values mixins/admins.yml my-galaxy-vm
  # Launch VM with custom git repository and branch
  $0 -k "ssh-rsa AAAAB3..." -g "https://github.com/username/galaxy-k8s-boot.git" -b "feature-branch" my-galaxy-vm

  # Auto-detect and restore Galaxy from existing data
  $0 -k "ssh-rsa AAAAB3..." --restore-galaxy my-galaxy-vm

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--git-branch)
            GIT_BRANCH="$2"
            shift 2
            ;;
        -d|--disk-name)
            DISK_NAME="$2"
            shift 2
            ;;
        --dry-run)
        	DRY_RUN="yes"
        	shift
        	;;
        --spot)
            SPOT=true
            shift
            ;;
        -e|--ephemeral-only)
            EPHEMERAL_ONLY=true
            shift
            ;;
        -f|--values)
            GALAXY_VALUES_FILES+=("$2")
            shift 2
            ;;
        -i|--machine-image)
            MACHINE_IMAGE="$2"
            shift 2
            ;;
        --postgres-disk)
            POSTGRES_DISK_NAME="$2"
            shift 2
            ;;
        --postgres-disk-size)
            POSTGRES_DISK_SIZE="$2"
            shift 2
            ;;
        -k|--ssh-key)
            SSH_KEY="$2"
            shift 2
            ;;
        -m|--machine-type)
            MACHINE_TYPE="$2"
            MACHINE_TYPE_SET=true
            shift 2
            ;;
        -p|--project)
            PROJECT="$2"
            shift 2
            ;;
        -r|--git-repo)
            GIT_REPO="$2"
            shift 2
            ;;
        -s|--disk-size)
            DISK_SIZE="$2"
            shift 2
            ;;
        -u|--user)
            VM_USER="$2"
            shift 2
            ;;
        -z|--zone)
            ZONE="$2"
            shift 2
            ;;
        --galaxy-chart)
            GALAXY_CHART="$2"
            shift 2
            ;;
        --galaxy-chart-version)
            GALAXY_CHART_VERSION="$2"
            shift 2
            ;;
        --galaxy-deps-chart)
            GALAXY_DEPS_CHART="$2"
            shift 2
            ;;
        --galaxy-deps-version)
            GALAXY_DEPS_VERSION="$2"
            shift 2
            ;;
        --restore-galaxy)
            RESTORE_GALAXY=true
            shift
            ;;
        --profile)
            PROFILE="$2"
            PROFILE_SET=true
            shift 2
            ;;
        --nfs-reserve)
            NFS_RESERVE="$2"
            shift 2
            ;;
        --ai-backend)
            AI_BACKEND="$2"
            shift 2
            ;;
        --ai-master-key)
            AI_MASTER_KEY="$2"
            shift 2
            ;;
        --gpu-type)
            GPU_TYPE="$2"
            shift 2
            ;;
        --gpu-cpus)
            GPU_CPUS="$2"
            shift 2
            ;;
        --gpu-count)
            GPU_COUNT="$2"
            shift 2
            ;;
        --gpu-model)
            GPU_MODEL="$2"
            shift 2
            ;;
        --ollama-storage-size)
            GPU_STORAGE="$2"
            shift 2
            ;;
        --job-id-prefix)
            JOB_ID_PREFIX="$2"
            shift 2
            ;;
        --hostname)
            GALAXY_HOSTNAME="$2"
            shift 2
            ;;
        --address)
            ADDRESS="$2"
            shift 2
            ;;
        --acme-email)
            ACME_EMAIL="$2"
            shift 2
            ;;
        --expose-litellm)
            EXPOSE_LITELLM=true
            shift
            ;;
        --interactive-tools)
            ENABLE_INTERACTIVE_TOOLS=true
            shift
            ;;
        -h|--help|help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [ -z "$INSTANCE_NAME" ]; then
                INSTANCE_NAME="$1"
            else
                echo "Error: Multiple instance names provided"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Validate required arguments
echo "Validatin required arguments"
if [ -z "$INSTANCE_NAME" ]; then
    echo "Error: Instance name is required"
    usage
    exit 1
fi

# Default the GCP Batch job-name prefix to the sanitized instance name when it was not
# set explicitly (--job-id-prefix). Batch job names must match ^[a-z]([a-z0-9-]*[a-z0-9])?$:
# lowercase, collapse invalid chars to '-', strip leading non-letters and trailing '-'.
if [ -z "$JOB_ID_PREFIX" ]; then
    JOB_ID_PREFIX=$(echo "$INSTANCE_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-' | sed 's/^[^a-z]*//; s/-*$//')
fi
echo "GCP Batch job-id prefix: $JOB_ID_PREFIX"

if [ "$EPHEMERAL_ONLY" = false ] && [ -z "$SSH_KEY" ]; then
    if [[ -e ~/.ssh/id_rsa.pub ]] ; then
        SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
    else
      echo "Error: SSH key is required"
      usage
      exit 1
    fi
fi

# Validate the AI backend selection and prepare the LiteLLM master key
case "$AI_BACKEND" in
    none|ollama-cpu|ollama-gpu|vllm-gpu|external|vertex) ;;
    *)
        echo "Error: invalid --ai-backend '$AI_BACKEND' (expected: none, ollama-cpu, ollama-gpu, vllm-gpu, external, vertex)"
        usage
        exit 1
        ;;
esac

# GPU-backed inference backends (ollama-gpu, vllm-gpu) share the same VM-side
# provisioning: pick a GPU machine type from --gpu-type/--gpu-cpus and force
# maintenance-policy=TERMINATE. This flag is the single switch for all of it.
GPU_BACKEND=false
case "$AI_BACKEND" in
    ollama-gpu|vllm-gpu) GPU_BACKEND=true ;;
esac

if [ "$AI_BACKEND" != "none" ] && [ -z "$AI_MASTER_KEY" ]; then
    AI_MASTER_KEY="sk-galaxy-$(openssl rand -hex 16)"
fi

# Resolve the GPU machine type and attach mechanism for the self-hosted GPU backend.
# The user asks for a GPU model (--gpu-type) and a desired vCPU count (--gpu-cpus);
# we pick the smallest machine in that GPU's family that meets the vCPU request (an
# explicit --machine-type always wins). GPU_ACCELERATOR holds the --accelerator spec
# for the flexible-attach families (T4/N1) and is empty for bundled families
# (L4/A100/H100), which ship the GPU with the machine type.
GPU_ACCELERATOR=""
if [ "$GPU_BACKEND" = true ]; then
    # Round a desired vCPU count up to the smallest offered size in a family.
    _gpu_round_up() {
        local want="$1"; shift
        local size
        for size in "$@"; do
            if [ "$want" -le "$size" ]; then echo "$size"; return; fi
        done
        echo "$size"   # nothing large enough: fall back to the largest offered size
    }
    case "$GPU_TYPE" in
        t4)
            # N1 flexible attach: a T4 rides on any n1-standard size.
            [ "$MACHINE_TYPE_SET" = true ] || \
                MACHINE_TYPE="n1-standard-$(_gpu_round_up "$GPU_CPUS" 1 2 4 8 16 32 64 96)"
            GPU_ACCELERATOR="type=nvidia-tesla-t4,count=${GPU_COUNT}"
            ;;
        l4)
            # G2 bundled: g2-standard-{4,8,12,16,24,32,48,96}.
            [ "$MACHINE_TYPE_SET" = true ] || \
                MACHINE_TYPE="g2-standard-$(_gpu_round_up "$GPU_CPUS" 4 8 12 16 24 32 48 96)"
            ;;
        a100)
            # A2 bundled, sized by GPU count: 1g=12, 2g=24, 4g=48, 8g=96 vCPU.
            if [ "$MACHINE_TYPE_SET" != true ]; then
                if   [ "$GPU_CPUS" -le 12 ]; then MACHINE_TYPE="a2-highgpu-1g"
                elif [ "$GPU_CPUS" -le 24 ]; then MACHINE_TYPE="a2-highgpu-2g"
                elif [ "$GPU_CPUS" -le 48 ]; then MACHINE_TYPE="a2-highgpu-4g"
                else                              MACHINE_TYPE="a2-highgpu-8g"
                fi
            fi
            ;;
        h100)
            # A3 bundled, sized by GPU count: 1g=26, 2g=52, 4g=104, 8g=208 vCPU.
            if [ "$MACHINE_TYPE_SET" != true ]; then
                if   [ "$GPU_CPUS" -le 26 ];  then MACHINE_TYPE="a3-highgpu-1g"
                elif [ "$GPU_CPUS" -le 52 ];  then MACHINE_TYPE="a3-highgpu-2g"
                elif [ "$GPU_CPUS" -le 104 ]; then MACHINE_TYPE="a3-highgpu-4g"
                else                               MACHINE_TYPE="a3-highgpu-8g"
                fi
            fi
            ;;
        *)
            echo "Error: invalid --gpu-type '$GPU_TYPE' (expected: t4, l4, a100, h100)"
            usage
            exit 1
            ;;
    esac
fi

# HTTPS requires an ACME account email for the Let's Encrypt certificate.
if [ -n "$GALAXY_HOSTNAME" ] && [ -z "$ACME_EMAIL" ]; then
    echo "Error: --hostname '$GALAXY_HOSTNAME' requires --acme-email (Let's Encrypt account email)"
    usage
    exit 1
fi

# Interactive Tools derive their subdomain from the hostname, so they require one.
if [ "$ENABLE_INTERACTIVE_TOOLS" = true ] && [ -z "$GALAXY_HOSTNAME" ]; then
    echo "Error: --interactive-tools requires --hostname (the IT subdomain derives from it)"
    usage
    exit 1
fi

# Exposing LiteLLM reuses the HTTPS host + cert, so it requires a hostname.
if [ "$EXPOSE_LITELLM" = true ] && [ -z "$GALAXY_HOSTNAME" ]; then
    echo "Error: --expose-litellm requires --hostname (it is served over HTTPS on that host)"
    usage
    exit 1
fi

# Set default disk names if not provided
if [ -z "$DISK_NAME" ]; then
    DISK_NAME="galaxy-data-$INSTANCE_NAME"
fi

if [ -z "$POSTGRES_DISK_NAME" ]; then
    POSTGRES_DISK_NAME="galaxy-postgres-$INSTANCE_NAME"
fi

# Set default values file if none provided
if [ ${#GALAXY_VALUES_FILES[@]} -eq 0 ]; then
    GALAXY_VALUES_FILES=("values/values.yml")
fi

echo "Converting values file array"
# Convert values files array to semicolon-separated string for metadata
# (semicolon is used instead of comma to avoid conflicts with gcloud metadata format)
GALAXY_VALUES_FILES_LIST=$(IFS=';'; echo "${GALAXY_VALUES_FILES[*]}")

echo "=== Galaxy Kubernetes Boot VM Launch ==="
echo "Instance Name: $INSTANCE_NAME"
echo "Project: $PROJECT"
echo "Zone: $ZONE"
echo "Machine Type: $MACHINE_TYPE"
echo "Machine Image: $MACHINE_IMAGE"
echo "Galaxy Chart Version: $GALAXY_CHART_VERSION"
echo "Galaxy Deps Version: $GALAXY_DEPS_VERSION"
echo "Galaxy Values Files: ${GALAXY_VALUES_FILES[@]}"
echo "Git Repository: $GIT_REPO"
echo "Git Branch: $GIT_BRANCH"

if [ "$RESTORE_GALAXY" = true ]; then
    echo "Galaxy Restore Mode: Auto-detect and restore"
fi

if [ "$AI_BACKEND" != "none" ]; then
    echo "ChatGXY Inference Backend: $AI_BACKEND"
    echo "LiteLLM Master Key: $AI_MASTER_KEY"
    if [ "$GPU_BACKEND" = true ]; then
        echo "GPU: $GPU_TYPE (machine type $MACHINE_TYPE)"
        [ -n "$GPU_MODEL" ] && echo "GPU Ollama Model: $GPU_MODEL"
    fi
    echo "ℹ ChatGXY requires a Galaxy image that includes it (e.g. add '-f mixins/dev.yml')."
fi

if [ -n "$ADDRESS" ]; then
    echo "Static IP: $ADDRESS"
fi
if [ -n "$GALAXY_HOSTNAME" ]; then
    echo "HTTPS Hostname: $GALAXY_HOSTNAME (Let's Encrypt, ACME email $ACME_EMAIL)"
    echo "ℹ Ensure DNS for $GALAXY_HOSTNAME resolves to the VM's public IP and 80/443 are open."
    if [ "$EXPOSE_LITELLM" = true ]; then
        echo "LiteLLM exposed at: https://$GALAXY_HOSTNAME/llm/v1 (OpenAI-compatible; bearer = LiteLLM key)"
    fi
fi

if [ "$EPHEMERAL_ONLY" = false ]; then
    echo "NFS Disk Name: $DISK_NAME"
    echo "NFS Disk Size: $DISK_SIZE"
    echo "PostgreSQL Disk Name: $POSTGRES_DISK_NAME"
    echo "PostgreSQL Disk Size: $POSTGRES_DISK_SIZE"
else
    echo "Mode: Ephemeral Only (no persistent disks)"
fi

echo ""

# Handle disk management
DISK_FLAG=""
POSTGRES_DISK_FLAG=""

if [ "$EPHEMERAL_ONLY" = false ]; then
    # Handle NFS disk
    if gcloud compute disks describe "$DISK_NAME" --project="$PROJECT" --zone="$ZONE" &>/dev/null; then
        echo "✓ NFS disk '$DISK_NAME' already exists, will attach existing disk."
        DISK_FLAG="--disk=name=$DISK_NAME,device-name=galaxy-data,mode=rw"

        # Get existing disk size
        EXISTING_DISK_SIZE=$(gcloud compute disks describe "$DISK_NAME" --project="$PROJECT" --zone="$ZONE" --format='get(sizeGb)')
        DISK_SIZE_GB="$EXISTING_DISK_SIZE"
    else
        echo "ℹ NFS disk '$DISK_NAME' does not exist, will create new disk ($DISK_SIZE)."
        DISK_FLAG="--create-disk=name=$DISK_NAME,size=$DISK_SIZE,type=$DISK_TYPE,device-name=galaxy-data,auto-delete=no"

        # Extract numeric value from DISK_SIZE (remove 'GB' suffix)
        DISK_SIZE_GB="${DISK_SIZE%GB}"
    fi

    # Calculate disk persistence size in Gi (K8s will not accept size in GB)
    # Convert GB to GiB: GiB = GB * (1000^3 / 1024^3) ≈ GB * 0.931
    # Using integer arithmetic: GiB = (GB * 931) / 1000
    PV_SIZE=$(( (DISK_SIZE_GB * 931) / 1000 ))
    echo "ℹ NFS storage will be configured for ${PV_SIZE}Gi (converted from ${DISK_SIZE_GB}GB disk)"

    # Galaxy claims PV_SIZE minus reserved headroom (so other PVCs on the same
    # disk have room). Guard against tiny disks: never drop below a sane floor.
    GALAXY_PV_SIZE=$(( PV_SIZE - NFS_RESERVE ))
    if [ "$GALAXY_PV_SIZE" -lt 10 ]; then
        GALAXY_PV_SIZE="$PV_SIZE"
        echo "⚠ Disk too small for ${NFS_RESERVE}Gi reserve; Galaxy will use full ${PV_SIZE}Gi."
    else
        echo "ℹ Galaxy PVC will request ${GALAXY_PV_SIZE}Gi (reserved ${NFS_RESERVE}Gi headroom for Ollama/RabbitMQ)."
    fi

    # Handle PostgreSQL disk
    if gcloud compute disks describe "$POSTGRES_DISK_NAME" --project="$PROJECT" --zone="$ZONE" &>/dev/null; then
        echo "✓ PostgreSQL disk '$POSTGRES_DISK_NAME' already exists, will attach existing disk."
        POSTGRES_DISK_FLAG="--disk=name=$POSTGRES_DISK_NAME,device-name=galaxy-postgres-data,mode=rw"
    else
        echo "ℹ PostgreSQL disk '$POSTGRES_DISK_NAME' does not exist, will create new disk ($POSTGRES_DISK_SIZE)."
        POSTGRES_DISK_FLAG="--create-disk=name=$POSTGRES_DISK_NAME,size=$POSTGRES_DISK_SIZE,type=$DISK_TYPE,device-name=galaxy-postgres-data,auto-delete=no"
    fi
else
    echo "ℹ Using ephemeral storage only (no persistent disks)."
fi

# Generate custom user_data.sh with values baked in
if [[ $DRY_RUN = "yes" ]] ; then
	TEMP_USER_DATA="./cloud-config.txt"
else
	TEMP_USER_DATA=$(mktemp /tmp/user_data.XXXXXX)
	trap "rm -f $TEMP_USER_DATA" EXIT
fi

# Add the configuration values directly into the script
if [ "$EPHEMERAL_ONLY" = false ]; then
    PV_SIZE_VALUE="${PV_SIZE}Gi"
    GALAXY_PV_SIZE_VALUE="${GALAXY_PV_SIZE}Gi"
else
    PV_SIZE_VALUE="20Gi"
    GALAXY_PV_SIZE_VALUE="20Gi"
fi

# Convert values files list to JSON array
GALAXY_VALUES_FILES_JSON=$(echo "$GALAXY_VALUES_FILES_LIST" | sed -e 's/;/","/g' -e 's/^/["/' -e 's/$/"]/')

# Pass the --profile selection as a plain scalar string (galaxy_import_profile_file).
# Raw JSON cannot be spliced into the ansible-pull --extra-vars reliably: it is
# built inside a `sudo bash -c '...'` block that strips quotes and word-splits,
# so a list/quoted value gets mangled. A plain string survives cleanly (like
# ai_backend); the playbook turns it into the galaxy_import_profile list.
#   not given -> "__use_role_default__" (playbook keeps the role default)
#   --profile '' -> "" (playbook disables post-install imports)
#   --profile PATH -> "PATH"
if [ "$PROFILE_SET" = true ]; then
    GALAXY_PROFILE_FILE="$PROFILE"
else
    GALAXY_PROFILE_FILE="__use_role_default__"
fi

cat > "$TEMP_USER_DATA" << 'EOF'
#cloud-config
runcmd:
  - |
    # Setup persistent disk if available
    DISK_DEVICE="/dev/disk/by-id/google-galaxy-data"
    if [ -b "$DISK_DEVICE" ]; then
      echo "[`date`] - Found persistent disk at $DISK_DEVICE"

      # Check if disk is already formatted
      if ! blkid "$DISK_DEVICE" > /dev/null 2>&1; then
        echo "[`date`] - Formatting disk $DISK_DEVICE with ext4"
        mkfs -t ext4 "$DISK_DEVICE"
      else
        echo "[`date`] - Disk $DISK_DEVICE is already formatted"
      fi

      # Create mount point and mount
      mkdir -p /mnt/block_storage
      mount "$DISK_DEVICE" /mnt/block_storage

      # Add to fstab for persistent mounting across reboots
      DISK_UUID=$(blkid -s UUID -o value "$DISK_DEVICE")
      if ! grep -q "$DISK_UUID" /etc/fstab; then
        echo "UUID=$DISK_UUID /mnt/block_storage ext4 defaults,nofail 0 2" >> /etc/fstab
      fi

      # Set proper ownership (VM_USER injected below)
      echo "[`date`] - Persistent disk mounted at /mnt/block_storage"
    else
      echo "[`date`] - No persistent disk found. Galaxy will use ephemeral storage."
    fi

    # Setup PostgreSQL disk if available
    POSTGRES_DISK_DEVICE="/dev/disk/by-id/google-galaxy-postgres-data"
    if [ -b "$POSTGRES_DISK_DEVICE" ]; then
      echo "[`date`] - Found PostgreSQL disk at $POSTGRES_DISK_DEVICE"

      # Check if disk is already formatted
      if ! blkid "$POSTGRES_DISK_DEVICE" > /dev/null 2>&1; then
        echo "[`date`] - Formatting PostgreSQL disk $POSTGRES_DISK_DEVICE with ext4"
        mkfs -t ext4 "$POSTGRES_DISK_DEVICE"
      else
        echo "[`date`] - PostgreSQL disk $POSTGRES_DISK_DEVICE is already formatted"
      fi

      # Create mount point and mount
      mkdir -p /mnt/postgres_storage
      mount "$POSTGRES_DISK_DEVICE" /mnt/postgres_storage

      # Add to fstab for persistent mounting across reboots
      POSTGRES_DISK_UUID=$(blkid -s UUID -o value "$POSTGRES_DISK_DEVICE")
      if ! grep -q "$POSTGRES_DISK_UUID" /etc/fstab; then
        echo "UUID=$POSTGRES_DISK_UUID /mnt/postgres_storage ext4 defaults,nofail 0 2" >> /etc/fstab
      fi

      # Set proper ownership (VM_USER injected below)
      echo "[`date`] - PostgreSQL disk mounted at /mnt/postgres_storage"
    else
      echo "[`date`] - No PostgreSQL disk found. PostgreSQL will use ephemeral storage."
    fi
  - |
    # Set disk ownership
    VM_USER="PLACEHOLDER_VM_USER"
    if [ -d /mnt/block_storage ]; then
      chown $VM_USER:$VM_USER /mnt/block_storage
    fi
    if [ -d /mnt/postgres_storage ]; then
      chown $VM_USER:$VM_USER /mnt/postgres_storage
    fi

    # Run ansible-pull as VM_USER
    sudo -u $VM_USER bash -c '
    export HOME=/home/PLACEHOLDER_VM_USER
    HOST_IP=$(curl -s ifconfig.me)

EOF

cat >> "$TEMP_USER_DATA" << EOF
    # Configuration from launch_vm.sh
    PV_SIZE="${PV_SIZE_VALUE}"
    GALAXY_PERSISTENCE_SIZE="${GALAXY_PV_SIZE_VALUE}"
    GIT_REPO="${GIT_REPO}"
    GIT_BRANCH="${GIT_BRANCH}"
    GALAXY_CHART="${GALAXY_CHART}"
    GALAXY_CHART_VERSION="${GALAXY_CHART_VERSION}"
    GALAXY_DEPS_VERSION="${GALAXY_DEPS_VERSION}"
    GALAXY_VALUES_FILES_JSON='${GALAXY_VALUES_FILES_JSON}'
    RESTORE_GALAXY="${RESTORE_GALAXY}"
    AI_BACKEND="${AI_BACKEND}"
    AI_MASTER_KEY="${AI_MASTER_KEY}"
    GALAXY_PROFILE_FILE="${GALAXY_PROFILE_FILE}"
    OLLAMA_MODEL_GPU="${GPU_MODEL}"
    OLLAMA_STORAGE_SIZE="${GPU_STORAGE}"
    GCP_BATCH_JOB_ID_PREFIX="${JOB_ID_PREFIX}"
    GALAXY_HOSTNAME="${GALAXY_HOSTNAME}"
    ACME_EMAIL="${ACME_EMAIL}"
    EXPOSE_LITELLM="${EXPOSE_LITELLM}"
EOF

cat >> "$TEMP_USER_DATA" << 'EOF'

    # Include the HTTPS hostname in the RKE2 API cert SANs when one is set.
    if [ -n "${GALAXY_HOSTNAME}" ]; then
      RKE2_SANS="[\"${HOST_IP}\",\"${GALAXY_HOSTNAME}\"]"
    else
      RKE2_SANS="[\"${HOST_IP}\"]"
    fi

    mkdir -p /tmp/ansible-inventory
    cat > /tmp/ansible-inventory/localhost << INVEOF
    [vms]
    127.0.0.1 ansible_connection=local ansible_python_interpreter="/usr/bin/python3"

    [all:vars]
    ansible_user="PLACEHOLDER_VM_USER"
    rke2_token="defaultSecret12345"
    rke2_additional_sans=${RKE2_SANS}
    rke2_debug=true
    nfs_size="${PV_SIZE}"
    galaxy_persistence_size="${GALAXY_PERSISTENCE_SIZE}"
    galaxy_db_password="gxy-db-password"
    galaxy_user="default-user@galaxyproject.org"
    galaxy_bootstrap_api_key="galaxypassword"
    restore_galaxy=$RESTORE_GALAXY
    ai_backend="${AI_BACKEND}"
    litellm_master_key="${AI_MASTER_KEY}"
    galaxy_import_profile_file="${GALAXY_PROFILE_FILE}"
    galaxy_hostname="${GALAXY_HOSTNAME}"
    acme_email="${ACME_EMAIL}"
    expose_litellm=${EXPOSE_LITELLM}
    INVEOF

    # Override the GPU Ollama model only when --gpu-model was given, so an empty
    # value leaves the role default (ollama_model_gpu) untouched. Appended under the
    # [all:vars] section (the last section in the inventory).
    if [ -n "${OLLAMA_MODEL_GPU}" ]; then
      echo "    ollama_model_gpu=\"${OLLAMA_MODEL_GPU}\"" >> /tmp/ansible-inventory/localhost
      echo "[`date`] - GPU Ollama model override: ${OLLAMA_MODEL_GPU}"
    fi

    if [ -n "${OLLAMA_STORAGE_SIZE}" ]; then
      echo "    ollama_storage_size=\"${OLLAMA_STORAGE_SIZE}\"" >> /tmp/ansible-inventory/localhost
      echo "[`date`] - Ollama model-cache size override: ${OLLAMA_STORAGE_SIZE}"
    fi

    # Per-cluster GCP Batch job-name prefix (always set: explicit or instance-name derived).
    if [ -n "${GCP_BATCH_JOB_ID_PREFIX}" ]; then
      echo "    gcp_batch_job_id_prefix=\"${GCP_BATCH_JOB_ID_PREFIX}\"" >> /tmp/ansible-inventory/localhost
      echo "[`date`] - GCP Batch job-id prefix: ${GCP_BATCH_JOB_ID_PREFIX}"
    fi

    echo "[`date`] - NFS storage size for Galaxy: ${PV_SIZE}"
    echo "[`date`] - Git Repository: ${GIT_REPO}"
    echo "[`date`] - Git Branch: ${GIT_BRANCH}"
    echo "[`date`] - Galaxy Chart: ${GALAXY_CHART}"
    echo "[`date`] - Galaxy Chart Version: ${GALAXY_CHART_VERSION}"
    echo "[`date`] - Galaxy Deps Version: ${GALAXY_DEPS_VERSION}"
    echo "[`date`] - Galaxy Values Files: ${GALAXY_VALUES_FILES_JSON}"
    echo "[`date`] - Inventory file created at /tmp/ansible-inventory/localhost; running ansible-pull..."

    ANSIBLE_CALLBACKS_ENABLED=profile_tasks ANSIBLE_HOST_PATTERN_MISMATCH=ignore ansible-pull -U ${GIT_REPO} -C ${GIT_BRANCH} -d /home/PLACEHOLDER_VM_USER/ansible -i /tmp/ansible-inventory/localhost --accept-host-key --limit 127.0.0.1 --extra-vars "{\"enable_gcp_batch\": true, \"enable_interactive_tools\": ${ENABLE_INTERACTIVE_TOOLS}, \"galaxy_chart\": \"${GALAXY_CHART}\", \"galaxy_chart_version\": \"${GALAXY_CHART_VERSION}\", \"galaxy_deps_chart\": \"${GALAXY_DEPS_CHART}\", \"galaxy_deps_version\": \"${GALAXY_DEPS_VERSION}\", \"galaxy_values_files\": ${GALAXY_VALUES_FILES_JSON}}" playbook.yml

    echo "[`date`] - User data script completed."
    '

EOF

# Replace placeholders in the generated user-data
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "s|PLACEHOLDER_VM_USER|${VM_USER}|g" "$TEMP_USER_DATA"
    sed -i '' "s|\${GALAXY_CHART}|${GALAXY_CHART}|g" "$TEMP_USER_DATA"
    sed -i '' "s|\${GALAXY_CHART_VERSION}|${GALAXY_CHART_VERSION}|g" "$TEMP_USER_DATA"
    sed -i '' "s|\${GALAXY_DEPS_CHART}|${GALAXY_DEPS_CHART}|g" "$TEMP_USER_DATA"
    sed -i '' "s|\${GALAXY_DEPS_VERSION}|${GALAXY_DEPS_VERSION}|g" "$TEMP_USER_DATA"
else
    sed -i "s|PLACEHOLDER_VM_USER|${VM_USER}|g" "$TEMP_USER_DATA"
    sed -i "s|\${GALAXY_CHART}|${GALAXY_CHART}|g" "$TEMP_USER_DATA"
    sed -i "s|\${GALAXY_CHART_VERSION}|${GALAXY_CHART_VERSION}|g" "$TEMP_USER_DATA"
    sed -i "s|\${GALAXY_DEPS_CHART}|${GALAXY_DEPS_CHART}|g" "$TEMP_USER_DATA"
    sed -i "s|\${GALAXY_DEPS_VERSION}|${GALAXY_DEPS_VERSION}|g" "$TEMP_USER_DATA"
fi

echo "ℹ Generated custom user_data.sh at $TEMP_USER_DATA"

if [[ $DRY_RUN = "yes" ]] ; then
	echo "Dry run complete."
	exit
fi

# Launch the VM
echo "Launching VM '$INSTANCE_NAME'..."

# Build the gcloud command
GCLOUD_CMD=(
    gcloud compute instances create "$INSTANCE_NAME"
    --project="$PROJECT"
    --zone="$ZONE"
    --machine-type="$MACHINE_TYPE"
    --image="$MACHINE_IMAGE"
    --image-project="$PROJECT"
    --boot-disk-size="$BOOT_DISK_SIZE"
    --boot-disk-type="$DISK_TYPE"
    --tags=k8s,http-server,https-server
    --scopes=cloud-platform
    --metadata-from-file=user-data="$TEMP_USER_DATA"
    --metadata=ssh-keys="$VM_USER:$SSH_KEY"
)

# Add disk flags if not ephemeral only
if [ "$EPHEMERAL_ONLY" = false ]; then
    GCLOUD_CMD+=($DISK_FLAG)
    GCLOUD_CMD+=($POSTGRES_DISK_FLAG)
fi

# Attach a reserved static external IP so the VM's public IP matches the hostname's
# DNS record (required for HTTPS). Accepts an address name or a literal IP; a named
# regional address must be in the same region as --zone.
if [ -n "$ADDRESS" ]; then
    GCLOUD_CMD+=(--address="$ADDRESS")
fi

# Attach the GPU for the self-hosted GPU inference backend. GPUs cannot live-migrate,
# so the host maintenance policy must be TERMINATE in every case. The GPU machine type
# and attach mechanism were resolved earlier from --gpu-type/--gpu-cpus: GPU_ACCELERATOR
# is set for flexible-attach families (T4/N1) and empty for bundled families (L4/A100/
# H100), which ship the GPU with the machine type and reject --accelerator.
if [ "$GPU_BACKEND" = true ]; then
    GCLOUD_CMD+=(--maintenance-policy=TERMINATE)
    if [ -n "$GPU_ACCELERATOR" ]; then
        echo "ℹ GPU backend: ${GPU_TYPE} on '$MACHINE_TYPE' via --accelerator=${GPU_ACCELERATOR} (maintenance-policy=TERMINATE)"
        GCLOUD_CMD+=(--accelerator="$GPU_ACCELERATOR")
    else
        echo "ℹ GPU backend: ${GPU_TYPE} bundled with machine type '$MACHINE_TYPE' (maintenance-policy=TERMINATE)"
    fi
fi

# Spot (preemptible) provisioning: ~60-91% cheaper, but GCP can reclaim the VM at any
# time. Spot requires maintenance-policy=TERMINATE (already added above for GPU
# backends, so only add it here when it wasn't). --instance-termination-action=STOP
# keeps the disks on preemption so the instance can be restarted (cloud-init runs once,
# so a restart resumes the already-installed cluster rather than redeploying).
if [ "$SPOT" = true ]; then
    GCLOUD_CMD+=(--provisioning-model=SPOT --instance-termination-action=STOP)
    if [ "$GPU_BACKEND" != true ]; then
        GCLOUD_CMD+=(--maintenance-policy=TERMINATE)
    fi
    echo "ℹ Spot VM: reclaimable by GCP at any time; ~60-91% cheaper than on-demand."
fi

# Execute the command
"${GCLOUD_CMD[@]}"

echo ""
echo "✓ Instance '$INSTANCE_NAME' created successfully."
echo ""

# Get the instance IP address
echo "Getting instance IP address..."
INSTANCE_IP=$(gcloud compute instances describe "$INSTANCE_NAME" --project="$PROJECT" --zone="$ZONE" --format='get(networkInterfaces[0].accessConfigs[0].natIP)')

if [ -n "$INSTANCE_IP" ]; then
    echo "Instance IP: $INSTANCE_IP"

    # Copy IP to clipboard on macOS
    if command -v pbcopy >/dev/null 2>&1; then
        echo "$INSTANCE_IP" | pbcopy
        echo "✓ IP address copied to clipboard"
    fi

    echo ""
    echo "The VM is now bootstrapping automatically. You can:"
    echo "1. Check cloud-init progress: gcloud compute ssh $INSTANCE_NAME --project=$PROJECT --zone=$ZONE --command='sudo tail -f /var/log/cloud-init-output.log'"
    echo "2. Monitor the deployment: gcloud compute ssh $INSTANCE_NAME --project=$PROJECT --zone=$ZONE --command='sudo journalctl -f -u cloud-final'"
    echo ""
    echo "Galaxy will be available at: http://$INSTANCE_IP/ once deployment completes."
else
    echo "Warning: Could not retrieve instance IP address"
    echo ""
    echo "The VM is now bootstrapping automatically. You can:"
    echo "1. Check cloud-init progress: gcloud compute ssh $INSTANCE_NAME --project=$PROJECT --zone=$ZONE --command='sudo tail -f /var/log/cloud-init-output.log'"
    echo "2. Monitor the deployment: gcloud compute ssh $INSTANCE_NAME --project=$PROJECT --zone=$ZONE --command='sudo journalctl -f -u cloud-final'"
    echo ""
    echo "Galaxy will be available at http://INSTANCE_IP/ once deployment completes."
fi
