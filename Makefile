.PHONY: k3s

REPO=ksuderman
IMAGE=galaxy-k8s-boot
VERSION=$(shell cat VERSION)
VM_NAME=dev
VM_IP=$(shell cluster ip $(VM_NAME))
PLATFORM=--platform linux/amd64
MAJOR_VERSION=20

all: build push

vm: instance

instance:
	os launch ks-$(VM_NAME) --cores 16 --disk 512 --ip $(VM_IP) --user-data bin/cloud-init.sh

build20:
	docker build -t $(REPO)/$(IMAGE):$(VERSION) $(PLATFORM) --build-arg MAJOR_VERSION=20 --target ubuntu-20 .

build24:
	docker build -t $(REPO)/$(IMAGE):$(VERSION) $(PLATFORM) --build-arg MAJOR_VERSION=24 --target ubuntu-24 .

cm:
	docker build -t $(REPO)/$(IMAGE):$(VERSION) -f Dockerfile.cmboot $(PLATFORM) --build-arg MAJOR_VERSION=$MAJOR_VERSION .

k3s:
	docker build -t $(REPO)/$(IMAGE):$(VERSION) -f Dockerfile.k3s $(PLATFORM) .

test:
	docker build -t $(REPO)/$(IMAGE):$(VERSION) -f Dockerfile.test $(PLATFORM) .

push:
	docker push $(REPO)/$(IMAGE):$(VERSION)

run:
	docker run -it $(REPO)/$(IMAGE):$(VERSION) bash

pull:
	git pull origin $(shell git branch --show-current)

env:
	python3 -m venv .venv
	. .venv/bin/activate
	pip install -r requirements.txt

clean:
	docker rmi --force $(REPO)/$(IMAGE):$(VERSION)

clean-all:
	docker rmi --force $(shell docker images -q)
