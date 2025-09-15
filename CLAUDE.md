# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Galaxy Kubernetes Boot is a collection of Ansible playbooks for deploying Kubernetes clusters (K3S or RKE2) and Galaxy/Pulsar instances on GCP, AWS, and OpenStack VM instances. The project uses Ansible automation to set up infrastructure and deploy scientific computing platforms.

## Key Architecture Components

- **Main Playbook (`playbook.yml`)**: Orchestrates the entire deployment process through imported playbooks
- **K3S Cluster Setup (`k3s/`)**: Contains Ansible roles and playbooks for K3S Kubernetes deployment
- **RKE Setup (`rke/`)**: RKE2 cluster deployment (work in progress)
- **Application Deployment**: Supports both Galaxy and Pulsar scientific computing platforms
- **Infrastructure**: Includes NFS storage, Helm package management, and ingress configuration
- **Docker Support**: Containerized deployment option with Ubuntu 24.04 base

## Common Commands

### Environment Setup
```bash
# Set up Python virtual environment and install dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# Alternative: Install Ansible directly on barebones Ubuntu
sudo apt install software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install ansible
```

### Docker Operations
```bash
# Build Docker image
make build

# Push to registry  
make push

# Run container interactively
make run

# Clean up images
make clean

# Remove all Docker images
make clean-all
```

### Automated Deployment
```bash
# Use init script as user data during VM launch
bin/init_script.sh

# Manual localhost deployment (after configuring inventories/localhost)
ansible-playbook -i inventories/localhost playbook.yml \
  --extra-vars "application=galaxy" \
  --extra-vars "galaxy_api_key=changeme"
```

### Galaxy Deployment
```bash
# Deploy Galaxy instance with custom values file
ansible-playbook -i inventories/my-server.ini playbook.yml \
  --extra-vars "application=galaxy" \
  --extra-vars "galaxy_api_key=changeme" \
  --extra-vars "galaxy_admin_users=email@address.com" \
  --extra-vars "chart_values_file=custom.yml"

# Deploy with resource limits
ansible-playbook -i inventories/localhost playbook.yml \
  --extra-vars "job_max_cores=6" \
  --extra-vars "job_max_mem=14" \
  --extra-vars "application=galaxy" \
  --extra-vars "galaxy_api_key=changeme"
```

### Pulsar Deployment
```bash
# Deploy Pulsar node
ansible-playbook -i inventories/my-server.ini playbook.yml \
  --extra-vars "application=pulsar" \
  --extra-vars "pulsar_api_key=changeme"
```

### Inventory Management
```bash
# Generate inventory file for remote host
bin/inventory.sh --name my-server --ip 1.2.3.4 --key ~/.ssh/my-key.pem > inventories/my-server.ini

# Cloud provider specific templates available:
# bin/aws.sh, bin/azure.sh, bin/openstack.sh
```

### User Management
```bash
# Add Galaxy user (registration disabled by default)
bin/add_user.sh <host> <galaxy_api_key> <email> <password> <username>
```

### Kubernetes Management
```bash
# Use kubectl on the server
kubectl get pods -A

# Download kubeconfig for local use
scp -i ~/.ssh/my-key.pem ubuntu@<server-ip>:/home/ubuntu/.kube/config ~/.kube/config
```

## Key Configuration Files

- **`values/accp.yml`**: Default Helm chart values for Galaxy deployment
- **`values/job_conf.yml`**: Job configuration for computational resources  
- **`values/aws_batch.yml`**: AWS Batch-specific configuration
- **`inventories/localhost.template`**: Template for localhost deployment inventory
- **`inventories/{cloud}.ini`**: Cloud provider-specific inventory examples
- **`bin/init_script.sh`**: Automated deployment script for VM user data
- **`requirements.txt`**: Python dependencies (Ansible 11.0.0, PyYAML, etc.)

## Playbook Architecture

The main `playbook.yml` orchestrates deployment through these imported playbooks:

1. **`setup.yml`**: Basic node preparation and system requirements
2. **`k3s/site.yml`**: K3S cluster installation and configuration  
3. **`helm.yml`**: Helm package manager installation
4. **`nfs.yml`**: NFS server setup for shared storage
5. **`ingress.yml`**: Ingress controller configuration
6. **`storage.yml`**: Block storage and persistent volume setup
7. **`galaxy_app.yml`**: Galaxy application deployment (when `application=galaxy`)
8. **`pulsar.yml`**: Pulsar node deployment (when `application=pulsar`)

## VM Requirements and Setup

### Minimum Specifications
- **OS**: Ubuntu 24.04
- **Root filesystem**: 30GB minimum
- **Block storage**: 100GB minimum attached disk
- **Security groups**: Ports 22 (SSH) and 80 (HTTP) open
- **AWS specific**: Enable V1 metadata service

### Block Storage Configuration
```bash
# Format and mount block storage disk
sudo mkfs -t ext4 /dev/nvme1n1
sudo mkdir /mnt/block_storage  
sudo mount /dev/nvme1n1 /mnt/block_storage
```

## Important Variables

- `application`: "galaxy" or "pulsar" - determines which platform to deploy
- `chart_values_file`: Helm values file (default: "accp.yml")
- `galaxy_api_key`: Admin API key for Galaxy
- `galaxy_admin_users`: Admin user email addresses
- `pulsar_api_key`: Admin API key for Pulsar
- `block_storage_disk_path`: Mount point for block storage (default: `/mnt/block_storage`)
- `job_max_cores`: Maximum CPU cores for jobs
- `job_max_mem`: Maximum memory in GB for jobs
- `k3s_version`: K3S version to install (default: 'v1.31.2+k3s1')

## Cloud Provider Support

The project includes deployment scripts and templates for:
- **AWS**: `bin/aws.sh` and `bin/aws.yml`
- **Azure**: `bin/azure.sh` and `bin/azure.yml` 
- **OpenStack**: `bin/openstack.sh` and `bin/openstack.yml`
- **GCP**: `inventories/gcp.ini`

## Testing and Validation

K3S deployment is production-ready. RKE2 support is under development. Validate deployments by:
- Accessing Galaxy/Pulsar web interfaces at `http://<server-ip>/`
- Using `kubectl` commands on the server or with downloaded kubeconfig
- Checking pod status: `kubectl get pods -A`