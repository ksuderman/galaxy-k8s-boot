.PHONY: k3s

REPO=ksuderman
IMAGE=galaxy-k8s-boot
VERSION=$(shell cat VERSION)
VM_NAME=dev
VM_IP=$(shell cluster ip $(VM_NAME))
PLATFORM=--platform linux/amd64

all: build push

vm:
	os launch ks-$(VM_NAME) --image Featured-Ubuntu24 --cores 16 --disk 512 --ip $(VM_IP) --user-data bin/cloud-init.sh

build:
	sudo docker buildx build -t $(REPO)/$(IMAGE):$(VERSION) $(PLATFORM) --build-arg MAJOR_VERSION=24  .

push:
	sudo docker push $(REPO)/$(IMAGE):$(VERSION)

run:
	sudo docker run -it $(REPO)/$(IMAGE):$(VERSION) bash

pull:
	git pull origin $(shell git branch --show-current)

env:
	python3 -m venv .venv
	. .venv/bin/activate
	pip install -r requirements.txt

clean:
	sudo docker rmi --force $(REPO)/$(IMAGE):$(VERSION)

clean-all:
	sudo docker rmi --force $(shell docker images -q)
