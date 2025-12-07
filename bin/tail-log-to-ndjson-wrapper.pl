#!/usr/bin/perl -w
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2023,2025 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# WWW:  https://github.com/eserte/cpan-testers-matrix/
#

use strict;
use FindBin;

my $fetch_url = "http://metabase.cpantesters.org/tail/log.txt?" . time;
my $output_file = "/tmp/ndjson-log.txt";
#system("wget", "-O", "$output_file~", $fetch_url);
system('curl', '-L', '--silent', '--compressed', '--fail', '--output', "$output_file~", $fetch_url);
die "Getting ${output_file}~ failed" if $? != 0;
rename "$output_file~", $output_file or die $!;
system("$FindBin::RealBin/tail-log-to-ndjson.pl", "--ndjson-dir", "/var/tmp/metabase-log/tail-log-as-ndjson", "--json-dir", "/var/tmp/metabase-log/log-as-json", "-logfile", "/tmp/ndjson-log.log", "-statusfile", "/tmp/ndjson-statusfile", $output_file);
die if $? != 0;

__END__

=head1 SETUP

Create directory:

    mkdir -p /var/tmp/metabase-log/tail-log-as-ndjson

Setup cron job:

    2,7,12,17,22,27,32,37,42,47,52,57 * * * * $HOME/bin/sh/cron-wrapper $HOME/src/CPAN/CPAN-Testers-Matrix/bin/tail-log-to-ndjson-wrapper.pl

(L<http://metabase.cpantesters.org/tail/log.txt> is currently modified
about 80s after minute 0,5,10,...)

(If you don't have C<cron-wrapper>, then just run without and redirect
everything to F</dev/null>)

Create a cgi-bin/cpantestersmatrix.yml in the CPAN-Testers-Matrix
directory with the following content:

    static_dist_dir: /var/tmp/metabase-log/tail-log-as-ndjson
    cache_root: /tmp/cpantesters_fast_cache
    serializer: Sereal
    filefmt_dist: ndjson

(You can omit the serializer if Sereal is not available)

Run C<plackup> (or C<starman>) like this:

    plackup cpan-testers-matrix.psgi 

=cut
