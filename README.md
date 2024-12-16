# Galaxy Kubernetes Boot

This project is a collection of [Ansible Playbooks](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html) and configurations to deploy a Kubernetes cluster (K3S or RKE2) and a Galaxy instance. The playbooks work on GCP, AWS, and OpenStack VM instances. Support for Azure will be added.

Currently, only the K3S cluster has been tested. The RKE2 cluster is a work in progress.

The playbook can be run either against a remote host or the host itself (localhost).

## Environment setup

To run the playbook we need to install Ansible and some other optional requirements that are only needed to generate the inventory file with the `bin/inventory.sh` script. The easiest way to install the requirements is to use `pip`.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

If the host is a barebones Ubuntu, Ansible can be installed with the following commands:

```bash
sudo apt install software-properties-common
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install ansible
```

## Cloud access policy setup

### AWS

Create an IAM role with the following permissions. This is a one-time setup required for the given AWS account.

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateSnapshot",
                "ec2:AttachVolume",
                "ec2:DetachVolume",
                "ec2:ModifyVolume",
                "ec2:DescribeAvailabilityZones",
                "ec2:DescribeInstances",
                "ec2:DescribeSnapshots",
                "ec2:DescribeTags",
                "ec2:DescribeVolumes",
                "ec2:DescribeVolumesModifications"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags"
            ],
            "Resource": [
                "arn:aws:ec2:*:*:volume/*",
                "arn:aws:ec2:*:*:snapshot/*"
            ],
            "Condition": {
                "StringEquals": {
                    "ec2:CreateAction": [
                        "CreateVolume",
                        "CreateSnapshot"
                    ]
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DeleteTags"
            ],
            "Resource": [
                "arn:aws:ec2:*:*:volume/*",
                "arn:aws:ec2:*:*:snapshot/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateVolume"
            ],
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "aws:RequestTag/ebs.csi.aws.com/cluster": "true"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateVolume"
            ],
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "aws:RequestTag/CSIVolumeName": "*"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DeleteVolume"
            ],
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/ebs.csi.aws.com/cluster": "true"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DeleteVolume"
            ],
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/CSIVolumeName": "*"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DeleteVolume"
            ],
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/kubernetes.io/created-for/pvc/name": "*"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DeleteSnapshot"
            ],
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/CSIVolumeSnapshotName": "*"
                }
            }
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DeleteSnapshot"
            ],
            "Resource": "*",
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/ebs.csi.aws.com/cluster": "true"
                }
            }
        }
    ]
}
```

### GCP

Figuring out minimal GCP permissions is still work-in-progress so for the time being, create a service account with the following permissions:

```
Owner
Project IAM Admin
```

## Launching the VM

When launching a VM, use Ubuntu 22.04 image and attach above created IAM role (AWS) or service account (GCP). Every time before running the playbook on GCP, delete `gce-pd-csi-sa` service account if it exists. We also need a persistent volume created. In the case of AWS, the volume needs to be attached to the instance but in case of GCP it needs not be attached before running the playbook. The minimum size of the volume should be 100GB.

### Automated deployment

There is a script that automates the deployment process available in `bin/ini_script.sh`. The script can be supplied as user data when launching the VM and it will automatically set up the environment and run the playbook. Before using the script, update the values for the volume ID, and job max memory and cpu values to match the size of the instance; Galaxy requires 22GB of memory and 6 CPUs so deduct those amounts from the total available on the instance.

## Generating the inventory

The inventory is a file that lists the servers to be configured and defines some variables that are used in the playbooks. There is a Bash script that generates the inventory file, or it can be created manually based on the template provided. There are example inventory files in the `inventories` directory, but they can not be used as-is as the IP addresses and SSH keys will need to be updated.

To generate the inventory file, run the following command:

```bash
bin/inventory.sh --name my-server --ip 1.2.3.4 --key ~/.ssh/my-key.pem > inventories/my-server.ini
```

If running the playbook on the server itself, there is `inventories/locahost` file available that captures the necessary variables.

## Running the playbooks

Once the inventory file is created, we can run the playbooks to deploy the Kubernetes cluster and the Galaxy instance. The playbook takes the arguments

- `kube_cloud_provider`: must be one of `gcp`, `aws`, or `openstack`
- `ebs_volume_id`: the ID of the EBS volume to attach to the server. For the case of AWS this is something like `vol-1234567890abcdef0`; for the case of GCP, this is something like this `projects/[PROJECT_D]/zones/[ZONE]/disks/[DISK_NAME]`; for the case of OpenStack, this is something like `my-volume-id`
- `gcp_project_id`: the GCP project ID (required only for GCP)

```bash
ansible-playbook -i inventories/my-server.ini playbooks/playbook.yml --extra-vars "kube_cloud_provider=aws" --extra-vars "ebs_volume_id=vol-1234567890abcdef0"
```

Once the playbook completes, the Galaxy instance will be available at `http://<server-ip>/galaxy/` after a few minutes.

## Managing the Kubernetes cluster

If you would like to manage the Kubernetes cluster, you can use the `kubectl` command on the server, or download the `kubeconfig` file from the server and use it on your local machine.

```bash
scp -i ~/.ssh/my-key.pem ubuntu@<server-ip>:/home/ubuntu/.kube/config ~/.kube/config
```
