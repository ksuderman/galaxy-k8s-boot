# NFS Configuration for Galaxy on Kubernetes

This document covers the NFS setup, configuration, and troubleshooting for Galaxy deployments on Kubernetes, specifically focusing on integration with GCP Batch job runner.

## Overview

Galaxy requires shared storage for job data, uploads, and datasets. This setup uses NFS-Ganesha server provisioner with a LoadBalancer service to provide both internal cluster access and external access for GCP Batch VMs.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Galaxy Pods   │    │   NFS Server    │    │  GCP Batch VMs  │
│   (Internal)    │◄──►│  LoadBalancer   │◄──►│   (External)    │
│                 │    │   Service       │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                        ┌─────────────────┐
                        │  Persistent     │
                        │  Volume         │
                        │  (Block Store)  │
                        └─────────────────┘
```

## Configuration

### NFS Server Setup (`nfs.yml`)

The NFS server is deployed using the NFS-Ganesha Helm chart with specific configurations for file locking support:

```yaml
- name: Helm install Ganesha NFS
  kubernetes.core.helm:
    name: nfs-provisioner
    namespace: nfs-provisioner
    chart_ref: nfs-ganesha/nfs-server-provisioner
    chart_version: "{{ version }}"
    values:
      service:
        type: LoadBalancer
        # Expose all required NFS and locking ports
        ports:
          nfs: 2049
          mountd: 20048
          rpcbind: 111
          nlm: 32765
        # Ensure session affinity for locking
        sessionAffinity: ClientIP
        sessionAffinityConfig:
          clientIP:
            timeoutSeconds: 10800
      mountOptions:
        - nfsvers=4.1
        - vers=4.1
        - hard
        - intr
        - rsize=1048576
        - wsize=1048576
        - timeo=600
        - retrans=2
        - locks         # Enable NFS locking
        - local_lock=all # Use all locking mechanisms
      # Enable NFS locking services
      env:
        - name: ENABLE_NFS_V4
          value: "yes"
        - name: ENABLE_NLM
          value: "yes"
        - name: GRACE_PERIOD
          value: "90"
      # Additional container settings for locking
      securityContext:
        privileged: true
        capabilities:
          add:
            - SYS_ADMIN
            - DAC_READ_SEARCH
      persistence:
        enabled: true
        storageClass: "{{ persistence_storage_class }}"
        size: "{{ size }}"
```

### Key Configuration Elements

#### **1. Service Type: LoadBalancer**
- **Purpose**: Provides external IP for GCP Batch VM access
- **Alternative**: ClusterIP only works for internal cluster access
- **Requirement**: GCP Batch VMs are external and need external access

#### **2. Port Configuration**
- **2049**: Main NFS service port
- **20048**: mountd (mount daemon)
- **111**: rpcbind (portmapper)
- **32765**: NLM (Network Lock Manager)

#### **3. Session Affinity**
- **ClientIP**: Ensures requests from the same client go to the same pod
- **Timeout**: 10800 seconds (3 hours) for long-running jobs
- **Purpose**: Maintains NFS locking state consistency

#### **4. Mount Options**
- **locks**: Enable NFS file locking
- **local_lock=all**: Use all available locking mechanisms
- **nfsvers=4.1**: Modern NFS version with better locking support
- **hard**: Retry NFS operations indefinitely
- **intr**: Allow interruption of NFS operations

#### **5. Environment Variables**
- **ENABLE_NFS_V4**: Enable NFSv4 support
- **ENABLE_NLM**: Enable Network Lock Manager
- **GRACE_PERIOD**: Lock recovery period (90 seconds)

#### **6. Security Context**
- **privileged: true**: Required for NFS server operations
- **SYS_ADMIN**: Administrative capabilities
- **DAC_READ_SEARCH**: File access capabilities

## Deployment

### 1. Deploy NFS Server
```bash
cd /Users/suderman/Workspaces/JHU/galaxy-k8s-boot
ansible-playbook -i inventories/localhost nfs.yml
```

### 2. Get NFS Server IP
```bash
# Get LoadBalancer external IP
kubectl get svc -n nfs-provisioner
# Look for EXTERNAL-IP of nfs-provisioner service
```

### 3. Update Galaxy Configuration
Update `values/nfs.yml` with the actual NFS server IP:
```yaml
configs:
  job_conf.yml:
    runners:
      gcp_batch:
        nfs_server: <LOADBALANCER_EXTERNAL_IP>
```

### 4. Restart Galaxy
```bash
kubectl rollout restart deployment/galaxy-web -n galaxy-ns
kubectl rollout restart deployment/galaxy-job-handlers -n galaxy-ns
```

## Troubleshooting

### Common Error: "No locks available"

This error typically occurs when NFS file locking is not properly configured or accessible.

#### **Symptoms**
- Galaxy upload failures
- "No locks available" error in Galaxy logs
- File operation timeouts

#### **Debugging Steps**

1. **Check NFS mount options in Galaxy pods**:
   ```bash
   kubectl exec -it deployment/galaxy-web -n galaxy-ns -- mount | grep nfs
   ```

2. **Test file locking directly**:
   ```bash
   kubectl exec -it deployment/galaxy-web -n galaxy-ns -- bash
   # Inside pod:
   flock /galaxy/server/database/test.lock echo "Lock test successful"
   ```

3. **Check NFS server status**:
   ```bash
   kubectl get pods -n nfs-provisioner
   kubectl logs -n nfs-provisioner deployment/nfs-provisioner
   ```

4. **Verify all ports are exposed**:
   ```bash
   kubectl get svc -n nfs-provisioner -o yaml
   # Ensure ports 2049, 20048, 111, 32765 are listed
   ```

#### **Common Causes and Solutions**

| **Cause** | **Solution** |
|-----------|-------------|
| Missing NFS locking ports | Add ports 111, 32765 to LoadBalancer service |
| No session affinity | Add `sessionAffinity: ClientIP` to service |
| NFSv3 instead of NFSv4 | Ensure `nfsvers=4.1` in mount options |
| Missing lock manager | Set `ENABLE_NLM=yes` environment variable |
| Insufficient privileges | Use `privileged: true` security context |
| Wrong mount options | Include `locks` and `local_lock=all` |

### Network Connectivity Issues

#### **GCP Batch Cannot Access NFS**

**Problem**: GCP Batch VMs cannot mount NFS volumes

**Debug**:
```bash
# From GCP Batch VM (if accessible):
telnet <NFS_EXTERNAL_IP> 2049
showmount -e <NFS_EXTERNAL_IP>
```

**Solutions**:
1. Verify LoadBalancer external IP is accessible
2. Check GCP firewall rules allow NFS ports
3. Ensure VPC/subnet configuration allows access

#### **Service Type Considerations**

| **Service Type** | **Galaxy Access** | **GCP Batch Access** | **Use Case** |
|------------------|-------------------|---------------------|--------------|
| **LoadBalancer** | ✅ Yes | ✅ Yes | Recommended for GCP Batch |
| **ClusterIP** | ✅ Yes | ❌ No | Internal only |
| **NodePort** | ✅ Yes | ✅ Yes (via Node IP) | Alternative to LoadBalancer |

### Performance Tuning

#### **Mount Options for Performance**
```yaml
mountOptions:
  - nfsvers=4.1          # Modern NFS version
  - hard                 # Reliable operations
  - intr                 # Interruptible
  - rsize=1048576        # 1MB read size
  - wsize=1048576        # 1MB write size
  - timeo=600            # 60 second timeout
  - retrans=2            # 2 retries
  - locks                # Enable locking
  - local_lock=all       # All lock types
```

#### **Monitoring NFS Performance**
```bash
# Check NFS stats in Galaxy pods
kubectl exec -it deployment/galaxy-web -n galaxy-ns -- cat /proc/self/mountstats

# Monitor NFS server logs
kubectl logs -f -n nfs-provisioner deployment/nfs-provisioner
```

## Security Considerations

### **Service Account Permissions**
The NFS server requires elevated privileges:
- `privileged: true` - Required for NFS operations
- `SYS_ADMIN` capability - Administrative operations
- `DAC_READ_SEARCH` capability - File access operations

### **Network Security**
- **Firewall rules**: Ensure only necessary traffic can reach NFS ports
- **VPC isolation**: Use private networks where possible
- **Access control**: Consider implementing NFS export restrictions

### **Data Security**
- **Encryption in transit**: Consider NFS with Kerberos or TLS
- **Encryption at rest**: Use encrypted persistent volumes
- **Backup strategy**: Regular backups of NFS data

## Integration with GCP Batch

### **Configuration Requirements**
The GCP Batch job runner requires:
1. **External access** to NFS server (LoadBalancer required)
2. **Network connectivity** from Batch VMs to NFS LoadBalancer
3. **Proper mount options** including locking support

### **Job Configuration** (`job_conf.yml`)
```yaml
gcp_batch:
  load: galaxy.jobs.runners.gcp_batch:GoogleCloudBatchJobRunner
  # Network and NFS configuration
  nfs_server: <NFS_LOADBALANCER_EXTERNAL_IP>
  nfs_path: /
  nfs_mount_path: /mnt/nfs
  network: <VPC_NETWORK_NAME>
  subnet: <SUBNET_NAME>
  # Other GCP Batch settings...
```

### **Firewall Requirements**
Ensure GCP firewall rules allow:
```bash
# Allow NFS traffic from Batch subnet to NFS LoadBalancer
gcloud compute firewall-rules create allow-nfs-from-batch \
  --allow tcp:2049,tcp:20048,tcp:111,tcp:32765 \
  --source-ranges <BATCH_SUBNET_CIDR> \
  --target-tags nfs-server \
  --description "Allow NFS access from GCP Batch VMs"
```

## Best Practices

1. **Monitor NFS performance** and adjust mount options as needed
2. **Use session affinity** to maintain locking consistency
3. **Configure appropriate timeouts** for long-running jobs
4. **Implement backup strategies** for NFS data
5. **Regular health checks** of NFS server pods
6. **Resource limits** on NFS server to prevent resource exhaustion
7. **Test failover scenarios** to ensure high availability

## References

- [NFS-Ganesha Documentation](https://github.com/nfs-ganesha/nfs-ganesha/wiki)
- [Kubernetes NFS Provisioner](https://github.com/kubernetes-sigs/nfs-ganesha-server-and-external-provisioner)
- [Galaxy Job Configuration](https://docs.galaxyproject.org/en/latest/admin/jobs.html)
- [GCP Batch Documentation](https://cloud.google.com/batch/docs)