#!/usr/bin/env bash

provider=k3s
if [[ $# > 0 ]] ; then
  case $1 in
    k3s|rke)
      provider=$1
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
fi
ansible-playbook -i inventories/hosts.ini -e kube_cloud_provider=openstack -e k8s_provider=$provider -c local playbook.yml

