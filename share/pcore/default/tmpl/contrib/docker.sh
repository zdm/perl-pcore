#!/bin/bash

set -e

SCRIPT_DIR="$(cd -P -- "$(dirname -- "$0")" && pwd -P)"

NAME=<: $dist_path :>
IMAGE=<: $dockerhub_username :>/${NAME}
TAG=latest
KILL_TIMEOUT=10
DOCKER_CONTAINER_ARGS="
    -v $SCRIPT_DIR/:/var/local/$NAME/data/ \
    -v $SCRIPT_DIR/log/:/var/local/$NAME/log/ \
    -v $SCRIPT_DIR/resources/:/var/local/resources/
"

# INTERNAL FUNCTIONS
function _is_docker_exists () {
    if [ -x "$(command -v docker)" ]; then
        true
    else
        false
    fi
}

function _is_systemctl_exists () {
    if [ -x "$(command -v systemctl)" ]; then
        true
    else
        false
    fi
}

function _is_service_installed () {
    if _is_systemctl_exists; then
        local IS_EXISTS=$( systemctl list-unit-files | grep $SERVICE_NAME )

        if [ -z "$IS_EXISTS" ]; then
            false
        else
            true
        fi
    else
        false
    fi
}

function _is_service_started () {
    if _is_systemctl_exists; then
        local IS_EXISTS=$( systemctl status $SERVICE_NAME | grep "Active: active (running)" )

        if [ -z "$IS_EXISTS" ]; then
            false
        else
            true
        fi
    else
        false
    fi
}

function _has_image () {
    local IMAGE_EXISTS=$( docker images | grep "^$IMAGE" | awk "{print \$3}" )

    if [ -z "$IMAGE_EXISTS" ]; then
        false
    else
        true
    fi
}

function _has_container () {
    docker inspect $NAME >/dev/null 2>&1

    local EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        true
    else
        false
    fi
}

function _is_container_started () {
    local STARTED=$(docker inspect --format="{{ .State.Running }}" $NAME 2>/dev/null)

    if [ "$STARTED" == "true" ]; then
        true
    else
        false
    fi
}

function _create_container () {
    docker create --name $NAME --hostname $NAME.$(hostname) $DOCKER_CONTAINER_ARGS $IMAGE:$TAG >/dev/null

    printf "Status: container has been \033[1;32mcreated\033[0m\n"
}

function _remove_container () {
    docker rm $NAME >/dev/null 2>&1 || true

    printf "Status: container has been \033[1;31mremoved\033[0m\n"
}

function _remove_image () {
    docker rmi $IMAGE:$TAG 2>&1 || true

    printf "Status: image has been \033[1;31mremoved\033[0m\n"
}

function _report_ok () {
    printf "%-25s" "$1:"

    printf "[ \033[1;32m YES \033[0m ]\n"
}

function _report_failure () {
    printf "%-25s" "$1:"

    printf "[ \033[1;31m  NO \033[0m ]\n"
}

# COMMANDS
function _pull () {
    docker pull $IMAGE:$TAG
}

function _update () {
    _pull

    local WAS_STARTED=

    if _is_container_started; then
        WAS_STARTED=1
    else
        WAS_STARTED=0
    fi

    _stop

    _remove_container

    _create_container

    if [ $WAS_STARTED == "1" ]; then
        _start
    fi
}

function _clean () {
    _stop

    _remove

    _remove_container

    _remove_image
}

function _status () {
    echo
    echo "Image name:              $IMAGE:$TAG"
    echo "Container name:          $NAME"
    echo "Service name:            $SERVICE_NAME"
    echo

    if _has_image; then
        _report_ok "Image is present"
    else
        _report_failure "Image is present"
    fi

    if _has_container; then
        _report_ok "Container is present"
    else
        _report_failure "Container is present"
    fi

    echo

    if _is_container_started; then
        _report_ok "Container is started"
    else
        _report_failure "Container is started"
    fi

    echo

    if _is_service_installed; then
        _report_ok "Service is installed"

        if _is_service_started; then
            _report_ok "Service is started"
        else
            _report_failure "Service is started"
        fi
    else
        _report_failure "Service is installed"

        _report_failure "Service is started"
    fi

    echo
}

function _start () {
    if ! _has_image; then
        _pull
    fi

    if ! _has_container; then
        _create_container
    fi

    if ! _is_container_started; then
        if _is_service_installed; then
            systemctl start $SERVICE_NAME 2>/dev/null

            printf "Status: service has been \033[1;32mstarted\033[0m\n"
        else
            docker start $NAME >/dev/null

            printf "Status: container has been \033[1;32mstarted\033[0m\n"
        fi
    fi
}

function _stop () {
    if _has_container; then
        if _is_container_started; then
            if _is_service_started; then
                systemctl stop $SERVICE_NAME 2>/dev/null || true

                printf "Status: service has been \033[1;31mstopped\033[0m\n"
            else
                docker stop -t $KILL_TIMEOUT $NAME >/dev/null 2>&1 || true

                printf "Status: container has been \033[1;31mstopped\033[0m\n"
            fi
        fi
    fi
}

function _restart () {
    _stop

    _start
}

function _run () {
    if ! _has_image; then
        _pull
    fi

    docker run -it --rm --hostname $NAME.$(hostname) --entrypoint bash $DOCKER_CONTAINER_ARGS $IMAGE:$TAG
}

function _install () {
    if _is_systemctl_exists; then
        if ! _has_image; then
            _pull
        fi

        if ! _has_container; then
            _create_container
        fi

        local DOCKER_PATH=$(command -v docker)

        cat <<EOF > /etc/systemd/system/${SERVICE_NAME}.service
[Unit]
Description=Docker container $NAME
After=docker.service
Requires=docker.service

[Service]
Restart=always
ExecStart=$DOCKER_PATH start -a $NAME
ExecStop=$DOCKER_PATH stop -t $KILL_TIMEOUT $NAME

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload

        systemctl enable ${SERVICE_NAME}.service 2>/dev/null

        printf "Status: service has been \033[1;32minstalled\033[0m and \033[1;32menabled\033[0m\n"
    fi
}

function _remove () {
    if _is_systemctl_exists && _is_service_installed; then
        if _is_service_started; then
            _stop
        fi

        systemctl disable ${SERVICE_NAME}.service 2>/dev/null

        rm -f /etc/systemd/system/${SERVICE_NAME}.service || true

        systemctl daemon-reload

        printf "Status: service has been \033[1;31mdisabled\033[0m and \033[1;31mremoved\033[0m\n"
    fi
}

function _usage () {
    cat <<EOF

$NAME docker management script

Usage: $0 <command>

Commands:
    pull     pull latest image
    update   pull latest image, create container and restart, if container was started
    clean    stop everything, remove service, container and image
    status   print status
    start    pull image and create container, if not exists, start contatiner / service
    stop     stop running container / service
    restart  restart running container / service
    run      run container with bash entry point
    install  install and enable systemd service
    remove   stop container / service, remove systemd service

EOF
}

function _init () {
    if ! _is_docker_exists; then
        printf "Status: \033[1;31mdocker is not installed\033[0m\n"

        exit
    fi

    SERVICE_NAME=docker-$NAME
}

_init

case $1 in
    pull)
        _pull
    ;;
    update)
        _update
    ;;
    clean)
        _clean
    ;;
    status)
        _status
    ;;
    start)
        _start
    ;;
    stop)
        _stop
    ;;
    restart)
        _restart
    ;;
    run)
        _run
    ;;
    install)
        _install
    ;;
    remove)
        _remove
    ;;

    *)
        _usage
    ;;
esac
