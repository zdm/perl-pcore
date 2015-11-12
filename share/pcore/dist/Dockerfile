FROM <: $dockerhub_username :>/pcore:latest

MAINTAINER <: $author_email :>

USER root

ADD . /var/local/<: $dist_path :>/

WORKDIR /var/local/<: $dist_path :>/

RUN pcore deploy --recommends --suggests \
    && pcore test -j $(nproc) \
    && pcore clean \
    && rm -rf ~/.cpanm

VOLUME ["/var/local/<: $dist_path :>/data/", "/var/local/<: $dist_path :>/log/"]

ENTRYPOINT ["/var/local/<: $dist_path :>/bin/<: $main_script :>"]
