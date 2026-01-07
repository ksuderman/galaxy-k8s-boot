#!/usr/bin/env bash
set -eu

server=${SERVER:-ks-dev-batch}
cloud=${CLOUD:-gcp}
user=${USERNAME:-$USER}
zone=${ZONE:=us-east4-c}

function help() {
	less -RX << EOF

NAME
    $0
    
SYNOPSIS
    $0 [-c|--cloud <cloud>] [-s|--server <server name>] [-u|--user | <username>]
    
DESCRIPTION
    Downloads the kubeconfig file from the server and saves it to ~/.kube/configs
    
OPTIONS
    -c, --cluster      name used to save the kubeconfig file. Default is $cloud
    -s, --server       name of the GCP instance. Default is $server
    -u, --user         user name used to SSH/SCP to the GCP VM. Default is $user
    -z, --zone         zone containing the GCP VM. Default is $zone
    -h, --help, help   print this help message and exit
    
EXAMPLES
    $0 -u ubuntu -s my-server -c testing
    $0 --user ubuntu --server my-server --cloud testing
	
Press Q to exit

EOF
}

while [[ $# -gt 0 ]] ; do
	case $1 in
		-c|--cloud) cloud=$2 ; shift ;;
		-s|--server) server=$2 ; shift ;;
		-u|--user) user=$2 ; shift ;;
		-h|--help|help)
			help
			exit 1
			;;
	esac
	shift
done

ip=$(gcloud compute instances list | grep $server | awk '{print $5}')

cat <<EOF
NAME  : $server
URL   : http://$ip
CLOUD : $cloud
USER  : $user
ZONE  : $zone
EOF

if [[ -e ~/.kube/configs/$cloud ]] ; then
	echo "Removing the existing kubeconfig file"
	chmod 0600 ~/.kube/configs/$cloud
	rm ~/.kube/configs/$cloud
fi
gcloud compute scp --zone $zone $USER@$server:/etc/rancher/rke2/rke2.yaml ~/.kube/configs/$cloud
kubectl config set-cluster default --server=https://$ip:6443 --kubeconfig=/Users/suderman/.kube/configs/$cloud
chmod 0400 ~/.kube/configs/$cloud

