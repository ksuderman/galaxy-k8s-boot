# Galaxy Kubernetes Boot

This project is a collection of [Ansible Playbooks](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html) and configurations to deploy a Kubernetes cluster (K3S or RKE2) and a Galaxy instance. The playbooks work on GCP, AWS, and OpenStack VM instances.

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

## Launching the VM

When launching a VM, use Ubuntu 24.04 image, root file system should be at least
30GB, attach a security group with ports 22 and 80 open, and on AWS enable V1
metadata service. Also attach a block storage disk (minimum size of the disk
should be 100GB), create a file system on the disk, and mount it (see commands
below). By default, the playbook expects the disk to be mounted at
`/mnt/block_storage` but this is configurable via `block_storage_disk_path`
variable in the inventory file.

```bash
sudo mkfs -t ext4 /dev/nvme1n1
sudo mkdir /mnt/block_storage
sudo mount /dev/nvme1n1 /mnt/block_storage
```

### Automated deployment

There is a script that automates the deployment process available in
`bin/init_script.sh`. The script can be supplied as user data when launching the
VM and it will automatically set up the environment and run the playbook.

## Generating the inventory file for manual deployment

The inventory is a file that lists the servers to be configured and defines some variables that are used in the playbooks. There is a Bash script that generates the inventory file, or it can be created manually based on the template provided. There are example inventory files in the `inventories` directory, but they can not be used as-is as the IP addresses and SSH keys will need to be updated.

To generate the inventory file, run the following command:

```bash
bin/inventory.sh --name my-server --ip 1.2.3.4 --key ~/.ssh/my-key.pem > inventories/my-server.ini
```

If running the playbook on the server itself, there is `inventories/locahost` file available that captures the necessary variables.

## Running the playbooks

Once the inventory file is created, we can run the playbooks to deploy the Kubernetes cluster and the Galaxy instance. The playbook takes the arguments

- `kube_cloud_provider`: must be one of `gcp`, `aws`, or `openstack`

```bash
ansible-playbook -i inventories/my-server.ini playbooks/playbook.yml --extra-vars "kube_cloud_provider=aws"
```

Once the playbook completes, the Galaxy instance will be available at `http://<server-ip>/galaxy/` after a few minutes.

## Managing the Kubernetes cluster

If you would like to manage the Kubernetes cluster, you can use the `kubectl` command on the server, or download the `kubeconfig` file from the server and use it on your local machine.

```bash
scp -i ~/.ssh/my-key.pem ubuntu@<server-ip>:/home/ubuntu/.kube/config ~/.kube/config
```
