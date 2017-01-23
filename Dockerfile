FROM softvisio/perl:v5.24.1

MAINTAINER zdm <zdm@softvisio.net>

USER root

ENV PCORE_LIB="/var/local" \
    DIST_PATH="/var/local/pcore" \
    PATH="/var/local/pcore/bin:$PATH" \
    PERL5LIB="/var/local/pcore/lib"

ADD . $DIST_PATH

WORKDIR $DIST_PATH

# --develop
RUN /bin/bash -c ' \
    cpan-outdated | cpanm \
    && cpanm --with-feature linux --with-recommends --with-suggests --installdeps . \
    && perl bin/pcore deploy --recommends --suggests \
    && pcore test -j $(nproc) \
    && rm -rf ~/.cpanm \
'
