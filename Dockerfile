FROM python:3.12-slim
#FROM ubuntu:22.04

ARG APP_DIR=/playbook
ARG KUBE_CLOUD_PROVIDER=openstack
ARG K8S_PROVIDER=k3s

#RUN apt-get update \
#    && apt-get install -y apt-utils \
#    && apt-get install -y dbus systemd systemd-sysv systemd-cron rsyslog iproute2 \
#    && apt-get clean \
#    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
#
#RUN apt-get update \
#	&& apt-get install -y python3 python3-pip python3-venv\
#	&& apt-get clean \
#	&& rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
##    && pip install --upgrade pip

WORKDIR $APP_DIR

COPY requirements.txt $APP_DIR/requirements.txt
COPY ./k3s $APP_DIR/k3s
COPY ./rke $APP_DIR/rke
COPY ./values $APP_DIR/values
COPY *.yml $APP_DIR/
COPY ./inventories/hosts.ini $APP_DIR/inventories/hosts.ini
COPY ./templates $APP_DIR/templates

RUN pip install --upgrade pip && pip install --no-cache --upgrade -r requirements.txt
CMD ["ansible-playbook", "-i", "inventories/hosts.ini", "playbook.yml", "-e", "kube_cloud_provider=$KUBE_CLOUD_PROVIDER", "-e", "K8S_PROVIDER=$K8S_PROVIDER", "--connection=local"]
#ENTRYPOINT ["/sbin/init"]
