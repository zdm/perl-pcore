FROM centos:latest

LABEL maintainer="zdm <zdm@softvisio.net>"

USER root

ENV TZ=UTC \
    PERL_VERSION="5.30.1" \
    PCORE_LIB="/var/local" \
    DIST_PATH="/var/local/pcore"

ENV PATH="$DIST_PATH/bin:$PATH" \
    PERL5LIB="$DIST_PATH/lib"

ADD . $DIST_PATH

WORKDIR $DIST_PATH

RUN /bin/bash -c ' \
    \
    # setup host
    source <( curl -fsSL https://bitbucket.org/softvisio/scripts/raw/master/setup-host.sh || echo false ) \
    \
    # setup perl build env
    && source <( curl -fsSL https://bitbucket.org/softvisio/scripts/raw/master/perl-build-env.sh || echo false ) setup \
    \
    # install && update perl
    && dnf -y install plenv perl-$PERL_VERSION \
    && plenv global perl-$PERL_VERSION \
    && source <( curl -fsSL https://bitbucket.org/softvisio/scripts/raw/master/perl-modules.sh || echo false ) \
    \
    # deploy pcore, --devel ???
    && perl bin/pcore deploy --recommends --suggests \
    && pcore test -j $(nproc) \
    \
    # cleanup perl build env
    && source <( curl -fsSL https://bitbucket.org/softvisio/scripts/raw/master/perl-build-env.sh || echo false ) cleanup \
'
