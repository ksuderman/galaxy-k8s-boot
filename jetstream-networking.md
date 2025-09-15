# Jetstream2 OpenStack Networking Guide

## Overview

Jetstream2 uses a unique networking model that differs significantly from traditional OpenStack deployments. Understanding these differences is crucial for successful VM deployment and network management.

## Key Differences from Standard OpenStack

### Traditional OpenStack Networking
- VMs receive private IP addresses (e.g., 10.x.x.x, 192.168.x.x)
- Public internet access requires "floating IPs" that are associated with instances
- Two-tier networking: private networks + floating IP pools
- `openstack floating ip list` shows available public IPs

### Jetstream2's Hybrid Network Model
- **Mixed approach**: Jetstream2 uses both private networks and floating IPs
- **Two network types**: 
  - `auto_allocated_network`: Private IPs (10.x.x.x) that are internet-accessible
  - `public`: External network with floating IP ranges (149.165.x.x)
- **Floating IP workflow**: VMs get private IPs first, then floating IPs are assigned
- **Internet connectivity**: Both private and floating IPs provide internet access

## Network Characteristics

### IP Address Behavior
- IP addresses like `149.165.150.x` are **directly routable from the internet**
- These appear as "fixed IPs" in OpenStack terminology but function as public IPs
- No need for floating IP association - VMs are immediately internet-accessible
- Security groups still apply for firewall rules

### Network Discovery
```bash
# List available networks
openstack network list

# Common Jetstream2 network name
auto_allocated_network

# Get network details
openstack network show auto_allocated_network

# Check subnet information and IP ranges
openstack subnet list --network auto_allocated_network -c "Subnet" -c "Allocation Pools"
```

## Assigning Public IP Addresses to VMs

### Method 1: Let OpenStack Auto-Assign (Recommended)

This is the simplest approach - OpenStack will assign an available public IP automatically:

```bash
openstack server create \
  --flavor <flavor-name> \
  --image <image-name> \
  --network auto_allocated_network \
  --key-name <keypair-name> \
  --security-group <security-group> \
  <instance-name>
```

**Example:**
```bash
openstack server create \
  --flavor m1.medium \
  --image "Ubuntu 22.04 LTS" \
  --network auto_allocated_network \
  --key-name my-keypair \
  --security-group default \
  my-web-server
```

### Method 2: Specify a Particular IP Address

If you need a specific public IP address:

#### Step 1: Find the Network UUID
```bash
# Get the network ID
NETWORK_ID=$(openstack network show auto_allocated_network -f value -c id)
echo $NETWORK_ID
```

#### Step 2: Check Available IP Ranges
```bash
# Verify the IP you want is in the allocation pool
openstack subnet list --network auto_allocated_network -c "Subnet" -c "Allocation Pools"
```

#### Step 3: Create VM with Specific IP
```bash
openstack server create \
  --flavor <flavor-name> \
  --image <image-name> \
  --nic net-id=<network-uuid>,v4-fixed-ip=<desired-ip> \
  --key-name <keypair-name> \
  --security-group <security-group> \
  <instance-name>
```

**Example:**
```bash
openstack server create \
  --flavor m1.medium \
  --image "Ubuntu 22.04 LTS" \
  --nic net-id=dec925ab-a494-4a26-b8cf-c2deb2ead15b,v4-fixed-ip=149.165.150.100 \
  --key-name my-keypair \
  --security-group default \
  my-web-server
```

### Method 3: Floating IP Assignment (Recommended for Specific IPs)

This is the most reliable method for assigning specific public IP addresses:

#### Step 1: Create VM with Auto-Assigned Private IP
```bash
openstack server create \
  --flavor <flavor-name> \
  --image <image-name> \
  --network auto_allocated_network \
  --key-name <keypair-name> \
  --security-group <security-group> \
  <instance-name>
```

#### Step 2: Wait for VM to Be Active
```bash
# Wait for server to reach ACTIVE status
openstack server show <instance-name> -c status

# Verify private IP is assigned
openstack server show <instance-name> -c addresses
```

#### Step 3: Assign Floating IP
```bash
# List available floating IPs
openstack floating ip list

# Assign your desired floating IP
openstack server add floating ip <instance-name> <floating-ip-address>

# Verify assignment
openstack server show <instance-name> -c addresses
```

**Example:**
```bash
# Create VM
openstack server create \
  --flavor m3.xl \
  --image "Featured-Ubuntu24" \
  --network auto_allocated_network \
  --key-name ks-cluster \
  --security-group exosphere \
  my-server

# Wait for ACTIVE status
openstack server show my-server -c status -c addresses

# Assign floating IP
openstack server add floating ip my-server 149.165.150.77

# Result: auto_allocated_network=10.0.42.156, 149.165.150.77
```

### Method 4: Pre-create a Port (Advanced)

For more control or when dealing with multiple network interfaces:

#### Step 1: Create a Port with Desired IP
```bash
openstack port create \
  --network auto_allocated_network \
  --fixed-ip ip-address=<desired-ip> \
  --security-group <security-group> \
  my-port-name
```

#### Step 2: Use the Port in VM Creation
```bash
# Get the port ID
PORT_ID=$(openstack port show my-port-name -f value -c id)

# Create VM using the pre-created port
openstack server create \
  --flavor <flavor-name> \
  --image <image-name> \
  --nic port-id=$PORT_ID \
  --key-name <keypair-name> \
  <instance-name>
```

## Automation and Cloud-Init Considerations

### Floating IP Timing with Cloud-Init

When using cloud-init scripts that depend on the public IP address, timing becomes critical:

**Problem**: Cloud-init runs during boot before floating IPs are assigned, causing failures when scripts try to use the public IP.

**Solution**: Wait for floating IP assignment in your cloud-init script:

```yaml
#cloud-config
runcmd:
  # Wait for floating IP assignment and detect the correct public IP
  - |
    echo "Waiting for floating IP assignment..."
    i=1
    while [ $i -le 60 ]; do
      # Try to get public IP from multiple sources
      public_ip=$(curl -s --connect-timeout 5 ifconfig.me || curl -s --connect-timeout 5 icanhazip.com || curl -s --connect-timeout 5 ipecho.net/plain)
      local_ips=$(hostname -I)
      
      echo "Attempt $i: Public IP: $public_ip, Local IPs: $local_ips"
      
      # Check if we have a public IP that's not in private ranges
      if [ -n "$public_ip" ] && ! echo "$public_ip" | grep -qE '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'; then
        echo "Found public IP: $public_ip"
        break
      fi
      
      # Also check local interfaces for non-private IPs
      for ip in $local_ips; do
        if ! echo "$ip" | grep -qE '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.|127\.)'; then
          public_ip="$ip"
          echo "Found public IP on local interface: $public_ip"
          break
        fi
      done
      
      # Break if we found a public IP
      if [ -n "$public_ip" ] && ! echo "$public_ip" | grep -qE '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)'; then
        break
      fi
      
      sleep 10
      i=$((i + 1))
    done
    
    if [ -z "$public_ip" ] || echo "$public_ip" | grep -qE '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)']; then
      echo "Warning: No public IP found, using fallback"
      public_ip=$(hostname -I | awk '{print $1}')
    fi
    
    echo "Using IP: $public_ip" > /run/detected_ip
  # Use the detected IP in subsequent commands
  - ip=$(cat /run/detected_ip | cut -d' ' -f3) && echo "Configuring services with IP: $ip"
```

### Automated Script Integration

For automation scripts (like the `bin/openstack.sh` in this repository):

1. **Wait for VM to be ACTIVE with network interfaces**:
```bash
while true; do
  status=$(openstack server show $NAME -f value -c status)
  addresses=$(openstack server show $NAME -f value -c addresses)
  
  if [[ "$status" == "ACTIVE" ]] && [[ -n "$addresses" ]]; then
    echo "Server ready for floating IP assignment"
    break
  elif [[ "$status" == "ERROR" ]]; then
    echo "Server creation failed"
    exit 1
  fi
  sleep 10
done
```

2. **Assign floating IP immediately after VM is ready**:
```bash
openstack server add floating ip $VM_NAME $FLOATING_IP
```

3. **Verify assignment**:
```bash
openstack server show $VM_NAME -c addresses -c status
```

## Common Issues and Troubleshooting

### "Invalid IP Address" Error
```
Fixed IP x.x.x.x is not a valid ip address for network
```

**Cause**: The IP address is outside the network's allocation pool.

**Solution**: 
```bash
# Check the actual IP ranges available
openstack subnet list --network auto_allocated_network -c "Subnet" -c "Allocation Pools"

# Use an IP within the shown allocation pools
```

### "IP Already in Use" Error
**Solution**:
```bash
# Check which IPs are already taken
openstack port list --network auto_allocated_network -c "Fixed IP Addresses" -c Status

# Choose a different IP or let OpenStack auto-assign
```

### Can't Connect to VM After Creation
**Common causes**:
- Security group rules blocking access
- SSH key not properly configured
- Service not started on the VM

**Check security groups**:
```bash
# List security groups
openstack security group list

# Check rules (should include SSH access)
openstack security group rule list <security-group-name>

# Add SSH access if missing
openstack security group rule create \
  --protocol tcp \
  --dst-port 22 \
  --remote-ip 0.0.0.0/0 \
  <security-group-name>
```

## Verification Steps

After creating a VM, verify the setup:

```bash
# Check VM status and IP assignment
openstack server show <instance-name> -c status -c addresses

# Test connectivity (replace with your VM's IP)
ping <vm-ip-address>

# Test SSH access
ssh -i <private-key> <username>@<vm-ip-address>
```

## Best Practices

1. **Use auto-assignment for most cases** - Let OpenStack choose available IPs unless you have specific requirements

2. **Reserve IPs when needed** - For production services that need consistent IP addresses, use Method 3 (pre-create ports)

3. **Document your IP assignments** - Keep track of which VMs use which IP addresses

4. **Configure security groups properly** - Remember that all IPs are public, so security group rules are your primary firewall

5. **Test connectivity immediately** - Verify SSH and service access right after VM creation

## Quick Reference Commands

```bash
# Essential network information
openstack network list
openstack subnet list --network auto_allocated_network

# Create VM with auto-assigned public IP
openstack server create --flavor <flavor> --image <image> --network auto_allocated_network --key-name <keypair> <name>

# Create VM with specific public IP
openstack server create --flavor <flavor> --image <image> --nic net-id=<net-uuid>,v4-fixed-ip=<ip> --key-name <keypair> <name>

# Check VM IP assignment
openstack server show <name> -c addresses

# List used IPs on network
openstack port list --network auto_allocated_network -c "Fixed IP Addresses"
```

## Summary

Jetstream2's provider network model eliminates the complexity of floating IPs by providing direct public IP assignment. While this is different from traditional OpenStack setups, it's actually simpler for most use cases since every VM automatically gets internet connectivity without additional configuration steps.