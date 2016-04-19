FROM softvisio/perl:v5.22.1

MAINTAINER admin@softvisio.net

USER root

ENV DIST_NAME="pcore" \
    PCORE_LIB="/var/local"

ENV DIST_PATH="$PCORE_LIB/$DIST_NAME"

ENV PATH="$DIST_PATH/bin:$PATH" \
    PERL5LIB="$DIST_PATH/lib"

ADD . $DIST_PATH

WORKDIR $DIST_PATH

# --develop
RUN cpanm --with-feature linux --with-recommends --with-suggests --installdeps . \
    && perl bin/pcore deploy --recommends --suggests \
    && pcore test -j $(nproc) \
    && rm -rf ~/.cpanm

VOLUME ["$DIST_PATH/data/", "$DIST_PATH/log/"]
