REPO=ksuderman
IMAGE=galaxy-k8s-boot
VERSION=$(shell cat VERSION)

all: build push

build:
	docker build -t $(REPO)/$(IMAGE):$(VERSION) .

cm:
	docker build -t $(REPO)/$(IMAGE):$(VERSION) -f Dockerfile.cmboot .

test:
	docker build -t $(REPO)/$(IMAGE):$(VERSION) -f Dockerfile.test .

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
