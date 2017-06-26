FROM debian:jessie
LABEL maintainer "srezic@cpan.org"

EXPOSE 80

RUN apt-get update -qq
RUN apt-get install -qq git starman libcgi-pm-perl libcpan-distnameinfo-perl libgravatar-url-perl libhtml-table-perl libjson-xs-perl liburi-query-perl libversion-perl libwww-perl libyaml-syck-perl perl-modules
#RUN apt-get install -qq libkwalify-perl libparse-cpan-packages-fast-perl

RUN git clone --depth=1 https://github.com/eserte/cpan-testers-matrix.git
WORKDIR cpan-testers-matrix

CMD starman --listen 0.0.0.0:80 cpan-testers-matrix.psgi
