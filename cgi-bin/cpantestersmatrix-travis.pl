#!/usr/bin/env perl
# -*- perl -*-

# May be used to run cpantestersmatrix with another perl. Used like this:
#
#    cd .../cpan-testers-matrix
#    TRAVIS=1 PATH=/opt/perl-X.Y.Z/bin:$PATH pistachio-perl -S starman cpan-testers-matrix.psgi

use strict;
no warnings;
use FindBin;
exec $^X, "-T", "$FindBin::RealBin/cpantestersmatrix.pl", @ARGV;
die $! if $!;
