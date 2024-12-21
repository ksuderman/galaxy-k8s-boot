#!/usr/bin/env bash

if [[ $# > 0 ]] ; then
  case $1 in
    k3s)
      playbook=playbook-k3s.yml
      ;;
    rke)
      playbook=playbook-rke.yml
      ;;
    -h|--help)
      echo "USAGE: $(basename $0) [k3s|rke]"
      exit 0
      ;;
    *)
      echo "ERROR: Invalid option $1"
      exit 1
      ;;
  esac
else
  playbook=playbook-rke.yml
fi
ansible-playbook -i inventories/hosts.ini -e kube_cloud_provider=openstack -e k8s_provider=$1 -c local $playbook

