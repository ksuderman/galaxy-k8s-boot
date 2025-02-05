#!/usr/bin/env bash

if [[ $# -eq 0 ]] ; then
  echo 'Usage: bin/azure.sh start|stop'
  exit 1
fi

az=/usr/local/bin/az

NAME=ks-dev
KEY=$HOME/.ssh/id_rsa.pub
GROUP=JH-RIT-ANVIL-TEST-RG
IMAGE=Canonical:ubuntu-24_04-lts:ubuntu-pro:latest
TYPE=Standard_D16ds_v5

DIR=$(dirname $(realpath $0))

command=$1
shift
while [[ $# > 0 ]]; do
  case $1 in
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

case $command in
  start)
    echo "Starting $NAME..."
    $az vm create \
      --resource-group $GROUP \
      --name $NAME \
      --image $IMAGE \
      --size $TYPE \
      --admin-username ubuntu \
      --ssh-key-values $KEY \
      --os-disk-size-gb 30 \
      --output table \
      --custom-data $DIR/azure.yml
    $az vm open-port --resource-group $GROUP --name $NAME --port 80 --priority 102
    ;;
  stop)
    echo "Stopping $NAME..."
    $az vm delete --resource-group $GROUP --name $NAME --yes
    ;;
  *)
    echo 'Usage: bin/azure.sh start|stop'
    exit 1
    ;;
esac

#az vm create --resource-group JH-RIT-ANVIL-TEST-RG --name ks-dev --image Canonical:ubuntu-24_04-lts:ubuntu-pro:latest --size Standard_D16ds_v5 --admin-username ubuntu --ssh-key-values /Users/suderman/.ssh/ks-cluster.pub --os-disk-size-gb 30 --output table --custom-data bin/azure.yml
#az vm open-port --resource-group JH-RIT-ANVIL-TEST-RG --name ks-dev --port 22 --priority 1001
#az vm open-port --resource-group JH-RIT-ANVIL-TEST-RG --name ks-dev --port 80 --priority 1002
