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
