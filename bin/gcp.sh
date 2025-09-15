#!/usr/bin/env bash

if [[ $# -eq 0 ]] ; then
  echo 'Usage: bin/gcp.sh start|stop [options]'
  echo 'Options:'
  echo '  -c, --cores <4|8|16|32|64|128>  Machine type cores'
  echo '  -d, --disk <size>               Boot disk size in GB'
  echo '  -k, --key <path>                SSH key file path'
  echo '  -n, --name <name>               Instance name'
  echo '  -w, --network <network>         VPC network name'
  echo '  -r, --region <region>           GCP region (for subnet)'
  echo '  -s, --subnet <subnet>           Subnet name'
  echo '  -u, --user <username>           Login user name'
  echo '  -z, --zone <zone>               GCP zone'
  exit 1
fi

DIR=$(dirname $(realpath $0))
DISK=300
IMAGE="--image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud"
KEY=$HOME/.ssh/ks-cluster.pub
NAME=ks-dev-batch
TAGS="http-server,https-server,k8s"
TYPE=n2-standard-8
ZONE=us-east4-b
NETWORK=""
SUBNET=""
REGION=""
USERNAME=ubuntu

command=$1
shift
while [[ $# > 0 ]]; do
  case $1 in
    -c|--cores)
      echo "Parsing cores $2"
      case $2 in
        4|8|16|32|64|128)
          TYPE=n2-standard-$2
          ;;
        *)
          echo "Invalid number of --cores.  Specify one of 4, 8, 16, 32, 64, or 128"
          exit 1
          ;;
      esac
      shift
      ;;
    -d|--disk) DISK=$2 ; shift ;;
    -k|--key) KEY=$2 ; shift ;;
    -n|--name) NAME=$2 ; shift ;;
    -z|--zone) ZONE=$2 ; shift ;;
    -w|--network) NETWORK=$2 ; shift ;;
    -s|--subnet) SUBNET=$2 ; shift ;;
    -r|--region) REGION=$2 ; shift ;;
    -u|--user) USERNAME=$2 ; shift ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

case $command in
  start)
    echo "Starting $NAME..."
    
    # Build networking options
    NETWORK_OPTS=""
    if [[ -n "$NETWORK" ]]; then
      NETWORK_OPTS="--network=$NETWORK"
      echo "Using VPC network: $NETWORK"
    fi
    
    SUBNET_OPTS=""
    if [[ -n "$SUBNET" ]]; then
      SUBNET_OPTS="--subnet=$SUBNET"
#      if [[ -n "$REGION" ]]; then
#        SUBNET_OPTS="--subnet=$SUBNET --subnet-region=$REGION"
#        echo "Using subnet: $SUBNET in region $REGION"
#      else
#        # Extract region from zone if not provided
#        SUBNET_REGION=$(echo $ZONE | sed 's/-[a-z]$//')
#        SUBNET_OPTS="--subnet=$SUBNET --subnet-region=$SUBNET_REGION"
#        echo "Using subnet: $SUBNET in region $SUBNET_REGION (derived from zone $ZONE)"
#      fi
    fi
    
    f=/tmp/ssh-keys.txt
    echo "value: |-" > $f
    echo "  $USERNAME: $(cat $KEY)" >> $f
    
    echo "Creating instance with configuration:"
    echo "  Name: $NAME"
    echo "  Zone: $ZONE"
    echo "  Machine type: $TYPE"
    echo "  Boot disk size: ${DISK}GB"
    echo "  Tags: $TAGS"
    [[ -n "$NETWORK" ]] && echo "  Network: $NETWORK"
    [[ -n "$SUBNET" ]] && echo "  Subnet: $SUBNET"
    
    gcloud compute instances create $NAME $IMAGE \
      --zone $ZONE \
      --machine-type $TYPE \
      --boot-disk-size $DISK \
      --tags=$TAGS \
      $NETWORK_OPTS \
      $SUBNET_OPTS \
      --metadata-from-file ssh-keys=$f \
      --metadata-from-file user-data=$DIR/gcp.yml
    
    if [[ $? -eq 0 ]]; then
      echo ""
      echo "✓ Instance $NAME created successfully!"
      
      # Get external IP
      EXTERNAL_IP=$(gcloud compute instances describe $NAME --zone=$ZONE --format="get(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)
      if [[ -n "$EXTERNAL_IP" ]]; then
        echo "✓ External IP: $EXTERNAL_IP"
        echo "✓ Galaxy will be available at: http://$EXTERNAL_IP:8080"
      fi
      
      echo ""
      echo "📋 For GCP Batch job runner configuration, you will need:"
      [[ -n "$NETWORK" ]] && echo "  • network: $NETWORK"
      [[ -n "$SUBNET" ]] && echo "  • subnet: $SUBNET"
      echo "  • nfs_server: <will be provided by Galaxy Helm NFS service>"
      echo ""
      echo "💡 After Galaxy is deployed, get NFS server IP with:"
      echo "   kubectl get svc -n galaxy-ns | grep nfs"
      echo ""
      echo "📖 Then update job_conf.yml with the actual values."
    fi
    ;;
  stop)
    echo "Stopping $NAME..."
    gcloud compute instances delete $NAME --zone=$ZONE --quiet
    ;;
  *)
    echo 'Usage: bin/gcp.sh start|stop'
    exit 1
    ;;
esac
