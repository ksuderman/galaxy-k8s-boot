ARG BASE_IMAGE=ubuntu:20.04
FROM $BASE_IMAGE

ARG DEBIAN_FRONTEND=noninteractive

ARG APP_DIR=/home/ubuntu
ARG KUBE_CLOUD_PROVIDER=openstack
ARG K8S_PROVIDER=k3s
ARG PLAYBOOK=playbook.yml

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

RUN pip install --upgrade pip && pip install --no-cache --upgrade  -r requirements.txt
CMD ["ansible-playbook", "-i", "inventories/hosts.ini", "playbook.yml", "-e", "kube_cloud_provider=$KUBE_CLOUD_PROVIDER", "-e", "k8s_provider=$K8S_PROVIDER", "--connection=local"]
#ENTRYPOINT ["/sbin/init"]
