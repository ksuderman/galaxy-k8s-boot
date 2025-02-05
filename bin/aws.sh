#!/usr/bin/env bash

if [[ $# -eq 0 ]] ; then
  echo 'Usage: bin/aws.sh start|stop'
  exit 1
fi

# Name of the instance to be created
NAME=ks-dev
# Name of the SSJ key pair to use. This key pair must already exist in the AWS account.
KEY=ks-galaxy-aws

DISK=300
# Security group to use. This security group must already exist in the AWS
# account and allow incoming traffic on ports 22, 80, and 6443.
GROUP=ks-dev-sg
IMAGE=ami-0e2c8caa4b6378d8c
TYPE=m6i.4xlarge

DIR=$(dirname $(realpath $0))

command=$1
shift
while [[ $# > 0 ]]; do
  case $1 in
    -n|--name) NAME=$2 ; shift ;;
    -k|--key) KEY=$2 ; shift ;;
    -g|--group) GROUP=$2 ; shift ;;
    -i|--image) IMAGE=$2 ; shift ;;
    -t|--type) SIZE=$2 ; shift ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

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
      "VolumeSize": $DISK,
      "VolumeType": "gp3"
    }
  }
]
EOF
)

case $command in
  start)
    echo "Starting $NAME..."
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
      --user-data file://$DIR/aws.yml
    ;;
  stop)
    echo "Stopping $NAME..."
		ID=$(aws ec2 describe-instances \
    			--filters "Name=tag:Name,Values=$NAME" \
    			          "Name=instance-state-name,Values=running" \
    			--query "Reservations[*].Instances[*].InstanceId" \
    			--output text)
    if [[ -z $ID ]] ; then
      echo "No running vm found."
      exit 1
    fi
    aws ec2 terminate-instances --instance-ids $ID
    ;;
  *)
    echo 'Usage: bin/azure.sh start|stop'
    exit 1
    ;;
esac

