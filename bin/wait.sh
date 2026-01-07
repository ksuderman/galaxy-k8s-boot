#!/usr/bin/env bash
set -eu
 
SERVER=${SERVER:-ks-dev-batch}
ip=$(gcloud compute instances list --filter="name~.*${SERVER}.*" --format="value(networkInterfaces[0].accessConfigs[0].natIP)")
echo "Waiting for $ip"
while ! nc -z $ip 22 ; do
	sleep 1
done
sleep 5
gcloud compute ssh $SERVER --project=anvil-and-terra-development --zone=us-east4-c --command='sudo tail -f /var/log/cloud-init-output.log'