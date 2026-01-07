#!/usr/bin/env bash
set -eu

reset="\033[0m"
bold="\033[1m"
white="\033[97m"

function hi() {
        echo -e "$bold$1$reset"
}

ASK="yes"
BATCH=""
BOOT=300GB
CORES=8
DELAY=${DELAY:-5}
DELETE="/tmp/gcp.json"
IP=
KUBE=gcp
MEM=standard
NAME=${NAME:-ks-batch-working}
NAMESPACE=galaxy
PRIVATE_KEY=~/.ssh/ks-cluster.pem
PROJECT_ID=anvil-and-terra-development
PUBLIC_KEY=~/.ssh/ks-cluster.pub
#REGION=us-east4
SECRET=/Users/suderman/.secret/galaxy-batch-key.json
TIMEOUT=5m
TYPE=n2
USERNAME=ubuntu
VALUES=("plain.yml")   # The $VALUES files must reside in the values/ directory.
VM_IMAGE=galaxy-k8s-boot-v2025-09-26
ZONE=${ZONE:-us-east4-b}

function help() {
	less -RX <<EOF
	
    $(hi NAME)
        $(basename $0)

    $(hi SYNOPSYS)
        $(basename $0) [start|stop|install|kube|secret|all|bounce]
	
    $(hi DESCRIPTION)
        Launch a GCP VM and install Galaxy.
    
    $(hi COMMANDS)
        all     - Starts the VM, installs Galaxy, downloads the kubeconfig, and defines the secret
        bounce  - Stops the VM and then restarts it performing all tasks
        install - Installs Galaxy and all of its dependencies
        kube    - Downloads the kubeconfig file for the cluster
        open    - Opens Galaxy in a web browser
        pause   - Wait for five seconds. You can also append the delay to the pause command, eg. $(hi pause30)
        secret  - Defines the Kubernetes Secret needed to connect to GCP Batch
        start   - Starts a GCP VM
        stop    - Stops the VM
        version - Displays the Galaxy version
        wait    - Wait for all of the Galaxy deployments to rollout
    
    $(hi NOTE)
        If $(hi --batch) is specified the Galaxy pods will be stuck in a $(hi pending) state until the $(hi secret) 
        has been defined as they all need to mount the secret as a configmap.qs
    
    $(hi OPTIONS)
        -b, --batch     Configure the GCP Batch job runner when installing Galaxy
        -c, --cores [4|8|16|32|64|128] 
                        Number of cores for the VM. Default is $(hi $CORES)
    	-d, --disk      The size of the boot disk in GB. Default is $(hi $BOOT)
    	-f, --values    The Helm values used when installing Galaxy. Default is $(hi $VALUES)
    	    --highmem   Create a VM with more memory. Default is $(hi $MEM)
    	-k, --key       The SSH key used by the playbook to connect to the server
    	    --kube      The name of the local kubeconfig file. Default is $(hi $KUBE)
    	-n, --name      The name of the cluster to create. Default is $(hi $NAME)
    	    --namespace The namespace where Galaxy is installed. Default is $(hi $NAMESPACE)
    	-p, --project   The GCP project. Default is $(hi $PROJECT_ID)
    	-s, --secret    JSON file containing security key for the Batch service account. Default is $(hi $SECRET)
    	    --timeout   Timeout parameter when waiting for deployments to rollout. Default is $(hi $TIMEOUT)
    	-t, --type      The machine type for the VM. Default is $(hi $TYPE)
        -u, --user      The username used to connect to the VM. Default is $(hi $USERNAME)
        -v, --vm        The VM image to use for cluster nodes. Default is $(hi $VM_IMAGE)
        -y, --yes       Don't prompt for confirmation before opening Galaxy.
    	-z, --zone      The zone where the VM will be created. Default is $(hi $ZONE)
        -h, --help      Print this help and exit

    Press $(hi Q) to quit.

EOF
}

if [[ $# -eq 0 ]] ; then
	help
	exit 1
fi
COMMANDS=()
while [[ $# -gt 0 ]] ; do
	case $1 in
		-b|--batch) BATCH="-e enable_gcp_batch=true"; VALUES[0]="batch.yml" ;;
		-c|--cores)
			case $2 in
				4|8|16|32|64|128) CORES=$2; shift ;;
				*)
					echo "Invalid selection. Cores must be one of 4, 8, 16, 32, 64, or 128"
					exit 1
					;;
			esac
			;;
		-d|--disk) BOOT=$2 ; shift ;;
    	-f|--values) VALUES+=($2) ; shift ;;
		--highmem) MEM=highmem ;;
		-k|--key) PRIVATE_KEY=$2 ; PUBLIC_KEY=$2 ; shift ;;
		--kube) KUBE=$2 ; shift ;;
		-n|--name) NAME=$2 ; shift ;;
		--namespace) NAMESPACE=$2 ; shift ;;
		-p|--project) PROJECT_ID=$2 ; shift ;;
		-t|--type) TYPE=$2 ; shift ;;
		--timeout) TIMEOUT=$2 ; shift ;;
		-u|--user) USERNAME=$2 ; shift ;;
		-v|--vm) VM_IMAGE=$2 ; shift ;;
		-y|--yes) ASK="no" ;;
		-z|--zone) ZONE=$2 ; shift;;
		-h|--help|help) help ; exit 0 ;;
		*)
			COMMANDS+=($1)
			;;
	esac
	shift	
done

function get_ip() {
	if [[ -z $IP ]] ; then	
		IP=$(gcloud compute instances list | grep $NAME | awk '{print $5}')
	fi
}

function wait_for_ssh() {
    local ip=$1
    local max_attempts=60
    local attempt=0

    echo "Waiting for SSH connection to $ip:22..."

    while [[ $attempt -lt $max_attempts ]]; do
        if nc -z -w5 $ip 22 2>/dev/null; then
            echo "✓ SSH connection established to $ip:22"
            return 0
        fi

        attempt=$((attempt + 1))
        echo "Attempt $attempt/$max_attempts: SSH not ready, waiting 5 seconds..."
        sleep 5
    done

    echo "✗ Failed to establish SSH connection to $ip:22 after $max_attempts attempts"
    echo "Please check that the VM is running and SSH is enabled"
    return 1
}

function start() {
	echo "Starting $NAME in $ZONE"
	echo "Disk    $BOOT"
	echo "Type    $MACHINE"
	echo "User    $USERNAME"
	gcloud compute instances create $NAME \
	  --boot-disk-size=$BOOT \
	  --boot-disk-type=pd-balanced \
	  --image=$VM_IMAGE \
	  --image-project=$PROJECT_ID \
	  --machine-type=$MACHINE \
	  --metadata=ssh-keys="$USERNAME:$(cat $PUBLIC_KEY)" \
	  --project=$PROJECT_ID \
	  --scopes=cloud-platform \
	  --service-account=galaxy-batch-vm@${PROJECT_ID}.iam.gserviceaccount.com \
	  --tags=k8s,http-server,https-server \
	  --zone=$ZONE
	for f in $DELETE ; do
		rm -rf $f
	done
}

function stop() {
	echo "Stopping $NAME in zone $ZONE"
	gcloud compute instances delete --quiet --zone $ZONE $NAME

}
function install() {
	get_ip
	echo "Instance IP is $IP"

	# Wait for SSH connectivity before proceeding
	if ! wait_for_ssh $IP; then
		echo "Aborting installation - SSH connectivity check failed"
		exit 1
	fi
	echo "Generating inventory file and starting Galaxy installation..."
	bin/inventory.sh --ip $IP --key $PRIVATE_KEY --name $KUBE > inventories/$KUBE.ini
	echo "Installing Galaxy with values files ${VALUES[@]}"
	ansible-playbook -i inventories/$KUBE.ini -e $(jq -nc --args '{chart_values_file: $ARGS.positional}' -- "${VALUES[@]}") -e "application=galaxy" -e "galaxy_namespace=$NAMESPACE" $BATCH deploy-galaxy.yml
}

function kube() {
	get_ip
	echo "Instance IP is $IP"
	gcloud compute scp --zone $ZONE $USERNAME@$NAME:/home/$USERNAME/.kube/config ~/.kube/configs/$KUBE
	sed -i '' "s|https://0.0.0.0:6443|https://$IP:6443|" ~/.kube/configs/$KUBE
	if [[ -e .kubeconfig ]] ; then
		rm .kubeconfig
	fi 
	kshim local $KUBE
}

function secret() {
	kubectl create secret generic gcp-batch-key \
	  --from-file=key.json=$SECRET \
	  --namespace galaxy				
}

function wait_for_galaxy() {
	for deployment in $(kubectl get deployments -n $NAMESPACE -o json | jq -r .items[].metadata.name) ; do
		kubectl rollout status deployment -n $NAMESPACE --watch $deployment --timeout $TIMEOUT
	done
}

function pause() {
	echo "Sleeping for $1 seconds"
	sleep $1
}

function version() {
	get_ip
	curl http://$IP/api/version | jq
}

function open_galaxy() {
	if [[ $ASK = "yes" ]] ; then
		read -p "Would you like to open http://$IP in a browser? [Y|n] " response
		case $response in
			y|Y)
				wait_for_galaxy 
				open http://$IP
				;;
			n|N)
				exit
				;;
			*)
				wait_for_galaxy 
				open http://$IP
				;;
		esac
	else
		wait_for_galaxy
		open http://$IP
	fi
}

function test() {
	echo "${VALUES[@]}"
	
}

MACHINE="$TYPE-$MEM-$CORES"
for command in ${COMMANDS[@]} ; do
	case $command in
		install|kube|secret|start|stop|test|version)
			$command
			;;
		all)
			start
			sleep 10
			install
			kube
			secret
			echo "Your Galaxy instance should be ready in a few minutes at $IP"
			open_galaxy
			;;
		bounce)
			stop
			sleep 2
			start
			sleep 15
			install
			kube
			secret
			echo "Your Galaxy instance should be ready in a few minutes at $IP"
			open_galaxy
			;;
		open)
			get_ip
			open_galaxy
			;;
		pause)
			pause $DELAY
			;;
		pause*)
			pause $(echo $command | sed 's/pause//')
			;;
		wait)
			wait_for_galaxy
			;;
		*)
			echo "Invalid command  $command"
			;;
	esac
done
