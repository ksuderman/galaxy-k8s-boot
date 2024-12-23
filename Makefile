REPO=ksuderman
IMAGE=galaxy-k8s-boot
VERSION=$(shell cat VERSION)
VM_NAME=dev
VM_IP=$(shell cluster ip $(VM_NAME))
PLATFORM="--platform linux/amd64"

all: build push

echo:
	echo "IP $(VM_IP)"
	echo "Version: $(VERSION)"

build:
	docker build -t $(REPO)/$(IMAGE):$(VERSION) $(PLATFORM) .

cm:
	docker build -t $(REPO)/$(IMAGE):$(VERSION) -f Dockerfile.cmboot $(PLATFORM) .

test:
	docker build -t $(REPO)/$(IMAGE):$(VERSION) -f Dockerfile.test $(PLATFORM) .

push:
	docker push $(REPO)/$(IMAGE):$(VERSION)

run:
	docker run -it $(REPO)/$(IMAGE):$(VERSION) bash

env:
	python3 -m venv .venv
	. .venv/bin/activate
	pip install -r requirements.txt

clean:
	docker rmi --force $(REPO)/$(IMAGE):$(VERSION)

clean-all:
	docker rmi --force $(shell docker images -q)
