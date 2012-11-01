#!/usr/bin/perl -w
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2012 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

use strict;
use Getopt::Long;
use JSON::XS;

my $o_dir;
GetOptions("o=s" => \$o_dir)
    or die "usage: $0 -o output_directory log.txt\n";
$o_dir
    or die "Please specify -o option (destination directory for the .json files)\n";
my $tail_log = shift
    or die "Please provide path to log.txt\n";

my %distinfo;

open my $fh, $tail_log
    or die "Can't open $tail_log: $!";
while(<$fh>) {
    chomp;
    next if /^The last \d+ reports/;
    if (my($date1, $author, $status, $distpath, $archname, $perl, $guid, $date2) = $_ =~
	m{^\[(.*?)\] \[(.*?)\] \[(.*?)\] \[(.*?)\] \[(.*?)\] \[(.*?)\] \[(.*?)\] \[(.*?)\]$}) {
	# I need:
	# - status
	# - platform
	# - guid
	# - version
	# - dist
	my $osname;
	if ($archname =~ m{\b(linux|openbsd|netbsd|solaris|freebsd|MSWin32|darwin|dragonfly|cygwin|mirbsd)\b}) {
	    $osname = lc $1
	} else {
	    warn "Cannot parse OS out of '$archname'\n";
	}
	# example: perl-v5.14.2
	$perl =~ s{^perl-v}{};
	# example: AVENJ/MooX-Role-Pluggable-0.01.tar.gz
	# XXX use DistnameInfo or so?
	if (my($dist, $version) = $distpath =~ m{^.+/(.*)-v?(\d.*)\.(?:tar\.gz|zip|tar\.bz2|tgz)$}) {
	    push @{ $distinfo{$dist} }, {
					 status => uc($status),
					 osname => $osname,
					 guid => $guid,
					 version => $version,
					 distribution => $dist,
					 perl => $perl,
					 id => "dummy",
					 archname => $archname,
					};
	} else {
	    warn "Cannot parse dist '$distpath'\n";
	}
    } else {
	warn "Can't parse line '$_'\n";
    }
}

while(my($dist,$v) = each %distinfo) {
    if ($dist !~ m{^[a-zA-Z0-9_-]+$}) {
	warn "Skipping possibly problematic filename '$dist'...\n";
    } else {
	my $o_file = $o_dir . "/$dist.json";
	print STDERR "$o_file...\n";
	open my $ofh, ">", $o_file
	    or die "Can't write to $o_file: $!";
	print $ofh encode_json $v;
	close $ofh
	    or die $!;
    }
}

__END__
