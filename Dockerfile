FROM softvisio/perl:latest

MAINTAINER admin@softvisio.net

USER root

ENV PATH="/var/local/pcore/bin:$PATH" \
    PERL5LIB="/var/local/pcore/lib/" \
    PCORE_LIB="/var/local/"

ADD . /var/local/pcore/

WORKDIR /var/local/pcore/

# --develop
RUN perl bin/pcore deploy --recommends --suggests \
    && pcore test -j $(nproc) \
    && rm -rf ~/.cpanm

VOLUME ["/var/local/resources/share/"]
