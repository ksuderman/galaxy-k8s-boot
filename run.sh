#!/usr/bin/env bash

ansible-playbook -i inventories/hosts.ini -e kube_cloud_provider=openstack -e k8s_provider=rke -c local playbook.yml
