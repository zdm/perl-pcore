FROM softvisio/perl:v5.26.1

LABEL maintainer="zdm <zdm@softvisio.net>"

USER root

ENV PCORE_LIB="/var/local" \
    DIST_PATH="/var/local/pcore" \
    PATH="/var/local/pcore/bin:$PATH" \
    PERL5LIB="/var/local/pcore/lib"

ADD . $DIST_PATH

WORKDIR $DIST_PATH

# --develop
RUN /bin/bash -c ' \

    # setup build environment
    source <( wget -q -O - https://bitbucket.org/softvisio/scripts/raw/tip/build-env-setup.sh ) \

    # update perl packages
    && source <( wget -q -O - https://bitbucket.org/softvisio/scripts/raw/tip/install-perl-exclusions.sh ) \
    && cpan-outdated | cpanm \

    # deploy pcore
    && cpanm --with-feature linux --with-recommends --with-suggests --installdeps . \
    && perl bin/pcore deploy --recommends --suggests \
    && pcore test -j $(nproc) \

    # cleanup build environment
    && source <( wget -q -O - https://bitbucket.org/softvisio/scripts/raw/tip/build-env-cleanup.sh ) \
'
