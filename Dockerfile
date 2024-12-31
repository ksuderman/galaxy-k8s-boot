ARG MAJOR_VERSION=20
ARG BASE_IMAGE=ubuntu:$MAJOR_VERSION.04

FROM $BASE_IMAGE as stage-1

ARG DEBIAN_FRONTEND=noninteractive
ARG APP_DIR=/home/ubuntu

RUN apt-get update \
    && apt-get install -y apt-utils dbus systemd systemd-sysv systemd-cron rsyslog iproute2 python3 python3-pip python3-venv openssh-client curl \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

#    && apt-get install -y dbus systemd systemd-sysv systemd-cron rsyslog iproute2 python3 python3-pip python3-venv \
WORKDIR $APP_DIR

COPY requirements.txt $APP_DIR/requirements.txt
COPY ./k3s $APP_DIR/k3s
COPY ./rke $APP_DIR/rke
COPY ./values $APP_DIR/values
COPY *.yml $APP_DIR/
COPY ./inventories/hosts.ini $APP_DIR/inventories/hosts.ini
COPY ./templates $APP_DIR/templates
COPY ./run.sh $APP_DIR/run.sh
COPY ./bin $APP_DIR/bin
COPY ./roles $APP_DIR/roles

FROM stage-1 as ubuntu-20
ARG KUBE_CLOUD_PROVIDER=openstack
ARG K8S_PROVIDER=k3s
ARG PLAYBOOK=playbook.yml
#RUN pip install --break-system-packages --upgrade pip &&
RUN pip install --no-cache --upgrade -r requirements-20.txt
CMD ["ansible-playbook", "-i", "inventories/hosts.ini", "playbook.yml", "-e", "kube_cloud_provider=$KUBE_CLOUD_PROVIDER", "-e", "k8s_provider=$K8S_PROVIDER", "--connection=local"]

FROM stage-1 as ubuntu-24
ARG KUBE_CLOUD_PROVIDER=openstack
ARG K8S_PROVIDER=k3s
ARG PLAYBOOK=playbook.yml
RUN pip install --no-cache --upgrade --break-system-packages -r requirements-24.txt
CMD ["ansible-playbook", "-i", "inventories/hosts.ini", "playbook.yml", "-e", "kube_cloud_provider=$KUBE_CLOUD_PROVIDER", "-e", "k8s_provider=$K8S_PROVIDER", "--connection=local"]

#FROM ubuntu-$MAJOR_VERSION as final
#ARG KUBE_CLOUD_PROVIDER=openstack
#ARG K8S_PROVIDER=k3s
#ARG PLAYBOOK=playbook.yml
#
#CMD ["ansible-playbook", "-i", "inventories/hosts.ini", "playbook.yml", "-e", "kube_cloud_provider=$KUBE_CLOUD_PROVIDER", "-e", "k8s_provider=$K8S_PROVIDER", "--connection=local"]
