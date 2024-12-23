# Integrating with CloudMC

To integrate with CloudMC, three main steps are required.

1.  When the VM is launched, ports 22 and 80 must be open, and the AWS metadata service v1 should be enabled.

2.  Block storage should be attached and mounted at `/mnt/block_storage`. The minimum size of the disk should be 100GB.
    Sample script:

    ```bash
    sudo mkfs -t ext4 /dev/nvme1n1
    sudo mkdir /mnt/block_storage
    sudo mount /dev/nvme1n1 /mnt/block_storage
    ```

    Both Galaxy and Pulsar will use this path for storing persistent data.

3.  The `bin/init_script.sh` file contains the user-data that should be used at VM startup.
    This user-data script will initiate setup of Galaxy or Pulsar. The `APPLICATION` environment variable
    must be set in this script to either 'galaxy' or 'pulsar', depending on whether the user selected 'private_galaxy'
    or 'add_capacity_to_galaxy'.

    If 'galaxy' is specified, the 'GALAXY_API_KEY' environment variable can be set to specify the master api key for the Galaxy
    instance. Once the script execution completes, the Galaxy application will start up and start responding on port 80 in approximately 5 minutes. At this point, CloudMC can register the admin user and create Galaxy additional users as required using
    the master API key.

    If 'pulsar' was specified, the playbook will setup Pulsar instead. Specify the `PULSAR_API_KEY` environment variable in this case to a uniquely generated password. Upon completion of the playbook, Pulsar will respond on port 80 in approximately 2-3 minutes. CloudMC will then need to convey the `PULSAR_API_KEY` and the ip address/host name of the Pulsar instance to usegalaxy.ca, so that usegalaxy.ca can start routing jobs to it.

    This can be done using the BioBlend API. The `PULSAR_HOST` and `PULSAR_API_KEY` can be saved to the corresponding user's
    preferences in Galaxy as key-value pairs.
