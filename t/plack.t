#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use FindBin;

use Test::More 'no_plan';

use Cwd 'realpath';

use Plack::Test;
use Plack::Util;
use HTTP::Request::Common;

$FindBin::RealBin = realpath "$FindBin::RealBin/.."; # fake location of psgi

my @UA = ('User-Agent' => 'Plack-Test/0.01');

my $app = Plack::Util::load_psgi("$FindBin::RealBin/cpan-testers-matrix.psgi");
ok $app, 'can convert into psgi application';

test_psgi app => $app, client => sub {
    my $cb = shift;
    {
	my $res = $cb->(GET "/", @UA);
	ok $res->is_success, 'get index page'
	    or diag $res->as_string;
	like $res->decoded_content, qr{<title>CPAN Testers Matrix}, 'found html title';
    }

    {
	my $res = $cb->(GET "/?dist=Kwalify", @UA);
	ok $res->is_success, 'get kwalify results'
	    or diag $res->as_string;
	my $content = $res->decoded_content;
	like $content, qr{<title>CPAN Testers Matrix: Kwalify}, 'found module headline';
	like $content, qr{linux}i, 'found a popular OS';
	like $content, qr{5\.18\.4}, 'found a perl version';
    }

    for my $icofile ('/favicon.ico', '/cpantesters_favicon.ico') {
	my $res = $cb->(GET $icofile, @UA);
	ok $res->is_success, "get $icofile"
	    or diag $res->as_string;
    SKIP: {
	    skip 'needs Image::Info 1.31', 1
		if !eval { require Image::Info; Image::Info->VERSION(1.31); 1 };
	    my $img_info = Image::Info::image_info(\$res->decoded_content);
	    is $img_info->{file_ext}, 'ico';
	}
    }

    for my $staticfile ('jquery-1.9.1.min.js', 'jquery.tablesorter.min.js', 'matrix_cpantesters.js') {
	my $res = $cb->(GET $staticfile, @UA);
	ok $res->is_success, "get static file $staticfile"
	    or diag $res->as_string;
    }

    my $res = $cb->(GET '/robots.txt', @UA);
    ok $res->is_success, "get robots.txt"
	or diag $res->as_string;
    is $res->decoded_content, <<EOF;
User-agent: *
Disallow: /
EOF

    {
	my $res = $cb->(GET '/not-found', @UA);
	is $res->code, 404, '404 as expected';
    }
};

__END__
