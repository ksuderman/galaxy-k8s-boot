REPO=ksuderman
IMAGE=galaxy-k8s-boot
VERSION=$(shell cat VERSION)

all: build push

build:
	docker build -t $(REPO)/$(IMAGE):$(VERSION) .

cm:
	docker build -t $(REPO)/$(IMAGE):$(VERSION) -f Dockerfile.cmboot .

push:
	docker push $(REPO)/$(IMAGE):$(VERSION)

run:
	docker run -it $(REPO)/$(IMAGE):$(VERSION) bash

clean:
	docker rmi --force $(REPO)/$(IMAGE):$(VERSION)

clean-all:
	docker rmi --force $(shell docker images -q)
