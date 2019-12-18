FROM centos:latest

LABEL maintainer="zdm <zdm@softvisio.net>"

USER root

ENV TZ=UTC \
    PERL_VERSION="5.30.1" \
    WORKSPACE="/var/local" \
    DIST_PATH="/var/local/pcore"

ENV PATH="$DIST_PATH/bin:$PATH" \
    PERL5LIB="$DIST_PATH/lib"

ADD . $DIST_PATH

WORKDIR $DIST_PATH

SHELL [ "/bin/bash", "-l", "-c" ]

ONBUILD SHELL [ "/bin/bash", "-l", "-c" ]

RUN \
    # setup host
    source <( curl -fsSL https://bitbucket.org/softvisio/scripts/raw/master/setup-host.sh ) \
    \
    # setup perl build env
    && curl -fsSL https://bitbucket.org/softvisio/scripts/raw/master/perl-build-env.sh | /bin/bash -s -- setup \
    \
    # install && update perl
    && dnf -y install plenv perl-$PERL_VERSION \
    && plenv global perl-$PERL_VERSION \
    \
    # deploy pcore, --devel ???
    && perl bin/pcore deploy --recommends --suggests \
    && pcore test -j $(nproc) \
    \
    # cleanup perl build env
    && curl -fsSL https://bitbucket.org/softvisio/scripts/raw/master/perl-build-env.sh | /bin/bash -s -- cleanup

ENTRYPOINT [ "/bin/bash", "-l" ]
