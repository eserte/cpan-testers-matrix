#!/usr/bin/perl

use strict;
use warnings;
use FindBin;
use lib "$FindBin::RealBin/../cgi-bin";

use Test::More 'no_plan';

require "cpantestersmatrix.pl";

ok defined &CPAN::Testers::Matrix::obfuscate_from;
*obfuscate_from = \&CPAN::Testers::Matrix::obfuscate_from;

is obfuscate_from('"" <somebody@cpan.com>'), 'somebody at cpan';
is obfuscate_from('"" <somebody@yahoo.co.jp>'), 'somebody at yahoo';
is obfuscate_from('"Some Body" <somebody@example.org>'), 'Some Body';
is obfuscate_from('"Some Body (SBODY)" <root@example.net ((root))>'), 'SBODY';
is obfuscate_from('"S&ouml;me Body (SBODY)" <root@example.org>'), 'SBODY';
is obfuscate_from('"Some Bodi&#x107; (SBODY)" <root@example.org>'), 'SBODY';
is obfuscate_from('"somebody" <somebody@example.org>'), 'somebody';

__END__
