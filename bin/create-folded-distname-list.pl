#!/usr/bin/perl -w
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2014 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

use strict;
use CPAN;
use CPAN::DistnameInfo;
use Getopt::Long;
use Parse::CPAN::Packages::Fast;

my $o;
GetOptions("o=s" => \$o)
    or die "usage: $0 [-o outfile]\n";

my $packages_file = Parse::CPAN::Packages::Fast->_default_packages_file_batch;
if (!$packages_file) {
    die "Can't continue: no default CPAN packages file found. Maybe you have to run CPAN.pm once?";
}

my %dists;
{
    my $overread_header = 1;
    open my $fh, "-|", "zcat", $packages_file or die $!;
    while(<$fh>) {
	if ($overread_header) {
	    if (/^$/) {
		$overread_header = 0;
	    }
	} else {
	    my $dist = (split /\s+/)[2];
	    $dist = CPAN::DistnameInfo->new($dist)->dist;
	    if (length $dist) {
		$dists{$dist} = 1;
	    }
	}
    }
}

my @dists = sort keys %dists;

my $ofh;
my $o_tmp = "$o.$$";
if (defined $o) {
    open $ofh, ">", $o_tmp
	or die "Can't write to $o_tmp: $!";
} else {
    $ofh = \*STDOUT;
}
print $ofh $_, "\n" for @dists;

if (defined $o) {
    close $ofh
	or die "Error writing to $o_tmp: $!";
    rename $o_tmp, $o
	or die "Error renaming $o_tmp to $o: $!";
}

__END__
