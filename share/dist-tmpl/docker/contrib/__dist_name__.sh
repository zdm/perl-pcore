#!/bin/bash

# curl -fsSLO https://bitbucket.org/softvisio/<: $dist_path :>/raw/master/contrib/<: $dist_path :>.sh && chmod +x <: $dist_path :>.sh

set -e

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"

TAG=latest
NAME=<: $dockerhub_dist_repo_name :>
DOCKERHUB_NAMESPACE=<: $dockerhub_dist_repo_namespace :>
SERVICE=0

# Docker container restart policy, https://docs.docker.com/config/containers/start-containers-automatically/
# - no             - do not automatically restart the container. (the default);
# - on-failure     - restart the container if it exits due to an error, which manifests as a non-zero exit code;
# - unless-stopped - restart the container unless it is explicitly stopped or Docker itself is stopped or restarted;
# - always         - always restart the container if it stops;
RESTART=always

# Seconds to wait for stop before killing container, https://docs.docker.com/engine/reference/commandline/stop/#options
KILL_TIMEOUT=10

DOCKER_CONTAINER_ARGS="
    -v $SCRIPT_DIR:/var/local/$NAME/data \
    -p 80:80/tcp \
    -p 443:443/tcp \
    --shm-size=1g \
"

source <( curl -fsSL https://bitbucket.org/softvisio/scripts/raw/master/docker.sh || echo false ) "$@"
