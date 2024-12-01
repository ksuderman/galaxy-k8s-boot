# Galaxy Kubernetes Boot

This project is a collection of [Ansible Playbooks](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html) and configurations to deploy a Kubernetes cluster (K3S or RKE2) and a Galaxy instance.  The playbooks work on GCP, AWS, and OpenStack VM instances.  Support for Azure will be added.

Currently, only the K3S cluster has been tested.  The RKE2 cluster is a work in progress.

## Requirements

The playbooks assume:

1. One or more Ubuntu servers with SSH access.
2. We have the SSH key to access the servers.
3. The servers have internet access and a public IP address.
4. We are configuring a single node cluster.

If using an OS other than Ubuntu, the `setup.yml` playbook will need to be modified to use that distribution's package manager to install the required packages.  To configure a multi-node cluster the inventory file will need to be modified to include the additional nodes.

## Setup

To run the playbook we need to install Ansible and some other optional requirements that are only needed to generate the inventory file with the `bin/inventory.sh` script.  The easiest way to install Ansible and the other requirements is to use `pip`.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Generating the inventory

The inventory is a file that lists the servers to be configured and defines some variables that are used in the playbooks. There is a Bash script that generates the inventory file, or it can be created manually based on the template provided.  There are example inventory files in the `inventories` directory, but they can not be used as-is as the IP addresses and SSH keys will need to be updated.

To generate the inventory file, run the following command:

```bash
bin/inventory.sh --name my-server --ip 1.2.3.4 --key ~/.ssh/my-key.pem > inventories/my-server.ini
```

## Running the playbooks

Once the inventory file is created, we can run the playbooks to deploy the Kubernetes cluster and the Galaxy instance.  The playbook takes one argument, the `kube_cloud_provider`, which must be one of `gcp`, `aws`, or `openstack`.

```bash
ansible-playbook -i inventories/my-server.ini playbooks/playbook.yml --extra-vars "kube_cloud_provider=gcp"
```
Once the playbook completes, the Galaxy instance will be available at `http://<server-ip>/galaxy/` after a few minutes.  If you would like to manage the Kubernetes cluster, you can use the `kubectl` command on the server, or download the `kubeconfig` file from the server and use it on your local machine.

```bash
scp -i ~/.ssh/my-key.pem ubuntu@<server-ip>:/home/ubuntu/.kube/config ~/.kube/config
```