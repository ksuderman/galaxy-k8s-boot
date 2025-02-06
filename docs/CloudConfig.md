# Cloud Config Examples


Two example scripts are provided (`bin/aws.sh` and `bin/azure.sh`) that demostrate how to launch a VM with the necessary user data (`bin/aws.yml` and `bin/azure.yml` respectively) to run the Ansible playbook and install Galaxy. The `bin/aws.sh` script also creates a block storage device and mounts it to the VM as `/mnt/block_storage`. The block storage device is used to store the persistent data for Galaxy and Pulsar.  Equivalent functionality is available in Azure, but is not demonstrated in the provided script.

## Prerequisites

Users must have the following installed on their local machine:
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html)
- [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)

Users must also have permission on AWS and Azure to create VMs, block storage devices, and manage network security groups.

### Prerequistes (AWS)

If you do not have a security group that allows incoming traffic on port 22 (SSH) and port 80 (HTTP), you can create a new security group with the following command:

```bash
# Find the VPC ID of the  VPC we want to attach the security group to.
aws ec2 describe-vpcs --query "Vpcs[*].[VpcId,State,CidrBlock,IsDefault]"

# Create a security group
aws ec2 create-security-group \
    --group-name my-security-group \
    --description "A security group for testing Cloud config examples" \
    --vpc-id <vpc-id>
# Open ports 22, 80, and 6443
aws ec2 authorize-security-group-ingress \
    --group-name my-security-group \
    --protocol tcp \
    --port 22 \
    --cidr $(curl -s ifconfig.me)/32
			
aws ec2 authorize-security-group-ingress \
    --group-name my-security-group \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0
			
aws ec2 authorize-security-group-ingress \
    --group-name my-security-group \
    --protocol tcp \
    --port 6443 \
    --cidr $(curl -s ifconfig.me)/32
			
```

On AWS a SSH key pair must also be uploaded to the region you are launching the VM in. The key pair name must be specified in the `bin/aws.sh` script.

```bash
aws ec2 import-key-pairs --key-name my-ssh-key --public-key-material ~/.ssh/id_rsa.pub
```

## Configuration

Both scripts have similar configuration options defined as environment variables at the top of each script.

- **NAME**: The name of the VM<br/> 
- **KEY**: The SSH key pair to use. On AWS this is the name of the key pair as created above. On Azure this is the path to the public key file.
- **IMAGE**: The image to use.
- **GROUP**: On AWS this is the name of the security group as created above. On Azure this is the name of the resource group.
- **TYPE**: The instance type

Users can either edit the script files to set these variables as desired or specify them on the command line when running the script.


## Usage

Starting a VM:
```bash
bin/aws.sh start
bin/aws.sh start --name my-vm --key my-ssh-key --image ami-0c55b159cbfafe1f0 --group my-security-group --type m6a.2xlarge

bin/azure.sh start
bin/azure.sh start --name my-vm \
    --key ~/.ssh/id_rsa.pub \
    --image Canonical:ubuntu-24_04-lts:ubuntu-pro:latest \
    --group JH-RIT-ANVIL-TEST-RG 
    --type Standard_D16ds_v5
```

Stopping a VM

```bash
bin/aws.sh stop
bin/aws.sh stop --name my-vm

bin/azure.sh stop
bin/azure.sh stop --name my-vm
```

**Note** If you started a VM by specifying the `--name` on the command line you will need to specify the same `--name` when stopping the VM.
