#!/bin/bash

# Check if all required arguments are provided
if [ "$#" -ne 5 ]; then
    echo "Usage: $0 <host> <galaxy_api_key> <email> <password> <username>"
    echo "Example: $0 localhost:8080 ADMIN_API_KEY user@example.com userpass username"
    exit 1
fi

host="$1"
galaxy_api_key="$2"
email="$3"
password="$4"
username="$5"

json_data=$(cat <<EOF
{
    "username": "$username",
    "email": "$email",
    "password": "$password"
}
EOF
)

curl -s -X POST \
    -H "x-api-key: $galaxy_api_key" \
    -H "Content-Type: application/json" \
    -d "$json_data" \
    "http://$host/api/users"

# Add a newline for better formatting
echo
