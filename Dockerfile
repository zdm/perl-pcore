FROM softvisio/perl:v5.26.2

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

    # setup perl build env
    source <( wget -q -O - https://bitbucket.org/softvisio/scripts/raw/tip/perl-build-env.sh || echo false ) setup \

	&& cpanm -v PathTools \

    # update perl packages
    && source <( wget -q -O - https://bitbucket.org/softvisio/scripts/raw/tip/perl-exclusions-install.sh || echo false ) \
    && cpan-outdated | cpanm \

    # deploy pcore
    && cpanm --with-feature linux --with-recommends --with-suggests --installdeps . \
    && perl bin/pcore deploy --recommends --suggests \
    && pcore test -j $(nproc) \

    # cleanup perl build env
    && source <( wget -q -O - https://bitbucket.org/softvisio/scripts/raw/tip/perl-build-env.sh || echo false ) cleanup \
'
