# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use FindBin;

use File::Glob qw(bsd_glob);
use File::Spec qw();
use Test::More 'no_plan';

my $rootdir = "$FindBin::RealBin/..";
chdir $rootdir or die $!;

my @files = (
	       bsd_glob("bin/*.pl"),
	       bsd_glob("cgi-bin/*.pl"),
	       bsd_glob("*.psgi"),
	      );

for my $f (@files) {
 SKIP: {
	skip "$f needs Doit", 1
	    if $f =~ /(merge-json-wrapper-doit.pl|setup-cpantestersmatrix-doit.pl)/ && !eval { require Doit; 1 };
	skip "$f needs JSON::XS", 1
	    if $f =~ /(tail-log-to-ndjson.pl|merge-json.pl)/ && !eval { require JSON::XS; 1 };
	skip "$f needs File::ReadBackwards", 1
	    if $f =~ /tail-log-to-ndjson.pl/ && !eval { require File::ReadBackwards; 1 };

	my @opts;
	if ($f =~ m{^cgi-bin/cpantestersmatrix(?:|2|-travis)\.pl$}) {
	    push @opts, '-T';
	}
	open my $OLDERR, ">&", \*STDERR or die;
	open STDERR, '>', File::Spec->devnull or die $!;
	my @cmd = ($^X, '-w', '-c', @opts, "./$f");
	system @cmd;
	close STDERR;
	open STDERR, ">&", $OLDERR or die;
	die "Signal caught" if $? & 0xff;

	is $?, 0, "Check @cmd";
    }
}
