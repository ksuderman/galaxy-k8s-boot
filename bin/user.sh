#!/usr/bin/env bash

set -eu

ssh_key=~/.ssh/ks-galaxy-aws.pem

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <instance name>"
    exit
fi

ip=$(ec ip $1)
if [[ -z $ip ]]; then
    echo "No such instance: $1"
    exit
fi
echo "Server IP: $ip"
api_key=$(ssh -i $ssh_key ubuntu@$ip "cat /run/galaxy_api_key")
if [[ -z $api_key ]]; then
    echo "No API key found"
    exit
fi
json_data=$(cat <<EOF
{
    "username": "admin",
    "email": "admin@example.com",
    "password": "galaxypassword"
}
EOF
)

curl -s -X POST \
    -H "x-api-key: $api_key" \
    -H "Content-Type: application/json" \
    -d "$json_data" \
    "http://$ip/api/users" | jq

# Add a newline for better formatting
echo
