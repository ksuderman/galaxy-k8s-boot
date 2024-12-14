FROM ubuntu/python:3.12-24.04_stable

ARG APP_DIR=/playbook
ARG KUBE_CLOUD_PROVIDER=openstack
ARG K8S_PROVIDER=k3s

WORKDIR $APP_DIR

COPY requirements.txt $APP_DIR/requirements.txt
COPY ./k3s $APP_DIR/k3s
COPY ./rke $APP_DIR/rke
COPY ./values $APP_DIR/values
COPY *.yml $APP_DIR/
COPY ./inventories/hosts.ini $APP_DIR/hosts.ini

RUN pip install --no-cache --upgrade -r requirements.txt
CMD ["ansible-playbook", "-i", "hosts.ini", "playbook.yml", "-e", "KUBE_CLOUD_PROVIDER=$KUBE_CLOUD_PROVIDER", "-e", "K8S_PROVIDER=$K8S_PROVIDER", "--connection=local"]
