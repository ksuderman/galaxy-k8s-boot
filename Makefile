.PHONY: k3s

REPO=ksuderman
IMAGE=galaxy-k8s-boot
VERSION=$(shell cat VERSION)
VM_NAME=dev
VM_IP=$(shell cluster ip $(VM_NAME))
PLATFORM=--platform linux/amd64
MAJOR_VERSION=24

all: build push

vm:
	os launch ks-$(VM_NAME) --image Featured-Ubuntu$(MAJOR_VERSION) --cores 16 --disk 512 --ip $(VM_IP) --user-data bin/cloud-init.sh

vm20:
	os launch ks-$(VM_NAME) --image Featured-Ubuntu20 --cores 16 --disk 512 --ip $(VM_IP) --user-data bin/cloud-init.sh

vm24:
	os launch ks-$(VM_NAME) --image Featured-Ubuntu24 --cores 16 --disk 512 --ip $(VM_IP) --user-data bin/cloud-init.sh

build20:
	sudo docker build -t $(REPO)/$(IMAGE):$(VERSION) $(PLATFORM) --build-arg MAJOR_VERSION=20 --target ubuntu-20 .

build24:
	sudo docker buildx build -t $(REPO)/$(IMAGE):$(VERSION) $(PLATFORM) --build-arg MAJOR_VERSION=24  .

cm:
	sudo docker build -t $(REPO)/$(IMAGE):$(VERSION) -f Dockerfile.cmboot $(PLATFORM) --build-arg MAJOR_VERSION=24 .

k3s:
	sudo docker build -t $(REPO)/$(IMAGE):$(VERSION) -f Dockerfile.k3s $(PLATFORM) .

test:
	sudo docker build -t $(REPO)/$(IMAGE):$(VERSION) -f Dockerfile.test $(PLATFORM) .

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
