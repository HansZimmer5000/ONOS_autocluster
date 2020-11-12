#!/bin/bash

set -x

create_networks(){
    for i in {0..2}; do
        docker network create test$i
    done
}

open_terminals(){
    ../target_term -set 3
}

start_container(){
    for i in {0..2}; do
        echo "Starting test$i"
        ../target_term -run $i docker run -it --rm --net test0 --hostname con$i --name con$i --entrypoint bash atomix/atomix:3.1.5
        sleep 1s
        docker network connect test1 con$i
        docker network connect test2 con$i
        sleep 1s
        ../target_term -run $i hostname -I
    done
}

shutdown_container(){
    docker stop $(docker ps -aq)
    docker rm $(docker ps -aq)
    sleep 1s
}

close_terminals(){
    for i in {0..2}; do
        ../target_term -close $i
        sleep 0.2s
    done
    echo "" > ../.term_list
} 

delete_network(){
    for i in {0..2}; do
        docker network rm test$i
    done
}

create_networks
open_terminals
start_container

read -p "Ready for cleanup?"
shutdown_container
close_terminals

set +x