#!/usr/bin/perl -w
# -*- perl -*-

#
# Author: Slaven Rezic
#

use strict;
use FindBin;
use Test::More;

if ((getpwuid($<))[0] ne 'eserte' && !$ENV{PERL_AUTHOR_TEST}) {
    plan skip_all => 'Author tests only --- set PERL_AUTHOR_TEST to run';
    exit 0;
}

my @matrix_tests =
    (
     ['dist=Tk'],
     ['dist=Tk 804.027'],
     ['dist=JSON', 'maxver=1'],
     ['dist=Clarion'],
     ['author=srezic'],
     ['dist=Kwalify', 'reports=1', 'os=freebsd', 'perl=5.8.8'],
     ['dist=Kwalify 1.16', 'reports=1', 'os=freebsd', 'perl=5.8.8'],
    );
my @report_table_tests = 
    (
     ['dist=Kwalify', 'reports=1', 'os=freebsd', 'perl=5.8.8'],
     ['dist=Kwalify 1.16', 'reports=1', 'os=freebsd', 'perl=5.8.8'],
    );

plan tests => scalar(@matrix_tests)*5 + scalar(@report_table_tests)*2;

my $cgi = "$FindBin::RealBin/../cgi-bin/cpantestersmatrix.pl";

sub _fetch_cpantestersmatrix {
    my(@cgi_args) = @_;
    local $ENV{SCRIPT_NAME} = "cpantestersmatrix.pl"; # to avoid warnings
    my $content = `$^X -wT $cgi @cgi_args`;
    $content;
}

sub test_cpantestersmatrix {
    my(@cgi_args) = @_;
    my $content = _fetch_cpantestersmatrix(@cgi_args);
    is($?, 0, "Exit code for @cgi_args");
    ok($content, "Have content for @cgi_args");
    like($content, qr{content-type:\s*text/html}i, "Seen http header");
    unlike($content, qr{error}i, "No error seen");
    like($content, qr{other links}i, "Some expected content");
}

# assumes at least one PASS on a freebsd system
sub test_cpantestersmatrix_report_table {
    my(@cgi_args) = @_;
    my $content = _fetch_cpantestersmatrix(@cgi_args);
    like($content, qr{PASS});
    like($content, qr{freebsd});
}	

for my $matrix_test (@matrix_tests) {
    test_cpantestersmatrix @$matrix_test;
}

for my $report_table_test (@report_table_tests) {
    test_cpantestersmatrix_report_table @$report_table_test;
}

__END__
