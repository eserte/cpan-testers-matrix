#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use FindBin;
use lib "$FindBin::RealBin/../lib";

use Test::More 'no_plan';

use CPAN::Testers::Matrix::Opensearch ();

is CPAN::Testers::Matrix::Opensearch::opensearch_xml("http://www.example.com"), <<'EOF';
<?xml version="1.0" encoding="UTF-8" ?>
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
  <ShortName>CPAN Testers Matrix</ShortName>
  <Description>Show CPAN Tester results</Description>
  <InputEncoding>us-ascii</InputEncoding>
  <OutputEncoding>us-ascii</OutputEncoding>
  <Image height="16" width="16" type="image/x-icon">cpantesters_favicon.ico</Image>
  <Url type="text/html" template="http://www.example.com/?dist={searchTerms}" />
  <Url type="application/x-suggestions+json" template="http://www.example.com/cpantestersmatrix_suggest.pl?q={searchTerms}"/>
  <Tags>CPAN Perl</Tags>
</OpenSearchDescription>
EOF

__END__
