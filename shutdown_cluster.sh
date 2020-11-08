#!/bin/bash

ids="$(docker ps -aq --filter name=onos --filter name=atomix-)"
docker stop $ids
docker rm $ids