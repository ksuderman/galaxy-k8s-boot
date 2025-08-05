#!/usr/bin/env bash

if [[ $# -eq 0 ]] ; then
  echo 'Usage: bin/aws.sh start|stop galaxy|pulsar'
  exit 1
fi

# Name of the SSH key pair to use. This key pair must already exist in the AWS account.
KEY=ks-galaxy-aws

DISK_SIZE_GB=300
# Security group to use. This security group must already exist in the AWS
# account and allow incoming traffic on ports 22, 80, and 6443.
GROUP=ks-dev-sg
IMAGE=ami-0e2c8caa4b6378d8c
TYPE=m6i.4xlarge

DIR=$(dirname $(realpath $0))
NAME=ks-dev-galaxy

command=
app=
#shift
while [[ $# > 0 ]]; do
  case $1 in
    start|stop) command=$1 ;;
    galaxy|pulsar) app=$1 ;;
    -c|--cores)
      case $2 in
        8) TYPE=m6i.2xlarge ;;
        16) TYPE=m6i.4xlarge ;;
        32) TYPE=m6i.8xlarge ;;
        64) TYPE=m6i.16xlarge ;;
        128) TYPE=m6i.32xlarge ;;
        *)
          echo "Invalid number of cores, must be one of 8, 16,32, 64, or 128"
          exit
          ;;
      esac
      shift
      ;;
    -n|--name) NAME=$2 ; shift ;;
    -k|--key) KEY=$2 ; shift ;;
    -g|--group) GROUP=$2 ; shift ;;
    -i|--image) IMAGE=$2 ; shift ;;
    -t|--type) TYPE=$2 ; shift ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

if [[ -z $command ]] ; then
  echo "Error: missing command."
  echo 'Usage: bin/aws.sh [start|stop] [galaxy|pulsar]'
  exit 1
fi
if [[ -z $app ]] ; then
  echo "Error: missing app."
  echo "Usage: bin/aws.sh $command [galaxy|pulsar]"
  exit 1
fi
# The name of the instance to be created.

mapping=$(cat << EOF
[
  {
    "DeviceName": "/dev/sda1",
    "Ebs": {
      "VolumeSize": 30,
      "VolumeType": "gp3"
    }
  },
  {
    "DeviceName": "/dev/sdb",
    "Ebs": {
      "VolumeSize": $DISK_SIZE_GB,
      "VolumeType": "gp3"
    }
  }
]
EOF
)

function terminate() {
    echo "Stopping $1..."
    ID=$(aws ec2 describe-instances \
            --filters "Name=tag:Name,Values=$1" \
                      "Name=instance-state-name,Values=running" \
            --query "Reservations[*].Instances[*].InstanceId" \
            --output text)
    if [[ -z $ID ]] ; then
      echo "No running vm name $1 found."
      return
    fi
    aws ec2 terminate-instances --instance-ids $ID

}

case $command in
  start)
    echo "Starting $NAME..."
    case $app in
      galaxy)
        #TYPE=m6i.4xlarge
        USER_DATA=file://$DIR/aws.yml
        ;;
      pulsar)
        TYPE=m6i.4xlarge
        USER_DATA=file://$DIR/pulsar.yml
        ;;
      *)
        echo "Unknown app: $app"
        exit 1
        ;;
    esac
    aws ec2 run-instances \
      --image-id $IMAGE \
      --instance-type $TYPE \
      --key-name $KEY \
      --security-group-ids $GROUP \
      --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME}]" \
      --metadata-options "HttpTokens=optional" \
      --block-device-mappings "$mapping" \
      --count 1 \
      --output json \
      --user-data $USER_DATA
    ;;
  stop)
    terminate $NAME
    ;;
  *)
    echo 'Usage: bin/aws.sh start|stop galaxy|pulsar'
    exit 1
    ;;
esac

