#!/usr/bin/env bash

# Set your project ID
export PROJECT_ID="anvil-and-terra-development"
export REGION="us-east1"

# The service account that will be attached to the GCE VM
VM_SA_NAME=galaxy-batch-vm
VM_SA_EMAIL=${VM_SA_NAME}@$PROJECT_ID.iam.gserviceaccount.com

RUNNER_SA_NAME=galaxy-batch-runner
RUNNER_SA_EMAIL=${RUNNER_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com

# ============================================================================
# 1. Create VM Service Account (for Galaxy to call Batch API)
# ============================================================================
gcloud iam service-accounts create ${VM_SA_NAME} \
    --display-name="Galaxy Batch VM Service Account" \
    --description="Service account for Galaxy VMs to manage Batch jobs" \
    --project=${PROJECT_ID}

# Grant Batch permissions to the VM service account
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${VM_SA_EMAIL}" \
    --role="roles/batch.jobsEditor"

# Grant permission to view project (needed for some operations)
gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member="serviceAccount:${VM_SA_EMAIL}" \
    --role="roles/compute.viewer"

# ============================================================================
# 2. Your existing Batch Job Service Account (galaxy-batch-runner)
# ============================================================================
# You already have: galaxy-batch-runner@anvil-and-terra-development.iam.gserviceaccount.com
# Verify it has the necessary permissions (it likely already does if you've been using it)

# Verify logging permissions (jobs write to Cloud Logging)
# If not already present, add with:
# gcloud projects add-iam-policy-binding ${PROJECT_ID} \
#     --member="serviceAccount:galaxy-batch-runner@${PROJECT_ID}.iam.gserviceaccount.com" \
#     --role="roles/logging.logWriter"

# ============================================================================
# 3. Grant VM service account permission to use your existing Batch job service account
# ============================================================================
gcloud iam service-accounts add-iam-policy-binding \
    ${RUNNER_SA_EMAIL} \
    --member="serviceAccount:${VM_SA_EMAIL}" \
    --role="roles/iam.serviceAccountUser" \
    --project=${PROJECT_ID}