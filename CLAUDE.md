# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Galaxy Kubernetes Boot is an Ansible-based deployment system for Galaxy on Kubernetes clusters using RKE2. The project supports both image preparation (for faster deployments) and direct deployment on cloud platforms including GCP, AWS, and OpenStack (Jetstream2).

## Architecture

The repository follows a two-phase deployment model:

1. **Image Preparation Phase** (optional but recommended): Uses `image_prep.yml` to create pre-configured VM images with RKE2, Helm, and system dependencies pre-installed for ~50% faster deployments
2. **Runtime Deployment Phase**: Uses `deploy-galaxy.yml` (optimized for prepared images) or `playbook.yml` (standard deployment) to deploy single-node RKE2 clusters with Galaxy

### Key Components

- **Single-node RKE2 clusters**: Master node runs workloads (taints removed automatically)
- **Galaxy application**: Scientific workflow platform deployed via Helm charts
- **GCP Batch integration**: Two job runners for offloading compute to GCP Batch
- **Pulsar support**: Alternative compute backend for Galaxy
- **CVMFS integration**: Pre-configured access to Galaxy reference data
- **NFS storage**: Persistent storage for Galaxy data
- **Ingress configuration**: Nginx-based ingress with optional TLS
- **PostgreSQL persistence**: CNPG operator with skip-initdb plugin for data reuse

## Common Commands

### Environment Setup
```bash
# Create Python virtual environment and install dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Install Ansible Galaxy requirements
ansible-galaxy install -r requirements.yml
```

### Image Preparation (Optional)
```bash
# Prepare a custom VM image (significantly speeds up deployments)
./bin/prepare_image.sh -i inventories/image_prep.ini
```

### Deployment
```bash
# Generate inventory file for target server
bin/inventory.sh --name my-server --ip 1.2.3.4 --key ~/.ssh/my-key.pem > inventories/my-server.ini

# Deploy Galaxy using optimized playbook (for prepared images)
ansible-playbook -i inventories/my-server.ini deploy-galaxy.yml \
  --extra-vars "application=galaxy" \
  --extra-vars "galaxy_api_key=changeme" \
  --extra-vars "galaxy_admin_users=email@address.com"

# Deploy Galaxy using standard playbook (works on any Ubuntu 24.04+)
ansible-playbook -i inventories/my-server.ini playbook.yml \
  --extra-vars "application=galaxy" \
  --extra-vars "galaxy_api_key=changeme" \
  --extra-vars "galaxy_admin_users=email@address.com"

# Deploy Pulsar instead of Galaxy
ansible-playbook -i inventories/my-server.ini playbook.yml \
  --extra-vars "application=pulsar" \
  --extra-vars "pulsar_api_key=changeme"
```

### User Management
```bash
# Add users to Galaxy instance (registration disabled by default)
bin/add_user.sh <host> <galaxy_api_key> <email> <password> <username>
```


## File Structure

### Core Playbooks
- `deploy-galaxy.yml`: Optimized runtime playbook for prepared images
- `playbook.yml`: Standard deployment playbook for any Ubuntu 24.04+
- `image_prep.yml`: Image preparation playbook
- Individual component playbooks: `setup.yml`, `rke2_setup.yml`, `helm.yml`, `nfs.yml`, `storage.yml`, `ingress.yml`, `galaxy_app.yml`, `pulsar.yml`

### Configuration
- `inventories/`: Ansible inventory files with deployment targets and variables
- `values/`: Helm chart values files
  - `values.yml`: Default configuration
  - `gcp-batch.yml`: Direct GCP Batch runner configuration
  - `hybrid-gcp-batch.yml`: Both GCP Batch runners enabled
  - `test-gcp-batch-comparison.yml`: A/B test routing for performance comparison
- `templates/`: Jinja2 templates for configuration generation
- `roles/image_preparation/`: Ansible role for VM image preparation
- `roles/galaxy_k8s_deployment/`: Main Galaxy deployment role

### Utilities
- `bin/`: Shell scripts for common operations
- `docs/`: Documentation including detailed image preparation guide
- `requirements.txt`/`requirements.yml`: Python and Ansible dependencies

## Key Variables

### Required Variables
- `application`: "galaxy" or "pulsar"
- `galaxy_api_key`: Admin API key for Galaxy
- `galaxy_admin_users`: Comma-separated admin email addresses
- `pulsar_api_key`: API key for Pulsar (when deploying Pulsar)

### Common Overrides
- `chart_values_file`: Helm values file (default: "accp.yml")
- `rke2_version`: RKE2 version (default: "v1.33.4+rke2r1")
- `rke2_token`: Cluster token (default: "defaultSecret12345")
- `block_storage_disk_path`: Block storage mount point (default: "/mnt/block_storage")

### GCP Batch Configuration
- `enable_gcp_batch`: Enable direct GCP Batch runner (NFS-based)
- `enable_pulsar_gcp_batch`: Enable Pulsar GCP Batch runner (SSD-based)
- `pulsar_gcp_project_id`: GCP project ID for Pulsar runner
- `gcp_batch_region`: GCP region (default: "us-east4")
- `reuse_existing_data`: Enable persistent data reuse across deployments

## GCP Batch Job Runners

The project supports two GCP Batch job runners:

### Direct GCP Batch Runner (`gcp_batch`)
- Files accessed via NFS mount from K8s cluster
- Lower job startup overhead
- Better for large input files
- Enable with: `enable_gcp_batch=true`

### Pulsar GCP Batch Runner (`pulsar_gcp`)
- Files staged via Pulsar sidecar to local SSD
- Better I/O performance during job execution
- Uses RabbitMQ for communication
- Enable with: `enable_pulsar_gcp_batch=true`

### Deployment with GCP Batch
```bash
# Deploy with direct GCP Batch runner
bin/launch_vm.sh my-galaxy \
  -f values/gcp-batch.yml \
  --git-branch persistent-data-merged

# Deploy with hybrid configuration (both runners)
bin/launch_vm.sh my-galaxy \
  -f values/hybrid-gcp-batch.yml \
  --git-branch persistent-data-merged
```

### Required GCP Firewall Rules
```bash
# NFS access for direct GCP Batch
gcloud compute firewall-rules create allow-nfs-for-batch \
  --project=PROJECT_ID --network=default \
  --action=ALLOW --rules=tcp:2049,udp:2049,tcp:111,udp:111 \
  --source-ranges=10.128.0.0/9 --target-tags=k8s

# RabbitMQ access for Pulsar GCP Batch
gcloud compute firewall-rules create allow-rabbitmq-for-batch \
  --project=PROJECT_ID --network=default \
  --action=ALLOW --rules=tcp:5672 \
  --source-ranges=10.128.0.0/9 --target-tags=k8s
```

## Claude Instructions

- **Use single-line commit messages.** Do not use multi-line commit messages with body text, bullet points, or the generated-by footer.
- Unless otherwise specified the Google VM name will be `ks-psql-test`, the kubeconfig file can be found at ~/.kube/configs/gcp and the Galaxy API key can be obtained using the command `abm config show gcp | jq -r .key`.

## Development Notes

- The project targets Ubuntu 24.04+ exclusively
- Single-node deployments are the primary use case
- Image preparation provides significant deployment speed improvements
- CVMFS is pre-configured for Galaxy reference data access
- All deployments use RKE2 Kubernetes distribution
- Ingress is configured with Nginx (Traefik disabled by default)
- Storage uses NFS for shared data and block storage for databases

## Testing

The project includes inventory examples and can be tested locally using the `inventories/localhost` configuration for development purposes.