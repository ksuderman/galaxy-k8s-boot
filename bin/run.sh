#!/usr/bin/env bash

CLOUD=${CLOUD:-openstack}
K8S=${K8S:-k3s}
VERSION=${VERSION:-$(cat VERSION)}

DIR=/opt/galaxy-k8s-boot

VOLUMES="-v ./.kube:$DIR/.kube -v ./outputs:$DIR/outputs" # -v ./inventories:$DIR/inventories"

docker run --privileged $VOLUMES \
       --network=host   --cgroupns=host  \
       -v /etc/systemd/system:/etc/systemd/system   \
       -v /sys/fs/cgroup:/sys/fs/cgroup:ro   \
       -v /run/systemd:/run/systemd   \
       -v /var/run/dbus:/var/run/dbus   \
       -e container=docker \
       -e kube_cloud_provider=$CLOUD \
       -e k8s_provider=k3s  \
       ksuderman/galaxy-k8s-boot:$VERSION

