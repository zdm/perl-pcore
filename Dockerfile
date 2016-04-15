FROM softvisio/perl:v5.22.1

MAINTAINER admin@softvisio.net

USER root

ENV DIST_NAME="pcore" \
    PCORE_LIB="/var/local"

ENV PATH="$PCORE_LIB/$DIST_NAME/bin:$PATH" \
    PERL5LIB="$PCORE_LIB/$DIST_NAME/lib"

ADD . $PCORE_LIB/$DIST_NAME/

WORKDIR $PCORE_LIB/$DIST_NAME/

# --develop
RUN perl bin/pcore deploy --recommends --suggests \
    && pcore test -j $(nproc) \
    && rm -rf ~/.cpanm

VOLUME ["$PCORE_LIB/$DIST_NAME/"]
