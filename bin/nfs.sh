#!/usr/bin/env bash

# Update the NFS server IP for the gcp_batch job runner configuration

set -eu

NFS_IP=$(kubectl get svc -n nfs-provisioner | grep nfs | awk '{print $4}')
echo "Setting NFS server IP to $NFS_IP"
helm upgrade galaxy -n galaxy galaxy/galaxy --reuse-values -f - <<EOF
configs:
  job_conf.yml:
    runners:
      gcp_batch:
        nfs_server: $NFS_IP
EOF
