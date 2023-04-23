FROM debian:jessie
LABEL maintainer "srezic@cpan.org"

RUN if grep -q "VERSION=.*jessie" /etc/os-release; then \
        echo "APT::Get::AllowUnauthenticated 1;" > /etc/apt/apt.conf.d/02allow-unsigned; \
        echo 'deb [check-valid-until=no] http://archive.debian.org/debian jessie main'                   >  /etc/apt/sources.list; \
        echo 'deb [check-valid-until=no] http://archive.debian.org/debian-security/ jessie/updates main' >> /etc/apt/sources.list; \
    fi

RUN apt-get update -qq
RUN apt-get install -qq git starman libcgi-pm-perl libcpan-distnameinfo-perl libgravatar-url-perl libhtml-table-perl libjson-xs-perl liburi-query-perl libversion-perl libwww-perl libyaml-syck-perl perl-modules
#RUN apt-get install -qq libkwalify-perl libparse-cpan-packages-fast-perl

RUN git clone --depth=1 https://github.com/eserte/cpan-testers-matrix.git
WORKDIR cpan-testers-matrix

# To write cpantesters_amendments.33.st, for example
RUN chown www-data data
# 33 is www-data on debian systems
USER 33
EXPOSE 5000
CMD starman --listen 0.0.0.0:5000 cpan-testers-matrix.psgi
