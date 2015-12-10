FROM softvisio/perl:latest

MAINTAINER admin@softvisio.net

USER root

ENV PERL5LIB="/var/local/pcore/lib/" \
    PATH="/var/local/pcore/bin:$PATH" \
    PCORE_DIST_LIB="/var/local/" \
    PCORE_RES_LIB="/var/local/resources/"

ADD . /var/local/pcore/

WORKDIR /var/local/pcore/

# --develop
RUN perl bin/pcore deploy --recommends --suggests \
    && pcore test -j $(nproc) \
    && rm -rf ~/.cpanm

VOLUME ["/var/local/resources/share/"]
