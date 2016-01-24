FROM <: $dockerhub_username :>/pcore:latest

MAINTAINER <: $author_email :>

USER root

ENV DIST_NAME="<: $dist_path :>"

ADD . $PCORE_LIB/$DIST_NAME/

WORKDIR $PCORE_LIB/$DIST_NAME/

RUN pcore deploy --recommends --suggests \
    && pcore test -j $(nproc) \
    && rm -rf ~/.cpanm

ENTRYPOINT ["bin/main.pl"]
