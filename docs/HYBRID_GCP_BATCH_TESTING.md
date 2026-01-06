# Hybrid GCP Batch Runner Testing Guide

This guide describes how to deploy and test Galaxy with both GCP Batch runners:
- **Direct GCP Batch** - Uses NFS for file access (current implementation)
- **Pulsar GCP Batch** - Uses RabbitMQ + local SSD for file staging (upstream Pulsar)

## Architecture Comparison

### Direct GCP Batch (NFS-based)
```
Galaxy Pod ──► GCP Batch API ──► Batch VM with NFS mount ──► Direct file access
```
- Files accessed via NFS mount from K8s cluster
- Lower job startup overhead
- Better for large input files

### Pulsar GCP Batch (SSD-based)
```
Galaxy Pod ──► RabbitMQ ──► Batch VM with Pulsar sidecar ──► Local SSD staging
```
- Files staged via Pulsar sidecar to local SSD
- Better I/O performance during job execution
- Better for I/O intensive tools

## Prerequisites

### 1. GCP Firewall Rules

Create firewall rules to allow both NFS and RabbitMQ access from GCP Batch VMs:

```bash
# NFS access (if not already created)
gcloud compute firewall-rules create allow-nfs-for-batch \
  --project=anvil-and-terra-development \
  --description="Allow NFS access for GCP Batch VMs" \
  --direction=INGRESS --priority=1000 --network=default \
  --action=ALLOW --rules=tcp:2049,udp:2049,tcp:111,udp:111 \
  --source-ranges=10.128.0.0/9 --target-tags=k8s

# RabbitMQ access (NEW for Pulsar)
gcloud compute firewall-rules create allow-rabbitmq-for-batch \
  --project=anvil-and-terra-development \
  --description="Allow RabbitMQ access for GCP Batch VMs" \
  --direction=INGRESS --priority=1000 --network=default \
  --action=ALLOW --rules=tcp:5672 \
  --source-ranges=10.128.0.0/9 --target-tags=k8s
```

### 2. GCP Service Account

Ensure the GCP Batch service account has required permissions:
- `roles/batch.jobsEditor`
- `roles/compute.instanceAdmin.v1`
- `roles/iam.serviceAccountUser`
- `roles/logging.logWriter`

### 3. Service Account Key Secret

The GCP service account key must be available as a Kubernetes secret:

```bash
kubectl create secret generic gcp-batch-key \
  --from-file=key.json=/path/to/service-account-key.json \
  -n galaxy
```

## Deployment Options

### Option 1: Fresh Deployment with Hybrid Configuration

```bash
# Using launch_vm.sh
bin/launch_vm.sh test-hybrid-galaxy \
  --git-branch persistent-data-merged \
  -f values/hybrid-gcp-batch.yml

# Or with test routing configuration
bin/launch_vm.sh test-hybrid-galaxy \
  --git-branch persistent-data-merged \
  -f values/hybrid-gcp-batch.yml \
  -f values/test-gcp-batch-comparison.yml
```

### Option 2: Enable on Existing Cluster

```bash
# Set required variables
export KUBECONFIG=~/.kube/configs/gcp

# Enable both runners via Ansible
ansible-playbook -i inventories/gcp.ini playbook.yml \
  --extra-vars "enable_gcp_batch=true" \
  --extra-vars "enable_pulsar_gcp_batch=true" \
  --extra-vars "pulsar_gcp_project_id=anvil-and-terra-development" \
  --tags galaxy
```

### Option 3: Manual Helm Upgrade

```bash
export KUBECONFIG=~/.kube/configs/gcp

# Apply hybrid configuration
helm upgrade galaxy ksuderman/galaxy -n galaxy \
  --reuse-values \
  -f values/hybrid-gcp-batch.yml \
  -f values/test-gcp-batch-comparison.yml
```

## Configuration Variables

### Direct GCP Batch (existing)
| Variable | Default | Description |
|----------|---------|-------------|
| `enable_gcp_batch` | `false` | Enable direct GCP Batch runner |
| `gcp_batch_service_account_email` | `""` | Service account email |
| `gcp_batch_region` | `us-east4` | GCP region |

### Pulsar GCP Batch (new)
| Variable | Default | Description |
|----------|---------|-------------|
| `enable_pulsar_gcp_batch` | `false` | Enable Pulsar GCP Batch runner |
| `pulsar_gcp_project_id` | `""` | GCP project ID (required) |
| `pulsar_gcp_region` | `us-east4` | GCP region |
| `pulsar_gcp_machine_type` | `n2-standard-4` | VM machine type |
| `pulsar_gcp_walltime_limit` | `86400` | Max job duration (seconds) |
| `pulsar_gcp_retry_count` | `3` | Job retry count |
| `pulsar_gcp_disk_size` | `375` | SSD disk size (GB) |
| `pulsar_gcp_ssd_name` | `pulsar_staging` | SSD volume name |
| `pulsar_container_image` | `galaxy/pulsar-pod-staging:0.15.0.2` | Pulsar sidecar image |

## Test Routing Configuration

The `values/test-gcp-batch-comparison.yml` file routes tools to different runners:

### Group A: Direct GCP Batch (NFS)
- `Cut1`, `Grep1`, `Sort1`, `Paste1`, `join1`, `cat1`
- Text processing tools
- Tests streaming/sequential I/O

### Group B: Pulsar GCP Batch (SSD)
- `FastQC`, `BWA`, `Samtools`, `HISAT2`, `featureCounts`
- Bioinformatics tools
- Tests random I/O intensive workloads

## Running Performance Tests

### 1. Prepare Test Data

Upload test datasets of varying sizes:
- Small: 1 MB text file
- Medium: 100 MB FASTQ file
- Large: 1 GB FASTQ file

### 2. Run Test Jobs

Run the same tool with different runners by temporarily changing the routing:

```bash
# Test Cut1 with Direct GCP Batch (default in test config)
# Submit job via Galaxy UI

# Test Cut1 with Pulsar GCP Batch
# Temporarily modify job_conf.yml or use API with destination override
```

### 3. Collect Metrics

Monitor job performance:

```bash
# Check GCP Batch job status
gcloud batch jobs list --location=us-east4 \
  --project=anvil-and-terra-development \
  --filter="createTime>=2025-01-06T00:00:00Z"

# Check specific job details
gcloud batch jobs describe JOB_NAME \
  --location=us-east4 \
  --project=anvil-and-terra-development

# Check Galaxy job metrics
kubectl exec -n galaxy deploy/galaxy-web -- \
  cat /galaxy/server/database/jobs/JOB_ID/metadata/job_metrics_*.json
```

### 4. Compare Results

Key metrics to compare:
- **Job startup time**: Time from submission to running
- **Data transfer time**: Input staging + output collection
- **Execution time**: Actual tool runtime
- **Total wall time**: End-to-end job duration

## Troubleshooting

### Direct GCP Batch Issues

```bash
# Check NFS connectivity from Batch VM
gcloud batch jobs describe JOB_NAME --location=us-east4 \
  --format="value(status.statusEvents)"

# Check NFS mount in running job
# (via serial console or SSH if enabled)
mount | grep nfs
```

### Pulsar GCP Batch Issues

```bash
# Check RabbitMQ connectivity
kubectl exec -n galaxy galaxy-rabbitmq-server-server-0 -c rabbitmq -- \
  rabbitmqctl list_connections

# Check RabbitMQ queues
kubectl exec -n galaxy galaxy-rabbitmq-server-server-0 -c rabbitmq -- \
  rabbitmqctl list_queues

# Check Pulsar sidecar logs (in Batch job)
gcloud batch jobs describe JOB_NAME --location=us-east4 \
  --format="value(status.taskGroups[0].taskStates)"

# Verify RabbitMQ external IP
kubectl get svc -n galaxy | grep rabbitmq
```

### Common Issues

1. **RabbitMQ connection refused**
   - Check firewall rule `allow-rabbitmq-for-batch` exists
   - Verify RabbitMQ service has external IP: `kubectl get svc -n galaxy -o wide`
   - Test connectivity from Batch VM network

2. **NFS mount timeout**
   - Check firewall rule `allow-nfs-for-batch` exists
   - Verify NFS service has external IP: `kubectl get svc -n nfs-provisioner -o wide`
   - Check NFS export path is correct in job_conf.yml

3. **Pulsar sidecar fails to start**
   - Check Pulsar container image is accessible
   - Verify AMQP URL is correctly configured
   - Check GCP Batch VM has network access

## Files Reference

| File | Purpose |
|------|---------|
| `values/hybrid-gcp-batch.yml` | Base hybrid configuration with both runners |
| `values/test-gcp-batch-comparison.yml` | Test routing for A/B comparison |
| `roles/galaxy_k8s_deployment/defaults/main.yml` | Ansible variables |
| `roles/galaxy_k8s_deployment/tasks/galaxy_application.yml` | Deployment tasks |

## Next Steps

After testing:
1. Analyze performance metrics for each runner
2. Determine optimal routing based on tool characteristics
3. Create production configuration with tool-specific routing
4. Consider cost implications (SSD vs NFS storage costs)
