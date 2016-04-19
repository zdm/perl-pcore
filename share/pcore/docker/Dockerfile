FROM <: $pcore_dockerhub_namespace :>/pcore:latest

MAINTAINER <: $author :>

USER root

ENV DIST_NAME="<: $dist_path :>"

ENV DIST_PATH="$PCORE_LIB/$DIST_NAME"

ADD . $DIST_PATH

WORKDIR $DIST_PATH

RUN pcore deploy --recommends --suggests \
    && pcore test -j $(nproc) \
    && rm -rf ~/.cpanm

VOLUME ["$DIST_PATH/data/", "$DIST_PATH/log/"]

ENTRYPOINT ["bin/main.pl"]
