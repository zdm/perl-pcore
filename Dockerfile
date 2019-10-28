FROM centos:latest

LABEL maintainer="zdm <zdm@softvisio.net>"

USER root

ENV TZ=UTC \
    PERL_VERSION="5.30.0" \
    PERL_CPANM_OPT="--metacpan --from https://cpan.metacpan.org/" \
    PERL_CPANM_HOME=/tmp/.cpanm \
    PCORE_LIB="/var/local" \
    DIST_PATH="/var/local/pcore"

ENV PATH="$DIST_PATH/bin:/usr/perlbrew/perls/perl-$PERL_VERSION/bin:$PATH" \
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
    && dnf -y install perl-$PERL_VERSION \
    && source <( curl -fsSL https://bitbucket.org/softvisio/scripts/raw/master/perl-modules.sh || echo false ) \
    # && cpan-outdated | cpanm \
    \
    # deploy pcore, --devel ???
    && perl bin/pcore deploy --recommends --suggests \
    && pcore test -j $(nproc) \
    \
    # cleanup perl build env
    && source <( curl -fsSL https://bitbucket.org/softvisio/scripts/raw/master/perl-build-env.sh || echo false ) cleanup \
'
