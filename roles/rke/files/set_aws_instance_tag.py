#!/usr/bin/python3
import argparse
import sys

import boto3

import requests


def set_instance_tags(region_name, instance_id, tags):
    ec2 = boto3.resource('ec2', region_name=region_name)
    ec2_instance = ec2.Instance(instance_id)
    ec2_instance.create_tags(
        Tags=tags)


def main(cluster_id):
    response = requests.get('http://169.254.169.254/latest/meta-data/instance-id')
    instance_id = response.text
    response = requests.get('http://169.254.169.254/latest/meta-data/placement/region')
    region_name = response.text
    set_instance_tags(region_name, instance_id,
                      [{'Key': f'kubernetes.io/cluster/{cluster_id}',
                        'Value': "owned"}])
    return 0


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Set AWS instance tag')
    parser.add_argument('cluster_id', help='cluster id of the kubernetes/rancher cluster')
    args = parser.parse_args()

    sys.exit(main(args.cluster_id))
