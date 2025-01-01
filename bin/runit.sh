#!/usr/bin/env bash

CLOUD=${CLOUD:-openstack}
K8S=${K8S:-k3s}
VERSION=${VERSION:-$(cat VERSION)}

DIR=/opt/galaxy-k8s-boot

VOLUMES="-v ./.kube:$DIR/.kube -v ./outputs:$DIR/outputs" # -v ./inventories:$DIR/inventories"

echo "Installing $CLOUD/$K8S $VERSION using $DIR"

docker run -it --privileged $VOLUMES \
       --net=host  --cgroupns=host  \
       -v /etc/systemd/system:/etc/systemd/system   \
       -v /sys/fs/cgroup:/sys/fs/cgroup:ro   \
       -v /run/systemd:/run/systemd   \
       -v /var/run/dbus:/var/run/dbus   \
       -e container=docker \
       -e kube_cloud_provider=$CLOUD \
       -e k8s_provider=$K8S  \
       ksuderman/galaxy-k8s-boot:$VERSION bash

