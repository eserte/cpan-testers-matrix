#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use FindBin;
use lib "$FindBin::RealBin/../lib";

use File::Temp qw(tempfile);
use Test::More 'no_plan';

use CPAN::Testers::Matrix::Suggest ();

diag "Creating folded CPAN distname list, this may take a while...";
my($tmpfh,$tmpfile) = tempfile(SUFFIX => '.txt', UNLINK => 1);
{
    open my $fh, "-|", $^X, "$FindBin::RealBin/../bin/create-folded-distname-list.pl" or die $!;
    local $/ = \4096;
    while(<$fh>) {
	print $tmpfh $_;
    }
    close $fh
	or die "While running create-folded-distname-list.pl: $!";
}
close $tmpfh
    or die "While writing to temporary file: $!";

my $s = CPAN::Testers::Matrix::Suggest->new;
$s->{dist_file} = $tmpfile;
isa_ok $s, 'CPAN::Testers::Matrix::Suggest';

is $s->do_suggest("Kwalif")."\n", <<'EOF';
["Kwalif",["Kwalify"]]
EOF

is $s->do_suggest("XXXThisReallyDoesNotExist")."\n", <<'EOF';
["XXXThisReallyDoesNotExist",[]]
EOF

__END__
