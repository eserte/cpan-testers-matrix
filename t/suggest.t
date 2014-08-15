#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use FindBin;
use lib "$FindBin::RealBin/../lib";

use Test::More 'no_plan';

use CPAN::Testers::Matrix::Suggest ();

is CPAN::Testers::Matrix::Suggest::do_suggest("Kwalif")."\n", <<'EOF';
["Kwalif",["Kwalify"]]
EOF

is CPAN::Testers::Matrix::Suggest::do_suggest("XXXThisReallyDoesNotExist")."\n", <<'EOF';
["XXXThisReallyDoesNotExist",[]]
EOF

__END__
