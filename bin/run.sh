#!/usr/bin/env bash

CLOUD=${CLOUD:-openstack}
K8S=${K8S:-k3s}
VERSION=${VERSION:-$(cat VERSION)}

DIR=/opt/galaxy-k8s-boot

VOLUMES="-v ./.kube:$DIR/.kube -v ./outputs:$DIR/outputs" # -v ./inventories:$DIR/inventories"

while [[ $# > 0 ]] ; do
  case $1 in
    --gcp) CLOUD=gcp ;;
    --aws) CLOUD=aws ;;
    --openstack) CLOUD=openstack ;;
    --k3s) K8S=k3s ;;
    --rk3) K8S=rke ;;
    --version) VERSION=$2 ; shift ;;
    *)
      echo "ERROR: Invalid option $1"
      exit 1
      ;;
  esac
  shift
done

#docker run --privileged \
#       --network=host   --cgroupns=host  \
#       -v /etc/systemd/system:/etc/systemd/system   \
#       -v /sys/fs/cgroup:/sys/fs/cgroup:ro   \
#       -v /run/systemd:/run/systemd   \
#       -v /var/run/dbus:/var/run/dbus   \
#       -e container=docker \
#       -e kube_cloud_provider=$CLOUD \
#       -e k8s_provider=$K8S  \
#       ksuderman/galaxy-k8s-boot:$VERSION

docker run --privileged \
       -e kube_cloud_provider=$CLOUD \
       -e k8s_provider=$K8S  \
       ksuderman/galaxy-k8s-boot:$VERSION
