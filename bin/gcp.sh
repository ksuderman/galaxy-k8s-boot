#!/usr/bin/env bash

if [[ $# -eq 0 ]] ; then
  echo 'Usage: bin/gcp.sh start|stop galaxy|pulsar'
  exit 1
fi

DIR=$(dirname $(realpath $0))

CORES=16
TYPE=n2-standard-8
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
        8) CORES=8 ;;
        16) CORES=16 ;;
        32) CORES=32  ;;
        64) CORES=64 ;;
        128) CORES=128 ;;
        *)
          echo "Invalid number of cores, must be one of 8, 16,32, 64, or 128"
          exit
          ;;
      esac
      shift
      ;;
    -n|--name) NAME=$2 ; shift ;;
#    -k|--key) KEY=$2 ; shift ;;
#    -g|--group) GROUP=$2 ; shift ;;
#    -i|--image) IMAGE=$2 ; shift ;;
#    -t|--type) TYPE=$2 ; shift ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

if [[ -z $command ]] ; then
  echo "Error: missing command."
  echo 'Usage: bin/gcp.sh [start|stop] [galaxy|pulsar]'
  exit 1
fi
if [[ -z $app ]] ; then
  echo "Error: missing app."
  echo "Usage: bin/gcp.sh $command [galaxy|pulsar]"
  exit 1
fi
# The name of the instance to be created.

function terminate() {
    echo "Stopping $1..."
    gcp rm $1
}

case $command in
  start)
    echo "Starting $NAME..."
    case $app in
      galaxy)
        #TYPE=m6i.4xlarge
        USER_DATA=$DIR/gcp.yml
        ;;
      pulsar)
        CORES=4
        USER_DATA=$DIR/pulsar.yml
        ;;
      *)
        echo "Unknown app: $app"
        exit 1
        ;;
    esac
    echo "Running gcp create with $CORES cores and user data $USER_DATA"
    gcp create $NAME --cores $CORES --user-data $USER_DATA --ip ks-dev-ip
    ;;
  stop)
    terminate $NAME
    ;;
  *)
    echo 'Usage: bin/gcp.sh start|stop galaxy|pulsar'
    exit 1
    ;;
esac

