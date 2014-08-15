#!/usr/bin/perl -T
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2014 Slaven Rezic. All rights reserved.
# This package is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

package CPAN::Testers::Matrix::Opensearch;

use strict;
use vars qw($VERSION);
$VERSION = '0.01';

my $ct = 'application/xml';

sub opensearch_xml {
    my $root_url = shift;
    my $suggest_url = $root_url . '/cpantestersmatrix_suggest.pl';

    <<EOF;
<?xml version="1.0" encoding="UTF-8" ?>
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
  <ShortName>CPAN Testers Matrix</ShortName>
  <Description>Show CPAN Tester results</Description>
  <InputEncoding>us-ascii</InputEncoding>
  <OutputEncoding>us-ascii</OutputEncoding>
  <Image height="16" width="16" type="image/x-icon">cpantesters_favicon.ico</Image>
  <Url type="text/html" template="$root_url/?dist={searchTerms}" />
  <Url type="application/x-suggestions+json" template="$suggest_url?q={searchTerms}"/>
  <Tags>CPAN Perl</Tags>
</OpenSearchDescription>
EOF
}

sub psgi {
    require Plack::Request;
    return sub {
	my $env = shift;
	my $req = Plack::Request->new($env);
	my $uri = $req->uri;
	my $root_url = $uri->scheme . '://' . $uri->host_port;
	return [ 200, ['Content-Type' => $ct], [opensearch_xml($root_url)] ];
    };
}

return 1 if caller;

require CGI;
my $q = CGI->new;
my $root_url = $q->url('-base' => 1);
print $q->header($ct);
print opensearch_xml($root_url);

__END__
