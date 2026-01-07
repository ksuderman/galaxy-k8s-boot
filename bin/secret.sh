#!/usr/bin/env bash
set -eu

# Create GCP Batch service account key secret for Galaxy
# This secret is required for Galaxy to submit jobs to GCP Batch

KUBECONFIG=${KUBECONFIG:-~/.kube/configs/gcp}
NAMESPACE=${NAMESPACE:-galaxy}
SECRET_NAME=${SECRET_NAME:-gcp-batch-key}
KEY_FILE=${KEY_FILE:-~/.secret/galaxy-batch-key.json}

function usage() {
    cat << EOF
NAME
    $0 - Create GCP Batch service account key secret

SYNOPSIS
    $0 [OPTIONS]

DESCRIPTION
    Creates a Kubernetes secret containing the GCP service account key
    required for Galaxy to submit jobs to GCP Batch.

OPTIONS
    -k, --key-file FILE     Path to GCP service account JSON key file
                            (default: ~/.secret/galaxy-batch-key.json)
    -n, --namespace NS      Kubernetes namespace (default: galaxy)
    -s, --secret-name NAME  Secret name (default: gcp-batch-key)
    --kubeconfig FILE       Path to kubeconfig file
                            (default: ~/.kube/configs/gcp)
    -h, --help              Show this help message

EXAMPLES
    $0
    $0 --key-file /path/to/key.json
    $0 --namespace my-galaxy --kubeconfig ~/.kube/config

EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -k|--key-file)
            KEY_FILE="$2"
            shift 2
            ;;
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -s|--secret-name)
            SECRET_NAME="$2"
            shift 2
            ;;
        --kubeconfig)
            KUBECONFIG="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Expand tilde in KEY_FILE
KEY_FILE="${KEY_FILE/#\~/$HOME}"
KUBECONFIG="${KUBECONFIG/#\~/$HOME}"

# Validate key file exists
if [[ ! -f "$KEY_FILE" ]]; then
    echo "Error: Key file not found: $KEY_FILE"
    echo "Please provide the path to your GCP service account JSON key file."
    exit 1
fi

# Check if namespace exists
if ! KUBECONFIG="$KUBECONFIG" kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "Error: Namespace '$NAMESPACE' does not exist."
    echo "Please ensure Galaxy is deployed or create the namespace first."
    exit 1
fi

# Check if secret already exists
if KUBECONFIG="$KUBECONFIG" kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "Secret '$SECRET_NAME' already exists in namespace '$NAMESPACE'."
    read -p "Do you want to replace it? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        KUBECONFIG="$KUBECONFIG" kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE"
    else
        echo "Aborted."
        exit 0
    fi
fi

# Create the secret
echo "Creating secret '$SECRET_NAME' in namespace '$NAMESPACE'..."
KUBECONFIG="$KUBECONFIG" kubectl create secret generic "$SECRET_NAME" \
    --from-file=key.json="$KEY_FILE" \
    -n "$NAMESPACE"

echo "Secret created successfully."
echo ""
echo "The secret contains the GCP service account key for Batch job submission."
echo "Galaxy pods mounting this secret will have access to GCP Batch API."
