#!/usr/bin/env bash

SERVER=${1:-dev}
DIR=$(dirname $0)

for f in run.sh runit.sh ; do
  cluster upload $SERVER $DIR/$f /home/ubuntu/$f
done

