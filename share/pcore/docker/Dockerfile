FROM <: $dockerhub_pcore_repo_id | raw :>:latest

LABEL maintainer="<: $author | raw :>"

USER root

ENV DIST_PATH="$PCORE_LIB/<: $dist_path :>"

ADD . $DIST_PATH

WORKDIR $DIST_PATH

RUN /bin/bash -c ' \

    # setup build environment
    source <( wget -q -O - https://bitbucket.org/softvisio/scripts/raw/tip/build-env-setup.sh ) \

    # deploy project
    && pcore deploy --recommends --suggests \
    && pcore test -j $(nproc) \

    # cleanup build environment
    && source <( wget -q -O - https://bitbucket.org/softvisio/scripts/raw/tip/build-env-cleanup.sh ) \
'

ENTRYPOINT ["bin/main.pl"]
