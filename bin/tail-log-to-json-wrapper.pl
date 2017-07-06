#!/usr/bin/perl -w
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2016,2017 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

use strict;

system("wget", "-O", "/tmp/log.txt~", "http://metabase.cpantesters.org/tail/log.txt?" . time);
die "Getting log.txt failed" if $? != 0;
rename "/tmp/log.txt~", "/tmp/log.txt" or die $!;
system("/home/eserte/src/CPAN/CPAN-Testers-Matrix/bin/tail-log-to-json.pl", "-o", "/var/tmp/metabase-log/log-as-json", "-logfile", "/tmp/log.log", "-statusfile", "/tmp/statusfile", "/tmp/log.txt", "-no-seek");
die if $? != 0;

__END__

=head1 SETUP

Create directory:

    mkdir -p /var/tmp/metabase-log/log-as-json

Setup cron job:

    2,7,12,17,22,27,32,37,42,47,52,57 * * * * $HOME/bin/sh/cron-wrapper $HOME/src/CPAN/CPAN-Testers-Matrix/bin/tail-log-to-json-wrapper.pl

(L<http://metabase.cpantesters.org/tail/log.txt> is currently modified
about 80s after minute 0,5,10,...)

(If you don't have C<cron-wrapper>, then just run without and redirect
everything to F</dev/null>)

Create a cgi-bin/cpantestersmatrix.yml in the CPAN-Testers-Matrix
directory with the following content:

    static_dist_dir: /var/tmp/metabase-log/log-as-json
    cache_root: /tmp/cpantesters_fast_cache
    serializer: Sereal

(You can omit the serializer if Sereal is not available)

Run C<plackup> (or C<starman>) like this:

    plackup cpan-testers-matrix.psgi 

=cut
