REPO=ksuderman
IMAGE=galaxy-k8s-boot
VERSION=$(shell cat VERSION)

all: build push

build:
	docker build -t $(REPO)/$(IMAGE):$(VERSION) .

push:
	docker push $(REPO)/$(IMAGE):$(VERSION)

run:
	docker run -it $(REPO)/$(IMAGE):$(VERSION) bash

clean:
	docker rmi $(REPO)/$(IMAGE):$(VERSION)
