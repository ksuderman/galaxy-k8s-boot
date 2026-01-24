#!/usr/bin/env bash
set -eu

if [[ -z $SERVER ]] ; then
	echo "Please set the \$SERVER variable."
	exit 1
fi

function keep_waiting() {
	logline=$(gcloud compute ssh $SERVER --project=anvil-and-terra-development --zone=us-east4-c --command='sudo tail -1 /var/log/cloud-init-output.log' 2>/dev/null | awk '{print $1}')
	#echo $logline
	if [[ $logline == "Cloud-init" ]] ; then
		echo "no"
	else
		echo "yes"
	fi
}

function get_log_line() {
	echo gcloud compute ssh $SERVER --project=anvil-and-terra-development --zone=us-east4-c --command='sudo tail -1 /var/log/cloud-init-output.log' 2>/dev/null
}
 
SERVER=${SERVER:-ks-dev-batch}
ip=$(gcloud compute instances list --filter="name~.*${SERVER}.*" --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)
echo "Waiting for the VM at $ip to come up"
# First wait for the VM to come up
while ! nc -z $ip 22 ; do
	sleep 1
done
echo "Waiting for cloud init to complete"
while [[ ! "$(gcloud compute ssh "$SERVER" \
  --project=anvil-and-terra-development \
  --zone=us-east4-c \
  --command='sudo tail -1 /var/log/cloud-init-output.log' 2>/dev/null)" == *Cloud-init* ]]
do
echo -n "."
sleep 5
done
echo
echo "Done"
exit

# Then tail the cloud init log until the init script completes
while [[ ! "$(gcloud compute ssh $SERVER --project=anvil-and-terra-development --zone=us-east4-c --command='sudo tail -1 /var/log/cloud-init-output.log' 2>/dev/null)" == *Cloud-init* ]] ; do
	echo -n "."
	sleep 5
done
echo "Done"

