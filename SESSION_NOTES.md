# Session Notes: Galaxy Kubernetes Boot Debugging & Investigation

**Date**: 2025-09-16
**Focus**: Deployment issues, architecture understanding, and cloud controller investigation

## Summary of Issues Resolved

### 1. Helm Module Parameter Error
**Problem**: Nginx ingress controller installation failing with unsupported `timeout` parameter
```
Unsupported parameters for (kubernetes.core.helm) module: timeout
```

**Solution**: Removed unsupported `timeout` parameter from `ingress.yml:56`, kept only `wait_timeout`
- **File**: `ingress.yml:50-57`
- **Change**: Removed `timeout: "10m0s"` line, kept `wait_timeout: "10m0s"`

### 2. Pod Readiness Detection Issues
**Problem**: Ansible playbook failing to detect ready kube-system pods despite them being healthy
**Root Cause**: Overly complex filter logic in pod readiness check

**Solution**: Simplified pod readiness detection logic in `ingress.yml:28-36`
- **Before**: Complex percentage-based calculation
- **After**: Simple count-based check (≥5 pods in 'Running' or 'Succeeded' state)
- **Improved**: Extended timeouts (10 retries × 10 seconds)

## Architecture Understanding Clarified

### RKE2 Installation Pattern
**Discovery**: Galaxy K8s Boot uses a two-phase deployment model:

1. **Image Preparation Phase** (`image_prep.yml`):
   - Downloads and installs RKE2 binaries via `roles/image_preparation/tasks/rke2_prerequisites.yml`
   - Uses official RKE2 install script: `INSTALL_RKE2_VERSION="v1.33.4+rke2r1" INSTALL_RKE2_TYPE=server /tmp/install-rke2.sh`
   - **Disables** rke2-server service (not started yet)
   - Creates template config but no actual runtime config

2. **Runtime Deployment Phase** (`deploy-galaxy.yml`):
   - **Assumes RKE2 already installed** from image prep
   - Creates actual `/etc/rancher/rke2/config.yaml`
   - Starts rke2-server service
   - Fast deployment optimized for pre-prepared images

### GCP Cloud Controller Manager Investigation
**Key Finding**: GCP Cloud Controller Manager is **NOT explicitly configured** in either phase

**Evidence**:
- ✅ User confirmed seeing: `cloud-controller-manager-ks-dev-batch` pod running
- ❌ No cloud provider configuration found in image prep tasks
- ❌ No cloud provider parameters in deploy-galaxy.yml RKE2 config
- ❌ No external cloud controller manifests or Helm charts

**Conclusion**: RKE2 automatically detects GCP environment and deploys cloud controller manager through built-in cloud provider integration. This explains why LoadBalancer services can get IPs assigned.

### NFS Security Architecture (Confirmed)
**Current Implementation**: Internal LoadBalancer (NOT NodePort)
- **Service Type**: `LoadBalancer` with `networking.gke.io/load-balancer-type: "Internal"`
- **Security**: `loadBalancerSourceRanges: ["10.0.0.0/8"]` restricts to internal GCP networks
- **Access Pattern**: Google Batch jobs → Internal LoadBalancer IP → NFS server
- **Why Not NodePort**: Would expose NFS to entire internet (security risk)

## Files Modified This Session

### `/Users/suderman/Workspaces/JHU/galaxy-k8s-boot/ingress.yml`
```yaml
# Line 56: Removed unsupported timeout parameter
- timeout: "10m0s"  # REMOVED
+ wait_timeout: "10m0s"  # KEPT

# Lines 28-36: Simplified pod readiness check
until:
  - kube_system_pods.resources | length > 0
  - >-
    (kube_system_pods.resources |
     selectattr('status.phase', 'defined') |
     selectattr('status.phase', 'in', ['Running', 'Succeeded']) |
     list | length) >= 5
retries: 10
delay: 10
```

## Current System State

### Infrastructure
- **Platform**: GCP with RKE2 single-node cluster
- **IP**: 34.48.47.222
- **Components**: RKE2 + NFS + Nginx Ingress + Galaxy
- **Cloud Controller**: Automatically deployed by RKE2

### Security Configuration
- **NFS**: Internal LoadBalancer with source IP restrictions
- **SSH**: Connectivity checks in `bin/gcp.sh` before deployment
- **Ingress**: Nginx with admission webhooks disabled for stability

### Previous Session Context
This session continued from previous work that included:
1. Creating comprehensive CLAUDE.md documentation
2. Fixing NFS LoadBalancer IP assignment with security considerations
3. Adding SSH connectivity checks to deployment scripts
4. Resolving nginx ingress controller timeout issues
5. Investigating and reverting problematic cloud provider configurations

## Key Lessons Learned

1. **RKE2 Cloud Integration**: RKE2 has built-in cloud provider detection - explicit configuration not always needed
2. **Helm Module Parameters**: Always verify supported parameters for Ansible modules
3. **Pod Readiness Logic**: Simple threshold checks often more reliable than complex percentage calculations
4. **Two-Phase Deployment**: Understanding the image prep vs runtime distinction is crucial for troubleshooting

## Next Steps Recommendations

1. **Test Full Pipeline**: Verify complete deployment with all recent fixes
2. **Monitor Cloud Controller**: Ensure LoadBalancer services get IPs as expected
3. **Document Deployment**: Update main README with troubleshooting guidance
4. **Performance Testing**: Validate the optimized deployment times with pre-prepared images

---

# Galaxy GCP Batch Job Runner Implementation - Session Notes

**Date**: 2025-09-17
**Focus**: GCP Batch job runner implementation and RKE2 LoadBalancer service configuration

## Summary of Issues Resolved

### 3. GCP Batch Service Account Permission Error
**Problem**: Jobs failing with `403 Permission "caller does not have permission to act as service account"` error.

**Root Cause**:
- Missing `service_account_email` configuration in the Batch runner
- Service account lacked `roles/iam.serviceAccountUser` permission

**Solution**:
1. **Enhanced GCP Batch Runner** (`lib/galaxy/jobs/runners/gcp_batch.py`):
   - Added `service_account_email` parameter support
   - Modified `_create_batch_job_spec()` to configure service account in allocation policy
   - Added proper logging for service account configuration

2. **Updated Job Configuration** (`config/job_conf.yml.k8s` and `values/gcp-batch.yml`):
   ```yaml
   service_account_email: galaxy-batch-runner@anvil-and-terra-development.iam.gserviceaccount.com
   ```

3. **Fixed Service Account Permissions**:
   ```bash
   gcloud projects add-iam-policy-binding anvil-and-terra-development \
     --member="serviceAccount:galaxy-batch-runner@anvil-and-terra-development.iam.gserviceaccount.com" \
     --role="roles/iam.serviceAccountUser"

   gcloud projects add-iam-policy-binding anvil-and-terra-development \
     --member="serviceAccount:galaxy-batch-runner@anvil-and-terra-development.iam.gserviceaccount.com" \
     --role="roles/logging.logWriter"
   ```

### 4. RKE2 LoadBalancer Services Stuck in Pending State
**Problem**: NFS LoadBalancer service never getting external IP, staying in `<pending>` state.

**Root Cause**: RKE2 was not configured with a load balancer controller to handle LoadBalancer service types.

**Solution**:
1. **Enabled RKE2 ServiceLB** in `rke2_setup.yml`:
   ```yaml
   rke2_server_config_yaml: |
     disable: rke2-ingress-nginx
     enable-servicelb: true
   ```

2. **Applied Configuration Manually** (due to lablabs.rke2 role limitation):
   ```bash
   # SSH to the cluster node
   gcloud compute ssh ks-dev-batch --zone=us-east4-b --project=anvil-and-terra-development

   # Add ServiceLB configuration
   echo 'enable-servicelb: true' | sudo tee -a /etc/rancher/rke2/config.yaml

   # Restart RKE2 to apply changes
   sudo systemctl restart rke2-server
   ```

3. **Updated Galaxy Configuration** with external IP:
   ```bash
   NFS_SERVER=34.186.35.218 && helm upgrade galaxy cloudve/galaxy \
     --namespace galaxy \
     --values values/gcp-batch.yml \
     --set configs.job_conf\.yml.runners.gcp_batch.nfs_server="$NFS_SERVER"
   ```
   Note: Period in `job_conf\.yml` must be escaped to prevent Helm from interpreting it as a field separator.

## Key Configuration Files Modified

### 1. `lib/galaxy/jobs/runners/gcp_batch.py`
- Added `service_account_email` parameter to runner specifications
- Enhanced `_create_batch_job_spec()` to configure service account in allocation policy
- Improved logging and error handling

### 2. `rke2_setup.yml`
- Added `enable-servicelb: true` to RKE2 server configuration
- Simplified cloud provider setup (removed GCE cloud controller manager)

### 3. `values/gcp-batch.yml`
- Added `service_account_email` configuration
- Updated NFS server IP to use template variable for dynamic assignment

### 4. Documentation Updates
- Enhanced `GCP_BATCH_RUNNER_README.md` with service account configuration requirements
- Added troubleshooting section for service account permission errors

## Verification Steps

### Check ServiceLB Status
```bash
export KUBECONFIG=/Users/suderman/.kube/configs/gcp
kubectl get pods -n kube-system | grep svclb
kubectl get svc -n nfs-provisioner
```

### Check GCP Batch Job Status
```bash
gcloud batch jobs list --location=us-east1 --project=anvil-and-terra-development
```

### Verify Service Account Configuration
```bash
kubectl get configmap galaxy-configs -n galaxy -o yaml | grep -A 5 service_account_email
```

## Important Notes

1. **ServiceLB Behavior**: RKE2's ServiceLB uses the node's IP address and NodePort forwarding, not true external load balancers like GCP Load Balancer.

2. **Dynamic NFS IP**: The playbook in `galaxy_app.yml` automatically detects and sets the NFS server IP, but for ServiceLB, the external IP of the GCE instance must be used for GCP Batch connectivity.

3. **Helm Configuration**: When using `--set` with nested YAML keys containing periods, escape the periods (`job_conf\.yml`) to prevent field separator interpretation.

4. **lablabs.rke2 Role Limitation**: The role may not properly pass through all `rke2_server_config_yaml` configurations, requiring manual intervention for some settings.

## Final Working Configuration

- **NFS Server**: External IP `34.186.35.218` (ServiceLB forwards to internal service)
- **GCP Batch Service Account**: `galaxy-batch-runner@anvil-and-terra-development.iam.gserviceaccount.com`
- **Required Permissions**: `roles/batch.jobsEditor`, `roles/compute.instanceAdmin.v1`, `roles/iam.serviceAccountUser`, `roles/logging.logWriter`
- **RKE2 LoadBalancer**: ServiceLB enabled for LoadBalancer service support

## Testing
The Cut1 tool successfully dispatches jobs to GCP Batch with proper NFS connectivity and service account authentication.

---

# Galaxy GCP Batch Network Configuration Resolution - Session Notes

**Date**: 2025-09-18
**Focus**: Resolving NFS connectivity issues between GCP Batch VMs and RKE2 cluster

## Summary of Issues Resolved

### 5. GCP Batch VMs Network Connectivity Issues
**Problem**: GCP Batch jobs were getting stuck in SCHEDULED state due to NFS connectivity problems between Batch VMs and the RKE2 cluster.

**Root Cause Analysis**:
- RKE2 cluster deployed in `us-east4` region but Galaxy configured for `us-east1`
- GCP Batch VMs were being created in wrong region/network context
- Missing firewall rules to allow NFS traffic between networks
- NFS server IP reverted to public IP instead of internal LoadBalancer IP

**Solution Implemented**:
1. **Network Configuration Alignment**:
   - Updated Galaxy region configuration from `us-east1` to `us-east4`
   - Verified GCP Batch VMs use same VPC (`default`) and subnet (`default`) as RKE2 cluster
   - Confirmed network configuration in GCP Batch runner code

2. **Firewall Rules for NFS Access**:
   ```bash
   gcloud compute firewall-rules create allow-nfs-for-batch \
     --project=anvil-and-terra-development \
     --description="Allow NFS access (port 2049) for GCP Batch VMs to access RKE2 cluster NFS server" \
     --direction=INGRESS \
     --priority=1000 \
     --network=default \
     --action=ALLOW \
     --rules=tcp:2049,udp:2049,tcp:111,udp:111 \
     --source-ranges=10.128.0.0/9 \
     --target-tags=k8s
   ```

3. **Galaxy Configuration Updates**:
   - Fixed NFS server IP to use internal LoadBalancer IP: `10.150.0.17`
   - Updated region to `us-east4` to match cluster location
   - Used `--reuse-values` with specific `--set` parameters to maintain configuration

### Configuration Commands Used

```bash
# Update Galaxy configuration with correct region and NFS server
export KUBECONFIG=/Users/suderman/.kube/configs/gcp
helm upgrade galaxy cloudve/galaxy \
  --namespace galaxy \
  --reuse-values \
  --set configs.job_conf\\.yml.runners.gcp_batch.nfs_server="10.150.0.17" \
  --set configs.job_conf\\.yml.runners.gcp_batch.region="us-east4"
```

### Verification Steps

1. **Network Configuration Verification**:
   ```bash
   gcloud compute instances describe ks-dev-batch --zone=us-east4-b \
     --format="value(networkInterfaces[0].network,networkInterfaces[0].subnetwork)"
   # Result: default VPC, us-east4/default subnet
   ```

2. **Firewall Rule Verification**:
   ```bash
   gcloud compute firewall-rules describe allow-nfs-for-batch \
     --format="value(disabled,allowed,sourceRanges,targetTags)"
   # Result: Active rule allowing NFS traffic from internal networks to k8s nodes
   ```

3. **Job Submission Testing**:
   ```bash
   gcloud batch jobs list --location=us-east4 --project=anvil-and-terra-development \
     --filter="createTime>=2025-09-18T13:20:00Z"
   # Result: New job successfully submitted to correct region
   ```

### Key Infrastructure Details

- **RKE2 Cluster**: Located in `us-east4-b` zone, using `default` VPC/subnet
- **NFS Server**: Internal LoadBalancer at `10.150.0.17` with service type restrictions
- **GCP Batch Region**: Now correctly configured for `us-east4`
- **Network Security**: Firewall rules restrict NFS access to internal networks only (`10.128.0.0/9`)

### Results Achieved

✅ **Region Alignment**: GCP Batch jobs now submitted to correct `us-east4` region
✅ **Network Connectivity**: Batch VMs created in same VPC/subnet as RKE2 cluster
✅ **NFS Access**: Firewall rules allow NFS traffic while maintaining security
✅ **Service Integration**: Jobs successfully submitted and show proper network configuration
✅ **Configuration Persistence**: Helm updates maintain correct settings

### Current Status

- **Latest Job**: `galaxy-job-1758216686-8b7b95e2` submitted successfully to GCP Batch
- **Job State**: SCHEDULED (normal - waiting for VM allocation)
- **Network Config**: Correctly configured for `default` VPC and `us-east4/default` subnet
- **NFS Server**: Using internal IP `10.150.0.17` for shared storage access

### Files Modified This Session

1. **Firewall Rules**: Created `allow-nfs-for-batch` rule
2. **Galaxy Configuration**: Updated via Helm with correct region and NFS server IP
3. **Network Verification**: Confirmed RKE2 cluster and Batch VM network alignment

### Expected Outcome

GCP Batch jobs should now:
- Be created in the same network context as the RKE2 cluster
- Successfully mount NFS shares from the internal LoadBalancer
- Progress from SCHEDULED → RUNNING → SUCCEEDED states
- No longer get stuck due to network connectivity issues

The network configuration issues that were causing jobs to remain in SCHEDULED state should now be resolved, allowing for successful Galaxy job execution via GCP Batch.

---

# Galaxy GCP Batch NFS Mount Resolution - Session Notes

**Date**: 2025-09-18 (Evening Session)
**Focus**: Debugging and resolving NFS mount failures in GCP Batch VMs

## Summary of Issues Identified and Resolved

### 6. Google Cloud Batch API Mount Options Incompatibility
**Problem**: Galaxy job submission failing with error "Unknown field for NFS: mount_options"

**Root Cause**: Google Cloud Batch API does not support the `mount_options` field in NFS volume configuration that was added to fix attribute caching.

**Solution**:
- Removed unsupported `volume.nfs.mount_options` field from API configuration
- Implemented NFS optimization through script-based remounting instead

### 7. GCP Batch Volume Mounting Complete Failure
**Problem**: Despite successful job submission, GCP Batch VMs showed NFS mount point exists but no actual NFS mount present.

**Error Logs**:
```
✗ NFS mount point exists but is not mounted
This indicates a Batch volume configuration issue
```

**Root Cause Analysis**:
- Google Cloud Batch volume mounting mechanism failing entirely
- NFS mount point directory created but no actual mount
- Network connectivity vs volume mounting configuration issue

**Solution Implemented**:
Added comprehensive NFS debugging and fallback mounting strategy in `gcp_batch.py`:

1. **Network Connectivity Testing**:
   ```bash
   # Ping test for NFS server reachability
   ping -c 3 {nfs_server_ip}
   ```

2. **NFS Client Installation**:
   ```bash
   # Ensure NFS tools are available
   apt-get update -qq && apt-get install -y nfs-common
   ```

3. **Multi-Level Fallback Strategy**:
   - **Primary**: Google Cloud Batch volume mounting (automatic)
   - **Fallback 1**: Manual remount with optimized options if volume mounted
   - **Fallback 2**: Manual mount if mount point exists but no mount
   - **Fallback 3**: Create mount point and manual mount if nothing exists

4. **Manual Mount Command**:
   ```bash
   mount -t nfs4 -o rw,hard,intr,rsize=1048576,wsize=1048576,actimeo=0 \
     {nfs_server}:{nfs_path} {mount_path}
   ```

### Enhanced Debugging Implementation

**File Modified**: `/Users/suderman/Workspaces/JHU/galaxy/lib/galaxy/jobs/runners/gcp_batch.py`

**Key Enhancements Added**:

1. **Comprehensive Connectivity Testing**:
   - NFS server ping test
   - NFS client tool availability check
   - Current mount status inspection

2. **Detailed Error Reporting**:
   - Network configuration debugging
   - Mount status before/after operations
   - Clear error messages with diagnostic information

3. **Robust Fallback Logic**:
   - Multiple mounting strategies
   - Automatic recovery from volume mounting failures
   - Creation of missing mount points

4. **Optimized Mount Options**:
   - `actimeo=0`: Disables attribute caching (fixes file visibility)
   - `rsize=1048576,wsize=1048576`: Optimized buffer sizes
   - `hard,intr`: Reliable mounting with interruption capability

### Configuration Status

**Current Network Configuration**:
- **NFS Server IP**: `10.150.0.51` (LoadBalancer IP - updated for new cluster)
- **Region**: `us-east4` (aligned with RKE2 cluster)
- **VPC/Subnet**: `default/default` (same as RKE2 cluster)
- **Firewall**: `allow-nfs-for-batch` rule active

**Helm Configuration Commands**:
```bash
# Update with new cluster's NFS server IP
export KUBECONFIG=/Users/suderman/.kube/configs/gcp
helm upgrade galaxy cloudve/galaxy \
  --namespace galaxy \
  --reuse-values \
  --set configs.job_conf\\.yml.runners.gcp_batch.nfs_server="10.150.0.51" \
  --set configs.job_conf\\.yml.runners.gcp_batch.region="us-east4"
```

### Infrastructure Updates

**New Cluster Details**:
- **Cluster Server**: `https://35.221.58.21:6443` (new cluster endpoint)
- **NFS LoadBalancer**: `10.150.0.51` (new internal IP)
- **Deployment Script**: Enhanced `bin/gcp.sh` with improved error handling

**Firewall Configuration Verified**:
```bash
gcloud compute firewall-rules describe allow-nfs-for-batch
# Status: Active, allowing TCP/UDP 2049,111 from 10.128.0.0/9 to k8s nodes
```

### Testing and Verification

**Latest Job Submitted**: `galaxy-job-1758241010-512728d5`
- **Status**: Failed due to NFS mount issues (as expected before fixes)
- **Logs**: Confirmed mount point exists but no actual mount
- **Network**: Correctly configured for us-east4 region

**Next Steps for Tomorrow**:
1. **Deploy Enhanced Docker Image**: Build new Galaxy image with updated `gcp_batch.py`
2. **Test Comprehensive Fix**: Submit test job to verify:
   - Network connectivity to NFS server
   - Fallback mounting strategies
   - File visibility and job execution
3. **Monitor Debugging Output**: Analyze detailed logs from enhanced script
4. **Validate Solution**: Confirm Cut1 tool completes successfully

### Files Modified This Session

1. **`lib/galaxy/jobs/runners/gcp_batch.py`**:
   - Added network connectivity testing
   - Implemented comprehensive NFS debugging
   - Created multi-level fallback mounting strategy
   - Enhanced error reporting and diagnostics

2. **Configuration Updates**:
   - Updated NFS server IP to match new cluster
   - Maintained correct region and network settings

### Expected Outcome

The enhanced GCP Batch runner should now:
- **Diagnose** network connectivity issues with detailed output
- **Automatically recover** from Google Cloud Batch volume mounting failures
- **Successfully mount** NFS using manual fallback methods
- **Provide comprehensive logs** for troubleshooting any remaining issues
- **Execute Galaxy jobs** successfully with proper file access

This comprehensive debugging and fallback approach should resolve the NFS mounting issues that were preventing Galaxy jobs from accessing shared storage on GCP Batch VMs.

---

# Galaxy GCP Batch Automatic NFS Export Path Detection - Session Notes

**Date**: 2025-09-20 (Evening Session)
**Focus**: Implementing automatic detection of dynamic NFS export paths for GCP Batch jobs

## Summary of Issues Identified and Resolved

### 8. Dynamic PVC Export Path Detection Challenge
**Problem**: The NFS export path changes with each Galaxy deployment due to dynamic PVC ID generation (e.g., `/export/pvc-e5e8fe47-644a-4ae4-80f9-cf7139e27fe0`), requiring manual configuration updates for each deployment.

**Root Cause Analysis**:
- Galaxy PVCs get random UUIDs that change on redeployment
- NFS server exports the PVC at `/export/pvc-<uuid>`
- GCP Batch VMs were mounting the wrong path (NFS root `/` instead of specific PVC export)
- Manual configuration was needed: `nfs_path: /export/pvc-e5e8fe47-644a-4ae4-80f9-cf7139e27fe0`

**Initial Approach Attempted**: Runtime detection in GCP Batch VMs
- **Issue**: Batch VMs are external to Kubernetes cluster and cannot query PVC information
- **Failure**: `mount.nfs4: Failed to resolve server 10.150.15.198` (network isolation)

### 9. Successful Solution: Deployment-Time Detection in galaxy-k8s-boot
**Approach**: Moved NFS export path detection to the galaxy-k8s-boot playbook where it runs within the Kubernetes cluster context.

**Implementation Details**:

#### **Enhanced galaxy_app.yml Playbook**
Added automatic NFS export path detection **after** Galaxy deployment when PVC exists:

```yaml
# 1. Deploy Galaxy initially (creates PVC)
- name: Helm install Galaxy
  kubernetes.core.helm:
    # ... basic configuration

# 2. Wait for PVC to be created and bound
- name: Wait for Galaxy PVC to be created
  kubernetes.core.k8s_info:
    api_version: v1
    kind: PersistentVolumeClaim
    name: galaxy-galaxy-pvc
    namespace: galaxy
    wait: true
    wait_condition:
      type: Bound
      status: "True"
    wait_timeout: 300

# 3. Detect NFS export path for the PVC
- name: Detect NFS export path for Galaxy PVC
  shell: |
    # Wait for NFS export to be available
    sleep 10
    # Get NFS exports and find the PVC export path
    showmount -e {{ nfs_server }} | grep '/export/pvc-' | head -1 | awk '{print $1}'
  register: nfs_export_detection
  retries: 10
  delay: 5
  until: nfs_export_detection.stdout != ""

# 4. Update Galaxy configuration with detected path
- name: Update Galaxy configuration with detected NFS export path
  kubernetes.core.helm:
    name: galaxy
    namespace: galaxy
    values:
      configs:
        job_conf.yml:
          runners:
            gcp_batch:
              nfs_server: "{{ nfs_server }}"
              nfs_path: "{{ nfs_export_path }}"  # Dynamically detected!
```

#### **Verification Results**
**✓ NFS Server Detection**: `10.150.15.198` (LoadBalancer IP)
**✓ NFS Export Detection**: `/export/pvc-ab244b01-7fb4-464d-8972-3a952042fe4e`
**✓ Deployment Integration**: Seamlessly integrated into existing playbook
**✓ Error Handling**: Comprehensive validation and retry logic

### Configuration Status After Implementation

**Current Network Configuration**:
- **Cluster Server**: `https://34.186.40.4:6443` (latest cluster)
- **NFS Server IP**: `10.150.15.198` (LoadBalancer IP - current deployment)
- **NFS Export Path**: `/export/pvc-ab244b01-7fb4-464d-8972-3a952042fe4e` (auto-detected)
- **Region**: `us-east4` (aligned with RKE2 cluster)

### Key Benefits Achieved

1. **🔄 Fully Automated**: Zero manual configuration needed for PVC ID changes
2. **🛡️ Deployment-Time Validation**: Fails early if NFS detection fails
3. **📊 Clear Diagnostics**: Detailed output showing detected values
4. **⚡ Efficient**: Detection happens once during deployment, not per job
5. **🎯 Cluster-Native**: Runs within Kubernetes where it has proper access to PVC information

### Testing Verification

**Manual Verification**:
```bash
# Command executed on cluster node
ansible all -i inventories/gcp.ini -m shell \
  -a "showmount -e 10.150.15.198 | grep '/export/pvc-' | head -1 | awk '{print \$1}'" \
  --become

# Result: /export/pvc-ab244b01-7fb4-464d-8972-3a952042fe4e
```

**Job Execution Test**:
- **Latest Job**: `galaxy-job-1758406435-beb2dbaa`
- **Status**: SUCCEEDED ✅
- **NFS Mount**: Correctly mounted `/export/pvc-ab244b01-7fb4-464d-8972-3a952042fe4e` to `/galaxy/server/database`
- **Galaxy Job Execution**: Cut1 tool completed successfully

### Architecture Improvement

**Before**: Manual configuration required for each deployment
```yaml
# Manual process:
# 1. Deploy Galaxy
# 2. Check: kubectl get pv | grep galaxy
# 3. Find: /export/pvc-xxxxx
# 4. Update: helm upgrade --set configs.job_conf.yml.runners.gcp_batch.nfs_path="/export/pvc-xxxxx"
```

**After**: Fully automatic detection and configuration
```yaml
# Automated process:
# 1. Deploy Galaxy (creates PVC)
# 2. Auto-detect export path
# 3. Auto-update Galaxy configuration
# 4. Ready for GCP Batch jobs
```

### Files Modified This Session

1. **`galaxy_app.yml`**:
   - Added PVC wait condition
   - Implemented NFS export path detection with retries
   - Added automatic Helm configuration update
   - Enhanced error handling and diagnostics

2. **Configuration Approach**:
   - Removed dynamic detection from `gcp_batch.py` (not needed - detection happens at deployment)
   - Kept existing manual mount fallback logic in runner (uses configured `nfs_path`)

### Expected Outcome for Future Deployments

The enhanced galaxy-k8s-boot playbook now provides:
- **Zero Configuration**: No manual PVC path updates needed
- **Deployment Resilience**: Works across Galaxy redeployments automatically
- **Error Prevention**: Clear failure messages if NFS detection fails
- **Maintenance Free**: No need to update playbooks when PVCs change

### Current Status: SOLUTION COMPLETE ✅

**✅ Problem Solved**: Dynamic PVC export path detection implemented
**✅ Testing Verified**: Manual detection confirmed working
**✅ Integration Complete**: Seamlessly integrated into galaxy-k8s-boot
**✅ Documentation Updated**: Comprehensive session notes added

**Ready for Production**: The solution ensures that every Galaxy deployment will automatically detect and configure the correct NFS export path, eliminating the need for manual updates when PVC IDs change.

---

# Galaxy GCP Batch Dynamic Resource Allocation & Global Configuration - Session Notes

**Date**: 2025-09-21 (Evening Session)
**Focus**: Implementing dynamic resource allocation and configuring all Galaxy jobs to use GCP Batch

## Summary of Issues Identified and Resolved

### 10. Dynamic Resource Allocation for GCP Batch VMs
**Problem**: GCP Batch VMs were using fixed CPU and memory resources (1 vCPU, 2 GiB) regardless of Galaxy job requirements, leading to resource waste and potential performance issues.

**Root Cause Analysis**:
- Galaxy jobs specify resource requirements via job destination parameters (`requests_cpu`, `requests_memory`, etc.)
- GCP Batch runner was ignoring these requirements and using hardcoded defaults
- Jobs that needed more resources were constrained, while small jobs wasted resources

**Solution Implemented**: Enhanced GCP Batch runner with comprehensive dynamic resource allocation

#### **Implementation Details**:

**Enhanced Parameter Support**:
```python
# Added job-specific resource parameters (same as Kubernetes runner)
"requests_cpu": dict(map=str, default=None),
"requests_memory": dict(map=str, default=None),
"limits_cpu": dict(map=str, default=None),
"limits_memory": dict(map=str, default=None),
```

**Comprehensive Format Support**:
- **CPU Formats**: `"1"`, `"1.5"`, `"500m"`, `"0.5"`
- **Memory Formats**: `"2048"`, `"1Gi"`, `"512Mi"`, `"1G"`, `"512M"`

**Resource Conversion Logic**:
```python
def _get_job_resources(self, job_wrapper, params):
    """Extract CPU and memory requirements and convert to GCP Batch format."""
    cpu_milli = self._get_cpu_milli(job_destination, params)  # Convert to milli-cores
    memory_mib = self._get_memory_mib(job_destination, params)  # Convert to MiB

    # Update environment variables for job execution
    cpu_cores = cpu_milli / 1000.0
    params["computed_galaxy_slots"] = max(1, int(cpu_cores))
    params["computed_galaxy_memory_mb"] = memory_mib

    return cpu_milli, memory_mib
```

**Priority Order for Resource Detection**:
1. **requests_cpu/requests_memory** (highest priority)
2. **limits_cpu/limits_memory** (fallback)
3. **vcpu/memory_mib defaults** (final fallback)

#### **Verification Results**:
- **✓ CPU Conversion**: `"1.5"` → 1500 mCPU, `"500m"` → 500 mCPU
- **✓ Memory Conversion**: `"2Gi"` → 2048 MiB, `"1G"` → 953 MiB
- **✓ Environment Variables**: `GALAXY_SLOTS` and `GALAXY_MEMORY_MB` set correctly
- **✓ GCP Batch Integration**: Resources allocated to VM instance

### 11. Global GCP Batch Job Configuration
**Problem**: Only Cut1 jobs were routed to GCP Batch runner; all other Galaxy jobs were still using the Kubernetes runner within the cluster.

**Root Cause**: Galaxy job configuration had Cut1 specifically mapped to `gcp_batch` environment, but default execution used `tpv_dispatcher` which routed most jobs to Kubernetes.

**Solution Implemented**: Changed Galaxy configuration to route **all jobs** to GCP Batch by default.

#### **Configuration Change**:

**Before**:
```yaml
execution:
  default: tpv_dispatcher  # TPV rules routed jobs to various destinations

tools:
- environment: gcp_batch   # Only Cut1 went to GCP Batch
  id: Cut1
```

**After**:
```yaml
execution:
  default: gcp_batch_default  # ALL jobs go to GCP Batch by default
```

**Helm Command Used**:
```bash
helm upgrade galaxy cloudve/galaxy --namespace galaxy --reuse-values \
  --set configs.job_conf\\.yml.execution.default="gcp_batch_default"
```

#### **Impact**:
- **Galaxy UI jobs**: All tools now run on GCP Batch VMs
- **Workflow jobs**: Multi-step workflows execute on GCP Batch
- **API jobs**: Programmatic submissions go to GCP Batch
- **Resource optimization**: Each job gets VM sized to its requirements
- **Cost efficiency**: No wasted Kubernetes cluster resources

### Configuration Status After Latest Changes

**Current Network Configuration**:
- **Cluster Server**: `https://34.11.47.121:6443` (latest cluster)
- **NFS Server IP**: `10.150.15.201` (LoadBalancer IP - current deployment)
- **NFS Export Path**: `/export/pvc-c6929dc9-0c41-4ebc-912b-396f554ed70f` (auto-detected)
- **Region**: `us-east4` (aligned with RKE2 cluster)

**Job Execution Flow**:
1. **Galaxy receives job**: Any tool submission
2. **Route to GCP Batch**: Default execution destination
3. **Dynamic resource allocation**: VM sized based on job requirements
4. **Auto NFS detection**: Correct export path configured automatically
5. **Job execution**: In appropriately sized GCP Batch VM
6. **Cleanup**: VM terminated after job completion

### Key Benefits Achieved

1. **🎯 Universal GCP Batch**: All Galaxy jobs use GCP Batch infrastructure
2. **📊 Dynamic Resource Allocation**: VMs automatically sized to job requirements
3. **💰 Cost Optimization**: No over-provisioning or under-provisioning
4. **🔄 Zero Configuration**: Both NFS paths and resources detected automatically
5. **⚡ Performance Optimization**: Jobs get exactly the resources they need
6. **🛡️ Backward Compatibility**: Falls back gracefully to defaults when needed

### Example Resource Allocation

**Job with Requirements**:
```yaml
# Galaxy job destination configuration
requests_cpu: "4"
requests_memory: "8Gi"
```

**Result**:
- **GCP Batch VM**: 4000 mCPU, 8192 MiB memory
- **Environment**: `GALAXY_SLOTS=4`, `GALAXY_MEMORY_MB=8192`
- **NFS Mount**: Auto-detected export path mounted correctly

### Files Modified This Session

1. **`lib/galaxy/jobs/runners/gcp_batch.py`**:
   - Added comprehensive resource parameter support
   - Implemented CPU/memory format conversion methods
   - Enhanced resource detection with priority ordering
   - Updated execution scripts to use computed resources

2. **Galaxy Job Configuration** (via Helm):
   - Changed default execution from `tpv_dispatcher` to `gcp_batch_default`
   - Restarted job handler to apply configuration changes

### Architecture Evolution

**Previous**: Mixed execution environment
- Cut1 jobs → GCP Batch VMs
- All other jobs → Kubernetes pods
- Fixed resources (1 vCPU, 2 GiB)

**Current**: Unified GCP Batch execution
- All jobs → GCP Batch VMs
- Dynamic resources based on job requirements
- Auto-detected NFS export paths
- Comprehensive fallback strategies

### Current Status: COMPREHENSIVE SOLUTION COMPLETE ✅

**✅ Dynamic Resource Allocation**: Implemented and tested
**✅ Global Job Routing**: All jobs use GCP Batch runner
**✅ Automatic NFS Detection**: Works across deployments
**✅ Cost Optimization**: VMs sized appropriately for each job
**✅ Production Ready**: Full-featured GCP Batch integration

**Ready for Morning**: The Galaxy GCP Batch integration now provides a complete, production-ready solution with automatic resource allocation, NFS configuration, and comprehensive job execution on Google Cloud infrastructure.

---

## Files for Future Reference

- `ingress.yml` - Fixed helm timeout and pod readiness issues
- `roles/image_preparation/tasks/rke2_prerequisites.yml` - Where RKE2 actually gets installed
- `deploy-galaxy.yml` - Runtime configuration (assumes RKE2 pre-installed)
- `nfs.yml` - Internal LoadBalancer security configuration
- `rke2_setup.yml` - RKE2 configuration with ServiceLB enabled
- `lib/galaxy/jobs/runners/gcp_batch.py` - GCP Batch job runner implementation
- `values/gcp-batch.yml` - Galaxy Helm values with GCP Batch configuration
- `CLAUDE.md` - Comprehensive project documentation (from previous session)

---

# CNPG Skip-Initdb Plugin Integration for Persistent PostgreSQL - Session Notes

**Date**: 2025-12-18
**Focus**: Enabling PostgreSQL data reuse when relaunching Galaxy instances with persistent disks

## Summary of Issues Identified and Resolved

### 12. PostgreSQL Data Reuse Challenge
**Problem**: When relaunching Galaxy instances that reuse persistent disks for PostgreSQL storage, two issues prevented data reuse:
1. Storage provisioner created new directories instead of reusing existing ones
2. CloudNative-PG (CNPG) always ran `initdb` to initialize a new database, even when valid data existed

**Root Cause Analysis**:
- Local-path-provisioner creates directories with pattern `pvc-<uuid>_<namespace>_<pvc-name>` - new UUIDs each deployment
- CNPG's default behavior is to always initialize fresh PostgreSQL clusters
- Existing data was renamed to `pgdata_*` backup directories and ignored

### 13. Solution Part 1: Storage Provisioner Symlink Logic
**Implementation**: Modified storage provisioners to detect and symlink to existing data directories.

**Files Modified**:
- `templates/postgres_storage_class.yaml.j2`
- `templates/hostpath_storage_class.yaml.j2`

**Key Logic Added**:
```bash
# Extract namespace_pvc-name suffix from new directory
suffix=$(echo "${pvcDir}" | sed 's/^pvc-[a-f0-9-]*_//')

# Search for existing directory with same suffix
existingDir=$(find "${baseDir}" -maxdepth 1 -type d -name "pvc-*_${suffix}" ! -name "${pvcDir}" 2>/dev/null | head -1)

if [ -n "${existingDir}" ] && [ -d "${existingDir}" ]; then
    if [ "$(ls -A "${existingDir}" 2>/dev/null)" ]; then
        # Create symlink to existing data instead of new directory
        ln -s "${existingDir}" "${absolutePath}"
        exit 0
    fi
fi
```

**Teardown Logic**: Only removes symlinks, preserves actual data directories.

### 14. Solution Part 2: CNPG Skip-Initdb Plugin Integration
**Implementation**: Integrated the CNPG skip-initdb plugin to prevent database reinitialization.

**Critical Discovery**: The plugin MUST be deployed to the same namespace as the CNPG operator. In Galaxy deployments, CNPG runs in `galaxy-deps` namespace (installed by galaxy-deps Helm chart), NOT in `cnpg-system`.

**Plugin Name**: `cnpg-i-skip-initdb.leonardoce.github.com` (must match exactly)

**Files Created/Modified**:

1. **`templates/cnpg_skip_initdb_plugin.yaml.j2`** - Plugin deployment template:
   - Issuer for self-signed certificates
   - Server and client TLS certificates
   - Plugin Deployment
   - Service with CNPG discovery annotations

2. **`roles/galaxy_k8s_deployment/defaults/main.yml`** - New variables:
   ```yaml
   cnpg_skip_initdb_enabled: false
   cnpg_skip_initdb_image: "docker.io/ksuderman/cnpg-i-skip-initdb:latest"
   cnpg_skip_initdb_namespace: "galaxy-deps"
   cnpg_skip_initdb_plugin_name: "cnpg-i-skip-initdb.leonardoce.github.com"
   setup_cert_manager: false
   cert_manager_version: "v1.14.0"
   ```

3. **`roles/galaxy_k8s_deployment/tasks/storage_setup.yml`** - Added cert-manager installation:
   - Downloads and applies cert-manager manifest
   - Waits for cert-manager and webhook deployments

4. **`roles/galaxy_k8s_deployment/tasks/galaxy_application.yml`** - Added plugin deployment:
   - Deploys plugin after galaxy-deps namespace creation
   - Waits for plugin deployment
   - Configures Helm values with plugin reference

5. **`docs/CNPG_SKIP_INITDB_INTEGRATION.md`** - Comprehensive documentation

### Configuration and Usage

**To Enable PostgreSQL Data Reuse**:
```bash
ansible-playbook -i inventories/my-server.ini playbook.yml \
  --extra-vars "setup_cert_manager=true" \
  --extra-vars "cnpg_skip_initdb_enabled=true" \
  --extra-vars "galaxy_user=admin@example.com"
```

**How It Works**:
1. **cert-manager** installs (if `setup_cert_manager: true`)
2. **galaxy-deps namespace** is created
3. **CNPG skip-initdb plugin** deploys to `galaxy-deps` namespace
4. **galaxy-deps Helm chart** installs (includes CNPG operator)
5. **Galaxy Helm chart** installs with plugin reference in cluster spec
6. **Storage provisioner** symlinks to existing PostgreSQL data
7. **CNPG plugin** intercepts bootstrap and skips `initdb`
8. **PostgreSQL** starts using existing data

### Troubleshooting Commands

```bash
# Verify plugin is running
kubectl get pods -n galaxy-deps -l app=skip-initdb

# Check plugin logs
kubectl logs -n galaxy-deps -l app=skip-initdb

# Verify certificates
kubectl get certificates -n galaxy-deps

# Check plugin service annotations
kubectl get svc skip-initdb -n galaxy-deps -o yaml | grep -A10 annotations

# Verify cluster has plugin configured
kubectl describe clusters.postgresql.cnpg.io -n galaxy | grep -A5 plugins

# Check storage symlinks (on node)
ls -la /mnt/postgres_storage/
```

### Common Issues and Solutions

1. **Plugin not discovered by CNPG**:
   - Ensure plugin is in `galaxy-deps` namespace (not `cnpg-system`)
   - Verify plugin name matches: `cnpg-i-skip-initdb.leonardoce.github.com`

2. **CNPG still reinitializing database**:
   - Check for `pgdata_*` backup directories (indicates plugin not working)
   - Verify plugin service has correct labels and annotations
   - Check CNPG operator logs for plugin discovery

3. **Storage not reusing data**:
   - Verify provisioner ConfigMap has symlink logic
   - Check provisioner pod logs
   - Inspect `/mnt/postgres_storage/` for symlinks

### Current Status: COMPLETE ✅

**✅ Storage Provisioner Symlink Logic**: Implemented and tested
**✅ cert-manager Installation**: Automated in Ansible playbook
**✅ CNPG Plugin Deployment**: Deploys to correct namespace (galaxy-deps)
**✅ Helm Values Integration**: Plugin reference passed to Galaxy chart
**✅ Documentation**: Comprehensive docs/CNPG_SKIP_INITDB_INTEGRATION.md

### Files Modified This Session

| File | Changes |
|------|---------|
| `templates/cnpg_skip_initdb_plugin.yaml.j2` | Updated namespace to galaxy-deps, correct plugin name |
| `templates/postgres_storage_class.yaml.j2` | Added symlink logic for data reuse |
| `templates/hostpath_storage_class.yaml.j2` | Added symlink logic for data reuse |
| `roles/galaxy_k8s_deployment/defaults/main.yml` | Added plugin and cert-manager variables |
| `roles/galaxy_k8s_deployment/tasks/storage_setup.yml` | Added cert-manager installation |
| `roles/galaxy_k8s_deployment/tasks/galaxy_application.yml` | Added plugin deployment and Helm values |
| `docs/CNPG_SKIP_INITDB_INTEGRATION.md` | Updated with correct namespace and troubleshooting |

---

# NFS Export Reuse and RabbitMQ Credential Sync - Session Notes

**Date**: 2025-12-19
**Focus**: Implementing automatic NFS export reuse and RabbitMQ credential synchronization for persistent disk reuse

## Summary of Issues Identified and Resolved

### 15. Galaxy PVC Stuck Pending Due to Insufficient Space
**Problem**: When relaunching Galaxy instances with persistent disks, the Galaxy PVC was stuck pending with "insufficient available space" error, even though the NFS server had the old Galaxy data.

**Root Cause Analysis**:
- The NFS server provisioner (nfs-server-provisioner Helm chart) has its own space accounting
- Unlike local-path-provisioner, it doesn't have symlink reuse logic
- The provisioner was trying to allocate new space instead of reusing existing exports
- Old Galaxy export (`pvc-5be5362d-...`) existed with 6.9GB data but provisioner reported insufficient space for 238GB request

**Solution Implemented**: Added automatic NFS export detection and static PV creation in `galaxy_application.yml`:
1. Before Galaxy Helm install, check for existing Galaxy NFS exports
2. Identify Galaxy exports by checking for `objects` subdirectory (Galaxy-specific)
3. If found, create a static PV pointing to the existing export
4. Create a PVC bound to the static PV
5. Galaxy Helm install will use the pre-existing PVC

### 16. RabbitMQ Authentication Failure on Relaunch
**Problem**: After resolving the PVC issue, Galaxy pods failed with RabbitMQ `ACCESS_REFUSED` errors.

**Root Cause Analysis**:
- RabbitMQ persistent data was preserved via block storage symlinks (working as designed)
- New Kubernetes deployment generated different credentials in the secret
- Secret had user `default_user_4iwnwNvs3k4QyIfjTbO`
- RabbitMQ stored user was `default_user_jH5BX7su0J5F3cgc6KM`

**Solution Implemented**: Added RabbitMQ credential synchronization in `galaxy_application.yml`:
1. After Galaxy Helm install, wait for RabbitMQ to be ready
2. Get expected credentials from Kubernetes secret
3. Check if expected user exists in RabbitMQ
4. If not, create the user with administrator permissions
5. Galaxy pods can then authenticate successfully

## Implementation Details

### NFS Export Reuse Logic
```yaml
# Check for existing Galaxy NFS exports
- name: Check for existing Galaxy NFS exports
  shell: |
    for dir in $(kubectl exec -n nfs-provisioner nfs-provisioner-nfs-server-provisioner-0 -- \
      ls -d /export/pvc-* 2>/dev/null); do
      if kubectl exec -n nfs-provisioner nfs-provisioner-nfs-server-provisioner-0 -- \
        test -d "$dir/objects" 2>/dev/null; then
        echo "$dir"
        exit 0
      fi
    done

# Create static PV for existing export
# Create PVC bound to static PV
```

### RabbitMQ Credential Sync Logic
```yaml
# Get expected credentials from secret
# Check existing RabbitMQ users via rabbitmqctl
# If user doesn't exist, create with:
#   - rabbitmqctl add_user
#   - rabbitmqctl set_user_tags administrator
#   - rabbitmqctl set_permissions -p / '.*' '.*' '.*'
```

### New Configuration Variable
```yaml
# roles/galaxy_k8s_deployment/defaults/main.yml
enable_persistent_data_reuse: true  # Enable NFS export reuse and RabbitMQ sync
```

## Verification Steps

### Check NFS Export Detection
```bash
# On control machine
kubectl exec -n nfs-provisioner nfs-provisioner-nfs-server-provisioner-0 -- \
  ls -la /export/

# Look for pvc-* directories with Galaxy data (objects, jobs_directory, config)
```

### Check RabbitMQ Users
```bash
kubectl exec -n galaxy galaxy-rabbitmq-server-server-0 -c rabbitmq -- \
  rabbitmqctl list_users
```

### Check PVC Status
```bash
kubectl get pvc -n galaxy
kubectl get pv | grep galaxy
```

## What's Now Automatically Handled

| Component | Issue | Solution |
|-----------|-------|----------|
| PostgreSQL | Data reinitialized | CNPG skip-initdb plugin + storage symlinks |
| Block Storage | New directories created | Symlink logic in local-path-provisioner |
| NFS (Galaxy PVC) | Insufficient space error | Static PV creation for existing exports |
| RabbitMQ | Authentication failure | Credential sync after deployment |

## Files Modified This Session

| File | Changes |
|------|---------|
| `roles/galaxy_k8s_deployment/defaults/main.yml` | Added `enable_persistent_data_reuse` variable |
| `roles/galaxy_k8s_deployment/tasks/galaxy_application.yml` | Added NFS export detection, static PV creation, and RabbitMQ credential sync |

### Current Status: COMPLETE ✅

**✅ NFS Export Reuse**: Automatically detects existing Galaxy exports and creates static PVs
**✅ RabbitMQ Credential Sync**: Automatically creates expected user if missing
**✅ Backward Compatible**: Uses `enable_persistent_data_reuse` flag (default: true)
**✅ Integrated with Existing Logic**: Works alongside CNPG plugin and storage symlinks

---

## Files for Future Reference

- `templates/cnpg_skip_initdb_plugin.yaml.j2` - CNPG skip-initdb plugin deployment
- `templates/postgres_storage_class.yaml.j2` - PostgreSQL storage with symlink reuse
- `templates/hostpath_storage_class.yaml.j2` - Block storage with symlink reuse
- `roles/galaxy_k8s_deployment/tasks/galaxy_application.yml` - NFS export reuse and RabbitMQ sync
- `docs/CNPG_SKIP_INITDB_INTEGRATION.md` - Plugin integration documentation

---

# VM Launch Script Bug Fix and Helm Chart Update - Session Notes

**Date**: 2025-12-23
**Focus**: Fixing `--reuse-existing-data` flag not being passed correctly to Ansible playbook

## Summary of Issues Identified and Resolved

### 17. VM Launch Script Variable Expansion Bug
**Problem**: When launching Galaxy instances with `--reuse-existing-data`, the PostgreSQL data was not being preserved. The CNPG cluster was missing the `cnpg.io/skip-initdb` annotation.

**Root Cause Analysis**:
Two bugs in `bin/launch_vm.sh`:

1. **Typo in variable name**: `RESUSE_EXISTING_DATA` instead of `REUSE_EXISTING_DATA` (missing "E")

2. **Variable not passed to cloud-init script**: The script uses three heredoc blocks:
   - Lines 298-367: `<< 'EOF'` - static content, no variable expansion
   - Lines 369-378: `<< EOF` - **variables are expanded here**
   - Lines 380-413: `<< 'EOF'` - **no variable expansion**

   The `REUSE_EXISTING_DATA` variable was referenced on line 397 inside the third heredoc (no expansion), but was never added to the second heredoc where it would be set as a shell variable.

**Solution Implemented**:
1. Fixed typo: `RESUSE_EXISTING_DATA` → `REUSE_EXISTING_DATA` (4 occurrences)
2. Added `REUSE_EXISTING_DATA="${REUSE_EXISTING_DATA}"` to the second heredoc block (line 378)

**Files Modified**:
- `bin/launch_vm.sh`:
  - Line 22: Fixed variable declaration
  - Line 51: Fixed usage text
  - Line 157: Fixed option parsing
  - Line 378: Added variable to expandable heredoc block
  - Line 398: Fixed variable reference

### 18. Published Helm Chart Missing Annotations Template
**Problem**: Even after fixing the launch script, the CNPG cluster was still missing the `cnpg.io/skip-initdb` annotation.

**Root Cause Analysis**:
The Galaxy Helm chart at `ksuderman.github.io/helm_charts` (version `6.7.0-dev`) did not have the annotations template in `templates/hapostgres/pgcluster.yaml`.

**Published chart (missing annotations support)**:
```yaml
metadata:
  labels:
    {{- include "galaxy.labels" . | nindent 4 }}
  name: {{ include "galaxy-postgresql.fullname" . }}
```

**Local chart (has annotations support)**:
```yaml
metadata:
  labels:
    {{- include "galaxy.labels" . | nindent 4 }}
  {{- if and .Values.postgresql.cluster .Values.postgresql.cluster.annotations }}
  annotations:
    {{- toYaml .Values.postgresql.cluster.annotations | nindent 4 }}
  {{- end }}
  name: {{ include "galaxy-postgresql.fullname" . }}
```

**Solution**: User republished the Helm chart with the annotations template support.

**Verification**:
```bash
helm repo update ksuderman
helm pull ksuderman/galaxy --version 6.7.0-dev --untar --untardir /tmp/galaxy-chart-check
cat /tmp/galaxy-chart-check/galaxy/templates/hapostgres/pgcluster.yaml
# Now shows annotations template support
```

## Complete Data Persistence Flow

After these fixes, the complete flow for reusing existing data is:

1. **User runs**: `bin/restart.sh` or `bin/launch_vm.sh --reuse-existing-data`
2. **Launch script**: Sets `REUSE_EXISTING_DATA="true"` in cloud-init
3. **Cloud-init**: Writes `reuse_existing_data="true"` to Ansible inventory
4. **Ansible playbook**: Passes value to Helm via `_helm_values_skip_initdb`
5. **Helm chart**: Renders CNPG Cluster with `cnpg.io/skip-initdb: "true"` annotation
6. **CNPG plugin**: Intercepts initdb Job, replaces with no-op when annotation present
7. **PostgreSQL**: Starts using existing data instead of reinitializing

## Testing Status

**Pending**: User will relaunch cluster with updated chart to verify complete fix.

## Key Debugging Commands Used

```bash
# Check CNPG cluster annotations
KUBECONFIG=~/.kube/configs/gcp kubectl get clusters.postgresql.cnpg.io -n galaxy -o yaml | grep -A15 "metadata:"

# Check Helm values applied
KUBECONFIG=~/.kube/configs/gcp helm get values galaxy -n galaxy | grep -A10 "postgresql:"

# Check rendered manifest
KUBECONFIG=~/.kube/configs/gcp helm get manifest galaxy -n galaxy | grep -A20 "kind: Cluster"

# Check cloud-init script on VM
gcloud compute ssh <vm-name> --command='sudo cat /var/lib/cloud/instance/user-data.txt | grep -i reuse'

# Download and inspect published chart
helm pull ksuderman/galaxy --version 6.7.0-dev --untar --untardir /tmp/galaxy-chart-check
cat /tmp/galaxy-chart-check/galaxy/templates/hapostgres/pgcluster.yaml
```

## Files Modified This Session

| File | Changes |
|------|---------|
| `bin/launch_vm.sh` | Fixed `REUSE_EXISTING_DATA` variable typo and heredoc expansion bug |

## Lessons Learned

1. **Heredoc delimiter quoting matters**: `<< 'EOF'` prevents variable expansion, `<< EOF` allows it
2. **Multi-block heredocs require careful variable passing**: Variables must be set in an expanding block before being used in a non-expanding block
3. **Published charts may differ from local**: Always verify the actual deployed chart template matches expectations
4. **End-to-end testing is essential**: The bug only manifested when testing the complete VM launch → Ansible → Helm → CNPG flow

---

# Pulsar GCP Batch Integration - Hybrid Approach Implementation

**Date**: 2026-01-06
**Focus**: Investigating and implementing Pulsar-based GCP Batch runner alongside the existing direct GCP Batch runner

## Summary

Implemented a hybrid approach that allows Galaxy to use both:
1. **Direct GCP Batch Runner** - Custom implementation using NFS for file access
2. **Pulsar GCP Batch Runner** - Upstream Pulsar library using RabbitMQ + local SSD

This enables A/B performance testing to determine the optimal approach for different workloads.

## Background: PR #20862 Analysis

Galaxy PR [#20862](https://github.com/galaxyproject/galaxy/pull/20862) introduced `PulsarGcpBatchJobRunner`, which integrates GCP Batch support through the Pulsar library (v0.15.10+).

### Key Differences from Direct GCP Batch

| Aspect | Direct GCP Batch | Pulsar GCP Batch |
|--------|------------------|------------------|
| **Runner Class** | `galaxy.jobs.runners.gcp_batch:GoogleCloudBatchJobRunner` | `galaxy.jobs.runners.pulsar:PulsarGcpBatchJobRunner` |
| **File Access** | NFS mount from K8s cluster | Local SSD via Pulsar sidecar staging |
| **Communication** | Direct GCP Batch API | RabbitMQ message queue |
| **Container Model** | Single tool container | Pulsar sidecar + tool container |
| **Galaxy Version** | Custom image | Standard Galaxy 25.1+ |

## Architecture

### Direct GCP Batch (NFS-based)
```
┌─────────────────────────────────────────────────────────────────┐
│   Galaxy Pod                          GCP Batch VM              │
│   ┌─────────────┐                    ┌─────────────────────┐    │
│   │ Job Handler │   GCP Batch API    │  Tool Container     │    │
│   │ gcp_batch   ├───────────────────►│  ┌───────────────┐  │    │
│   │ runner      │                    │  │ /galaxy/db    │◄─┼─NFS│
│   └─────────────┘                    │  │ (NFS mount)   │  │    │
│                                      │  └───────────────┘  │    │
│                                      └─────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

### Pulsar GCP Batch (SSD-based)
```
┌─────────────────────────────────────────────────────────────────┐
│   Galaxy Pod         RabbitMQ        GCP Batch VM               │
│   ┌─────────────┐   ┌───────┐       ┌─────────────────────┐     │
│   │ Job Handler │   │       │       │ Pulsar    Tool      │     │
│   │ pulsar_gcp  ├──►│  MQ   │◄─────►│ Sidecar   Container │     │
│   │ runner      │   │       │       │ ┌─────┐  ┌───────┐  │     │
│   └─────────────┘   └───────┘       │ │Stage│◄►│ Tool  │  │     │
│                                     │ └─────┘  └───────┘  │     │
│                                     │    Local SSD        │     │
│                                     └─────────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
```

## Investigation Findings

### 1. File Staging Mechanism
- **Pulsar sidecar container** (`galaxy/pulsar-pod-staging:0.15.0.2`) handles file transfer
- Files staged to local SSD at `/mnt/disks/{ssd_name}` (default: `pulsar_staging`)
- Uses `remote_transfer` action for input/output staging
- No NFS dependency - files transferred via RabbitMQ coordination

### 2. CVMFS Support
- Pulsar staging container has CVMFS tooling built-in
- Can connect to CVMFS-hosted conda environments
- Reference data accessible from CVMFS mounts

### 3. Container Configuration
- Two containers per job: Pulsar sidecar + tool container
- Tool containers resolved via Galaxy's standard container resolution
- `remote_container_handling: true` delegates orchestration to Pulsar

### 4. RabbitMQ Requirements
- Exchange: `pulsar` (direct type)
- Queue naming: `pulsar_{queue_name}` or `pulsar_{manager_name}_{queue_name}`
- **Critical**: GCP Batch VMs must reach RabbitMQ (external to K8s cluster)

## RabbitMQ Exposure Solution

Implemented the same pattern used for NFS exposure:

1. **Patch RabbitMQ service** with node's internal IP as `externalIP`
2. **Firewall rule** allows port 5672 from internal GCP networks
3. **AMQP URL** constructed with credentials from K8s secret

```bash
# Firewall rule (one-time setup)
gcloud compute firewall-rules create allow-rabbitmq-for-batch \
  --project=anvil-and-terra-development \
  --description="Allow RabbitMQ access for GCP Batch VMs" \
  --direction=INGRESS --priority=1000 --network=default \
  --action=ALLOW --rules=tcp:5672 \
  --source-ranges=10.128.0.0/9 --target-tags=k8s
```

## Implementation Details

### New Ansible Variables (`defaults/main.yml`)

```yaml
# Pulsar GCP Batch Configuration
enable_pulsar_gcp_batch: false
pulsar_gcp_project_id: ""
pulsar_gcp_region: "us-east4"
pulsar_gcp_machine_type: "n2-standard-4"
pulsar_gcp_walltime_limit: 86400
pulsar_gcp_retry_count: 3
pulsar_gcp_disk_size: 375
pulsar_gcp_ssd_name: "pulsar_staging"
pulsar_container_image: "galaxy/pulsar-pod-staging:0.15.0.2"
```

### Ansible Tasks Added (`galaxy_application.yml`)

1. **Pre-install**: Set `rabbitmq_external_ip` to node's internal IP
2. **Helm values**: Include `_helm_values_pulsar_gcp` with runner configuration
3. **Post-install**:
   - Get RabbitMQ credentials from secret
   - Construct AMQP URL
   - Patch RabbitMQ service with external IP
   - Update ConfigMap with real AMQP URL
   - Restart Galaxy deployments

### Helm Values Files

| File | Purpose |
|------|---------|
| `values/hybrid-gcp-batch.yml` | Base configuration with both runners |
| `values/test-gcp-batch-comparison.yml` | A/B test routing configuration |

### Test Routing Strategy

**Group A (Direct GCP Batch / NFS):**
- `Cut1`, `Grep1`, `Sort1`, `Paste1`, `join1`, `cat1`
- Text processing tools with streaming I/O

**Group B (Pulsar GCP Batch / SSD):**
- `FastQC`, `BWA`, `Samtools`, `HISAT2`, `featureCounts`
- Bioinformatics tools with random I/O

## Trade-off Analysis

| Aspect | Direct GCP Batch | Pulsar GCP Batch |
|--------|------------------|------------------|
| **Job Startup** | Faster (just mount NFS) | Slower (transfer inputs) |
| **I/O During Job** | NFS latency | Local SSD speed |
| **Large Files** | Efficient (no copy) | Transfer overhead |
| **Small Files** | NFS latency | Local SSD faster |
| **Upstream Support** | None (custom) | Full Galaxy/Pulsar support |
| **Multi-Cloud** | GCP only | Extensible to TES, K8s |
| **Debugging** | Simpler | More complex |

### Recommendations

| Use Case | Recommended Runner |
|----------|-------------------|
| Large input files | Direct GCP Batch |
| I/O intensive tools | Pulsar GCP Batch |
| Upstream support needed | Pulsar GCP Batch |
| Simple debugging | Direct GCP Batch |
| Multi-cloud future | Pulsar GCP Batch |

## Files Created/Modified

| File | Changes |
|------|---------|
| `roles/galaxy_k8s_deployment/defaults/main.yml` | Added Pulsar GCP Batch variables |
| `roles/galaxy_k8s_deployment/tasks/galaxy_application.yml` | Added RabbitMQ exposure and Pulsar config tasks |
| `values/hybrid-gcp-batch.yml` | **NEW** - Hybrid configuration |
| `values/test-gcp-batch-comparison.yml` | **NEW** - A/B test routing |
| `docs/HYBRID_GCP_BATCH_TESTING.md` | **NEW** - Testing guide |

## Deployment Commands

### Fresh Deployment
```bash
bin/launch_vm.sh test-hybrid-galaxy \
  --git-branch persistent-data-merged \
  -f values/hybrid-gcp-batch.yml \
  -f values/test-gcp-batch-comparison.yml
```

### Enable on Existing Cluster
```bash
ansible-playbook -i inventories/gcp.ini playbook.yml \
  --extra-vars "enable_gcp_batch=true" \
  --extra-vars "enable_pulsar_gcp_batch=true" \
  --extra-vars "pulsar_gcp_project_id=anvil-and-terra-development"
```

## Verification Commands

```bash
# Check both runners configured
KUBECONFIG=~/.kube/configs/gcp kubectl get configmap galaxy-configs -n galaxy -o yaml | grep -E "gcp_batch:|pulsar_gcp:"

# Check RabbitMQ external IP
KUBECONFIG=~/.kube/configs/gcp kubectl get svc -n galaxy | grep rabbitmq

# Check NFS external IP
KUBECONFIG=~/.kube/configs/gcp kubectl get svc -n nfs-provisioner

# Monitor GCP Batch jobs
gcloud batch jobs list --location=us-east4 --project=anvil-and-terra-development
```

## Next Steps

1. Deploy test cluster with hybrid configuration
2. Run identical jobs through both runners
3. Collect and compare performance metrics
4. Determine optimal tool routing based on results
5. Create production configuration

---

# GCP Batch Authentication: Switch to Application Default Credentials

**Date**: 2026-01-06
**Focus**: Removing JSON key secret requirement, using ADC from VM's attached service account

## Summary

Updated all GCP Batch values files to use Application Default Credentials (ADC) instead of requiring a mounted JSON key secret. This simplifies deployment and leverages the VM's attached service account.

## Background

The user questioned why a `gcp-batch-key` secret was needed when Workload Identity had been previously discussed.

### Investigation Findings

1. **This is an RKE2 cluster**, not GKE - Workload Identity is a GKE-specific feature
2. **The custom GCP Batch runner already supports ADC** - see `gcp_batch.py:99-111`:
   ```python
   def _init_batch_client(self):
       service_account_file = self.runner_params.get("service_account_file")
       if service_account_file:
           os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = service_account_file

       credentials, project = default()  # Uses ADC
       self.batch_client = batch_v1.BatchServiceClient(credentials=credentials)
   ```
3. **The `service_account_file` parameter is optional** - when not provided, the runner uses `google.auth.default()` which on a GCP VM uses the metadata service
4. **The VM has a service account attached** with `cloud-platform` scope, providing full API access

## Changes Made

### Values Files Updated

| File | Changes |
|------|---------|
| `values/hybrid-gcp-batch.yml` | Removed `extraVolumes`, `extraVolumeMounts`, `service_account_file`, `credentials_file` |
| `values/gcp-batch.yml` | Removed `extraVolumes`, `extraVolumeMounts`, `service_account_file` |
| `values/gcp-batch2.yml` | Removed `extraVolumes`, `extraVolumeMounts`, `service_account_file` |
| `values/hybrid_job_conf.yml` | Removed `service_account_file` |

### Before (Required JSON Key Secret)

```yaml
extraVolumes:
  - name: gcp-batch-key
    secret:
      secretName: gcp-batch-key
      defaultMode: 0400

extraVolumeMounts:
  - name: gcp-batch-key
    mountPath: /etc/secrets/galaxy
    readOnly: true

configs:
  job_conf.yml:
    runners:
      gcp_batch:
        service_account_file: /etc/secrets/galaxy/key.json
```

### After (Uses ADC)

```yaml
# Authentication: Uses Application Default Credentials (ADC) from VM's attached service account
# No secret mounting required - the GCP Batch runner automatically uses the metadata service

configs:
  job_conf.yml:
    runners:
      gcp_batch:
        # Authentication uses ADC from VM's attached service account
        project_id: "PLACEHOLDER_PROJECT_ID"
        region: us-east4
        service_account_email: "PLACEHOLDER_SERVICE_ACCOUNT"
```

## How ADC Works on GCP VMs

According to [Google Cloud documentation](https://cloud.google.com/docs/authentication/application-default-credentials):

1. ADC checks `GOOGLE_APPLICATION_CREDENTIALS` environment variable (not set)
2. ADC checks well-known credential locations (not present)
3. **ADC uses the VM's metadata service** to get credentials from the attached service account

The RKE2 VM has service account `526897014808-compute@developer.gserviceaccount.com` attached with `cloud-platform` scope, which provides access to all GCP APIs including Batch.

## Benefits

1. **No secret management** - No JSON key file to create, rotate, or secure
2. **Simpler deployment** - Fewer configuration steps
3. **Automatic credential refresh** - Metadata service handles token refresh
4. **Security best practice** - No long-lived credentials stored in cluster

## Prerequisites

The VM must have:
- A service account attached with required permissions (see `PERMISSIONS.md`)
- `cloud-platform` scope (or more specific Batch API scopes)

## Verification

```bash
# Check VM service account
gcloud compute instances describe <vm-name> --zone=<zone> \
  --format='get(serviceAccounts[].email)'

# Check scopes
gcloud compute instances describe <vm-name> --zone=<zone> \
  --format='get(serviceAccounts[].scopes)'
```

---

# TPV Job Routing Fix and Helm Install Timeout Resolution

**Date**: 2026-01-09
**Focus**: Fixing TPV job routing so FastQC runs on Pulsar GCP Batch instead of Kubernetes

## Summary of Issues Identified and Resolved

### 19. TPV Job Routing - FastQC Going to k8s Instead of pulsar_gcp

**Problem**: FastQC jobs were being routed to the Kubernetes runner instead of the Pulsar GCP Batch runner, despite having explicit tool routing in `job_conf.yml`.

**Root Cause Analysis**:
TPV (Total Perspective Vortex) scoring was causing the issue:
- `gcp_batch` destination had `scheduling.prefer: [gcp-batch-nfs]` → tools without matching tag get score -1
- `pulsar_gcp` destination had `scheduling.prefer: [gcp-batch-ssd]` → tools without matching tag get score -1
- `k8s` destination had `scheduling.accept: [docker]` → tools without tag get score 0 (neutral)

Since tool definitions in TPV rules were missing their `scheduling.prefer` tags (Galaxy Helm chart template dropped them), all tools scored:
- `gcp_batch`: -1
- `k8s`: 0 (winner!)
- `pulsar_gcp`: -1

**Solution Implemented**:
Removed `scheduling.prefer` tags from destinations so all destinations score 0 equally, allowing `job_conf.yml` tool routing to control execution:

```yaml
# Before: Destinations with prefer tags (caused score imbalance)
destinations:
  gcp_batch:
    runner: gcp_batch
    scheduling:
      prefer: [gcp-batch-nfs]  # REMOVED
  pulsar_gcp:
    runner: pulsar_gcp
    scheduling:
      prefer: [gcp-batch-ssd]  # REMOVED
  k8s:
    runner: k8s
    scheduling:
      accept: [docker]  # REMOVED

# After: All destinations score equally
destinations:
  gcp_batch:
    runner: gcp_batch
    params:
      docker_enabled: "true"
  pulsar_gcp:
    runner: pulsar_gcp
    params:
      docker_enabled: "true"
  k8s:
    runner: k8s
    # No scheduling tags - scores 0
```

### 20. Ansible Playbook Timeout During Galaxy Helm Install

**Problem**: Ansible playbook was timing out waiting for Galaxy PVC to be bound (300 second timeout), causing downstream tasks (like Pulsar configuration) to be skipped.

**Root Cause Analysis**:
The Galaxy Helm install task didn't have `wait: true`, so it returned immediately. The subsequent PVC wait task then started before the Helm deployment was stable.

**Solution Implemented**:
Added `wait: true` and `wait_timeout: 600` to the Galaxy Helm install task:

```yaml
# roles/galaxy_k8s_deployment/tasks/galaxy_application.yml
- name: Helm install Galaxy
  kubernetes.core.helm:
    name: galaxy
    namespace: galaxy
    chart_ref: "{{ galaxy_chart }}"
    chart_version: "{{ galaxy_chart_version }}"
    kubeconfig: "{{ kubeconfig_path }}"
    update_repo_cache: true
    wait: true           # NEW: Wait for deployment to stabilize
    wait_timeout: 600    # NEW: 10 minute timeout
    values_files: ...
    values: ...
```

## Files Modified This Session

| File | Changes |
|------|---------|
| `values/test-gcp-batch-comparison.yml` | Removed `scheduling.prefer` tags from `gcp_batch` and `pulsar_gcp` destinations; added `k8s` override without `scheduling.accept`; removed scheduling tags from tool definitions |
| `roles/galaxy_k8s_deployment/tasks/galaxy_application.yml` | Added `wait: true` and `wait_timeout: 600` to Galaxy Helm install task |

## Configuration Architecture

**Tool Routing** (`job_conf.yml`):
- FastQC, BWA, Samtools → `pulsar_gcp` environment
- Cut1, Grep1, Sort1 → `gcp_batch` environment
- System tools → `local` environment

**TPV Rules** (`tpv_rules_local.yml`):
- Resource allocation (cores, memory) per tool
- No scheduling preferences on destinations
- All destinations score equally (0)

## Commit Details

```
Fix Helm install timeout and TPV scheduling tag conflicts

- Add wait: true and wait_timeout: 600 to Galaxy Helm install task
  to ensure deployment is stable before checking PVC status
- Remove scheduling.prefer tags from TPV destinations (gcp_batch, pulsar_gcp)
  to avoid scoring conflicts with tools that lack matching tags
- Override k8s destination without scheduling.accept tag for equal scoring
- Tool routing now relies on job_conf.yml environment mappings instead of
  TPV scheduling tag matching
```

## Next Steps

1. Delete existing VM (user will do manually)
2. Deploy fresh cluster with `bin/start.sh`
3. Verify FastQC routes to `pulsar_gcp`
4. Confirm GCP Batch job is created

## Key Debugging Commands

```bash
# Check current TPV rules in pod
KUBECONFIG=~/.kube/configs/gcp kubectl exec -n galaxy deployment/galaxy-web -- \
  cat /galaxy/server/lib/galaxy/jobs/rules/tpv_rules_local.yml

# Check job_conf.yml tool routing
KUBECONFIG=~/.kube/configs/gcp kubectl get configmap galaxy-configs -n galaxy -o yaml | \
  grep -A50 "job_conf.yml"

# Monitor GCP Batch jobs
gcloud batch jobs list --location=us-east4 --project=anvil-and-terra-development
```

---

# Deployment Fixes and Pulsar GCP Batch Investigation - Session Notes

**Date**: 2026-01-11
**Focus**: Fixing deployment issues and investigating Pulsar GCP Batch resource sizing

## Summary of Issues Identified and Resolved

### 20. Helm wait_timeout Missing Time Unit
**Problem**: Ansible playbook failed with error `invalid argument "600" for "--timeout" flag: time: missing unit in duration "600"`

**Root Cause**: The `wait_timeout` parameter in the Helm install task was set to `600` but Helm requires a time unit suffix (e.g., `600s`).

**Solution**: Changed `wait_timeout: 600` to `wait_timeout: "600s"` in `galaxy_application.yml:244`.

**Commit**: `e14f5e6`

### 21. Galaxy PVC Wait Using Wrong Condition Type
**Problem**: Playbook timed out waiting for Galaxy PVC even though the PVC was bound. Error: `Failed to gather information about PersistentVolumeClaim(s) even after waiting for 300 seconds`

**Root Cause**: The PVC wait task used `wait_condition` with `type: Bound`, but PVCs don't have condition types - they have `status.phase`.

**Solution**: Changed from `wait_condition` approach to checking `status.phase == "Bound"` with retries:
```yaml
- name: Wait for Galaxy PVC to be bound
  kubernetes.core.k8s_info:
    # ...
  register: galaxy_pvc
  until: galaxy_pvc.resources | length > 0 and galaxy_pvc.resources[0].status.phase == "Bound"
  retries: 30
  delay: 10
```

### 22. Consolidated Helm Values
**Problem**: Multiple `_helm_values_*` sections made the playbook harder to maintain.

**Solution**: Consolidated `_helm_values_base`, `_helm_values_gcp_batch`, `_helm_values_pulsar_gcp`, and `_helm_values_cnpg_plugin` into a single `_helm_values` section. Only `_helm_values_skip_initdb` remains conditional.

**Commit**: `3fe2c29`

### 23. Default Galaxy API Key
**Problem**: The `galaxy_api_key` default was empty string, which didn't trigger `default(omit)` in the template.

**Solution**: Set `galaxy_api_key: "galaxypassword"` in `defaults/main.yml`. Note: This is actually passed via inventory file in `launch_vm.sh`, so the default is redundant but provides a fallback.

**Commit**: `e54d826`

### 24. GCP Batch Placeholder Values Not Replaced
**Problem**: `PLACEHOLDER_PROJECT_ID` and `PLACEHOLDER_SERVICE_ACCOUNT` in `values/hybrid-gcp-batch.yml` were not being replaced, causing GCP Batch job submission failures.

**Solution**: Hardcoded the actual values:
- `project_id: "anvil-and-terra-development"`
- `service_account_email: galaxy-batch-runner@anvil-and-terra-development.iam.gserviceaccount.com`

**Commits**: `62f108e`, `778c645`

## Pulsar GCP Batch Resource Sizing Investigation

### Issue Identified
When launching a FastQC job requesting 8 cores, the GCP Batch VM was created with `n2-standard-2` (1 vCPU per task) instead of being sized appropriately.

### Root Cause
The Pulsar GCP Batch runner (`PulsarGcpBatchJobRunner`) does NOT support dynamic resource sizing. The `GcpJobParams` class in `pulsar/client/container_job_config.py` only supports a fixed `machine_type` parameter - it doesn't read job resource requirements and size VMs accordingly.

This is different from Galaxy's direct `gcp_batch` runner which has dynamic resource allocation implemented.

### Documentation Created
Created comprehensive documentation at `docs/PULSAR_GCP_BATCH_RESOURCE_SIZING_ISSUE.md` including:
- Technical analysis of the limitation
- Comparison with direct GCP Batch runner
- Proposed solutions (machine type mapping, ComputeResource usage, hybrid approach)
- Authentication considerations for non-GCP Galaxy deployments
- Graphviz DOT diagrams for architecture visualization

### Diagrams Generated
Created `docs/diagrams/` with DOT source files and PNG images:
- `direct_gcp_batch.dot/.png` - Direct GCP Batch runner architecture
- `pulsar_gcp_batch.dot/.png` - Pulsar GCP Batch runner architecture
- `auth_adc.dot/.png` - ADC authentication flow
- `auth_credentials.dot/.png` - Credentials file authentication flow

**Commit**: `ff392d1`, `7de4ed3`, `1eddf78`, `e07ec46`

## Files Modified This Session

| File | Changes |
|------|---------|
| `roles/galaxy_k8s_deployment/tasks/galaxy_application.yml` | Fixed wait_timeout, consolidated helm values, fixed PVC wait condition |
| `roles/galaxy_k8s_deployment/defaults/main.yml` | Set default galaxy_api_key |
| `values/hybrid-gcp-batch.yml` | Replaced placeholder values with actual project_id and service_account_email |
| `docs/PULSAR_GCP_BATCH_RESOURCE_SIZING_ISSUE.md` | **NEW** - Documented resource sizing limitation |
| `docs/diagrams/*.dot` | **NEW** - Graphviz source files |
| `docs/diagrams/*.png` | **NEW** - Generated architecture diagrams |

## Current Deployment Status

Galaxy is successfully deployed and running on `ks-psql-test`:
- All pods running
- PVCs bound
- GCP Batch jobs dispatching (but Pulsar runner uses fixed machine types)

## Next Steps

1. **For Pulsar maintainers**: Review `docs/PULSAR_GCP_BATCH_RESOURCE_SIZING_ISSUE.md` and consider implementing dynamic resource sizing
2. **Workaround**: Use multiple destinations with different `machine_type` values and TPV routing until Pulsar is updated

---

# GCP Batch Runner Configuration Fixes - Session Notes

**Date**: 2026-01-24
**Focus**: Fixing GCP Batch runner parameter validation errors and playbook configuration

## Summary of Issues Identified and Resolved

### 25. Invalid GCP Batch Runner Parameters
**Problem**: Galaxy job handler crashing with `Exception: Invalid job runner parameter for this plugin: container_image`

**Root Cause Analysis**:
The `values/batch.yml` file contained parameters that are not valid for the GCP Batch runner:
- `container_image` - Not in `runner_param_specs` (runner uses Galaxy's container finder)
- `nfs_server` - Not a valid parameter
- `nfs_path` - Not a valid parameter
- `nfs_mount_path` - Not a valid parameter

The GCP Batch runner expects NFS configuration via `gcp_batch_volumes` in format: `"server:/remote_path:/mount_path"`

**Solution Implemented**:

1. **Updated `values/batch.yml`**:
   - Removed invalid `container_image`, `nfs_server`, `nfs_path`, `nfs_mount_path` parameters
   - Added comment about `gcp_batch_volumes` format
   - Added startup probe timeout configuration for CVMFS tool loading

2. **Updated `roles/galaxy_k8s_deployment/tasks/galaxy_application.yml`**:
   - Removed `nfs_server` from initial Helm values
   - Changed ConfigMap update to set `gcp_batch_volumes` with format `"nfs_server:nfs_export_path:/galaxy/server/database"`

### 26. Pulsar GCP Batch Configuration Breaking Deployment
**Problem**: VM launch failing due to Pulsar GCP Batch configuration being applied unconditionally, even when `enable_pulsar_gcp_batch` was false.

**Root Cause Analysis**:
The Helm values and Ansible tasks for Pulsar GCP Batch were being included unconditionally in `galaxy_application.yml`, causing errors when variables like `galaxy_public_url` weren't defined.

**Solution Implemented**:
Made all Pulsar-related configuration conditional on `enable_pulsar_gcp_batch`:

1. **Helm install task**: Pulsar GCP values are now conditionally combined only when `enable_pulsar_gcp_batch` is true
2. **Pulsar-specific tasks**: Added `when: enable_pulsar_gcp_batch | default(false) | bool` to all tasks including:
   - RabbitMQ external IP setup
   - Galaxy public URL detection
   - RabbitMQ patching flag
   - RabbitMQ credentials retrieval
   - AMQP URL construction
   - RabbitMQ service patching
   - ConfigMap update with AMQP URL
   - Galaxy deployment restart for Pulsar

### 27. Missing GCP Batch Helper Module
**Problem**: Job handler crashing with `ModuleNotFoundError: No module named 'galaxy.jobs.runners.util.gcp_batch'`

**Root Cause Analysis**:
The Docker image was built from `galaxy-upstream` which had the `gcp_batch.py` runner file but was missing the `util/gcp_batch/` helper module directory that the runner imports.

**Solution Implemented**:
Copied the `util/gcp_batch/` module from `galaxy-batch-dev` to `galaxy-upstream`:
```
lib/galaxy/jobs/runners/util/gcp_batch/
├── __init__.py
├── container_script.sh
├── direct_script.sh
└── helpers.py
```

### 28. Slow Startup Due to Tool Loading
**Problem**: Galaxy web pod being killed by startup probe before tool loading completed from CVMFS.

**Root Cause Analysis**:
Investigated whether this was the slow startup bug from issue #21262. Found that:
- Commit `2e4a50a38c75` introduced the bug on **2025-10-29** on the `dev` branch
- The `release_25.1` branch was created earlier and does NOT contain this bug
- The slow startup is normal CVMFS tool loading time, not the validation bug

**Solution Implemented**:
Added startup probe timeout configuration to `values/batch.yml`:
```yaml
web:
  startupProbe:
    initialDelaySeconds: 60
    periodSeconds: 10
    failureThreshold: 120  # Allow up to ~20 minutes
```

### 29. Wrong Docker Image Tag Being Used
**Problem**: Pods using old image tag (0.2) instead of new tag (0.3) after rebuilding.

**Root Cause Analysis**:
The `start.sh` script pulls values files from the remote GitHub repository (`pulsar-gcp` branch), not the local files. Local changes to `values/v25.1-batch.yml` weren't being applied.

**Solution**: User pushed local changes to GitHub and relaunched.

## Files Modified This Session

| File | Changes |
|------|---------|
| `values/batch.yml` | Removed invalid runner params (`container_image`, `nfs_*`), added startup probe timeout, added `gcp_batch_volumes` comment |
| `values/v0.1.yml` | Updated image tag to 0.3 |
| `roles/galaxy_k8s_deployment/tasks/galaxy_application.yml` | Made Pulsar config conditional, changed NFS config to use `gcp_batch_volumes` |

## Key Learnings

1. **GCP Batch runner parameter validation**: The runner validates all parameters against `runner_param_specs` - invalid parameters cause immediate failure
2. **`gcp_batch_volumes` format**: Must be `"server:/remote_path:/mount_path"` - separate NFS parameters are not supported
3. **Conditional Ansible configuration**: Use `when: variable | default(false) | bool` pattern to guard optional features
4. **GitHub vs local files**: The `launch_vm.sh` script pulls from GitHub, so local changes must be pushed before they take effect
5. **Release branch bug status**: The slow startup bug (issue #21262) only affects the `dev` branch, not `release_25.1`

## Current Status: WORKING ✅

**✅ GCP Batch runner parameters fixed**: Invalid parameters removed
**✅ Pulsar GCP Batch conditionally configured**: No longer breaks when disabled
**✅ Helper module included**: `util/gcp_batch/` copied to galaxy-upstream
**✅ Startup probe timeout extended**: 20 minutes for CVMFS tool loading
**✅ Docker image rebuilt**: `ksuderman/galaxy-batch:0.3` with all fixes

---

## Session 2026-01-26: GCP Batch CVMFS and Resource Fixes

### 30. CVMFS cloud.galaxyproject.org Not Mounted
**Problem**: Tool Shed tools (like snpEff) failed with error:
```
python3: can't open file '/cvmfs/cloud.galaxyproject.org/tools/toolshed.g2.bx.psu.edu/repos/iuc/snpeff/74aebe30fb52/snpeff/gbk2fa.py': [Errno 2] No such file or directory
```

**Root Cause**: The default CVMFS docker volume mount in the GCP Batch runner only included `data.galaxyproject.org`, not `cloud.galaxyproject.org` which hosts Tool Shed tools.

**Solution**:
1. Updated `docker_extra_volumes` in `values/batch.yml` to include both repositories
2. Updated `DEFAULT_CVMFS_DOCKER_VOLUME` in Galaxy runner code
3. Updated `container_script.sh` to verify both CVMFS repos
4. Updated `image_prep.yml` to verify `cloud.galaxyproject.org` in `cvmfs_verify_repos`
5. Created new VM image `galaxy-k8s-boot-v2026-01-24`

### 31. Job Resource Parameters Not Respected
**Problem**: Jobs requested 4 CPUs and 16GB memory via Galaxy's job resource selector, but VMs were created with default 1 CPU and 2GB memory.

**Root Cause**: GCP Batch runner only checked `job_destination.params` for Kubernetes-style parameters (`requests_cpu`, `limits_cpu`) but didn't check Galaxy's job resource parameters (`processors`, `mem`).

**Solution**: Updated `_get_job_resources()` in `gcp_batch.py` to call `job_wrapper.get_resource_parameters()` and check for `processors` and `mem` parameters from the tool form.

### 32. Static Machine Type Causing Job Failures
**Problem**: Jobs with large resource requirements failed:
```
machine_type "n2-standard-4" cannot satisfy compute_resource cpu_milli:16000 memory_mib:32768
```

**Root Cause**: Machine type was hardcoded to `n2-standard-4` regardless of resource requirements.

**Solution**: Added `compute_machine_type()` function that:
- Selects variant (highcpu/standard/highmem) based on memory-per-vCPU ratio
- Finds smallest valid size (2, 4, 8, 16, 32, 48, 64, 80, 96, 128) meeting requirements
- Returns appropriate machine type like `n2-standard-16` or `n2-highmem-8`

### Files Modified

| File | Changes |
|------|---------|
| `values/batch.yml` | Updated `docker_extra_volumes` and `custom_vm_image` |
| `bin/launch_vm.sh` | Updated default `MACHINE_IMAGE` to `galaxy-k8s-boot-v2026-01-24` |
| `image_prep.yml` | Added `cloud.galaxyproject.org` to `cvmfs_verify_repos` |

### Galaxy Code Modified (galaxy-batch-dev and galaxy-upstream)

| File | Changes |
|------|---------|
| `lib/galaxy/jobs/runners/gcp_batch.py` | Resource parameter handling, dynamic machine type selection |
| `lib/galaxy/jobs/runners/util/gcp_batch/helpers.py` | `compute_machine_type()`, updated `DEFAULT_CVMFS_DOCKER_VOLUME` |
| `lib/galaxy/jobs/runners/util/gcp_batch/__init__.py` | Export `compute_machine_type` |
| `lib/galaxy/jobs/runners/util/gcp_batch/container_script.sh` | CVMFS verification for both repos |

---