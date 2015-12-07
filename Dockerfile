FROM softvisio/perl:latest

MAINTAINER admin@softvisio.net

USER root

ENV PERL5LIB="/var/local/pcore/lib/" \
    PATH="/var/local/pcore/bin:$PATH" \
    PCORE_DIST_LIB="/var/local/" \
    PCORE_RES_LIB="/var/local/resources/"

# TODO
# automated build ignore .dockerignore
# https://github.com/docker/docker/issues/9455
ADD . /var/local/pcore/

# ADD bin/ /var/local/pcore/bin/
# ADD contrib/ /var/local/pcore/contrib/
# ADD lib/ /var/local/pcore/lib/
# ADD share/ /var/local/pcore/share/
# ADD t/ /var/local/pcore/t/
# ADD xt/ /var/local/pcore/xt/
# ADD cpanfile /var/local/pcore/
# ADD CHANGES /var/local/pcore/
# ADD LICENSE /var/local/pcore/
# ADD README.md /var/local/pcore/
# ADD Build.PL /var/local/pcore/

WORKDIR /var/local/pcore/

# --develop
RUN perl bin/pcore deploy --recommends --suggests \
    && pcore test -j $(nproc) \
    && pcore clean \
    && rm -rf ~/.cpanm

VOLUME ["/var/local/resources/share/"]
