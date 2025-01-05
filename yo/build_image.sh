#!/bin/bash
this_f=$(readlink -f "$0")
this_d=$(dirname "$this_f")
source $this_d/func.sh

cmd_runs="$1"
DOCKER_DIR="docker/ubuntu_18_04"
CONTAINER_NAME="ubuntu_18_04"
cmd_init="cd /mnt/docker/ubuntu_18_04; MACHINE=$YO_M; source ./setup-environment build"

start_cmd_docker "${cmd_init}; ${cmd_runs}"
