#!/usr/bin/env bash
set -eu

function keep_waiting() {
	logline=$(gcloud compute ssh $SERVER --project=anvil-and-terra-development --zone=us-east4-c --command='sudo tail -1 /var/log/cloud-init-output.log' 2>/dev/null | awk '{print $1}')
	#echo $logline
	if [[ $logline == "Cloud-init" ]] ; then
		echo "no"
	else
		echo "yes"
	fi
}
 
SERVER=${SERVER:-ks-dev-batch}
ip=$(gcloud compute instances list --filter="name~.*${SERVER}.*" --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)
echo -n "Waiting for $ip"
while ! nc -z $ip 22 ; do
	sleep 1
done
waiting="yes"
# echo "Waiting: $waiting"
while [[ $(keep_waiting) == "yes" ]] ; do
	echo -n "."
	sleep 5
	#waiting=$(keep_waiting)
done
echo "Done"

