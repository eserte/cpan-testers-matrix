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
     ['author=zoffix', { TODO => "Large author files currently not supported" }],
     ['dist=Schema::Kwalify'], # resolves to distribution
    );
my @report_table_tests = 
    (
     ['dist=Kwalify', 'reports=1', 'os=freebsd', 'perl=5.8.8'],
     ['dist=Kwalify 1.16', 'reports=1', 'os=freebsd', 'perl=5.8.8'],
    );
my @other_links_tests =
    (
     ['bugtracker', 'dist=MooseX-Method-Signatures 0.36'],
    );

plan tests => scalar(@matrix_tests)*5 + scalar(@report_table_tests)*2 + scalar(@other_links_tests)*1;

my $cgi = "$FindBin::RealBin/../cgi-bin/cpantestersmatrix.pl";

sub _fetch_cpantestersmatrix {
    my(@cgi_args) = @_;
    local $ENV{SCRIPT_NAME} = "cpantestersmatrix.pl"; # to avoid warnings
    local $ENV{HTTP_USER_AGENT} = 'Mozilla/5.0 (X11; Linux i386; rv:20.0) Gecko/20100101 Firefox/20.0';
    local $ENV{REMOTE_ADDR} = '127.0.0.1';
    my $cmd = "$^X -wT $cgi @cgi_args";
    my $content = `$cmd`;
    $content;
}

sub test_cpantestersmatrix {
    my(@cgi_args) = @_;
    my %directives;
    @cgi_args = grep {
	if (ref $_ eq 'HASH') {
	    %directives = %$_;
	    0;
	} else {
	    1;
	}
    } @cgi_args;
    local $TODO;
    $TODO = $directives{TODO} if exists $directives{TODO};
    my $content = _fetch_cpantestersmatrix(@cgi_args);
    is($?, 0, "Exit code for @cgi_args");
    ok($content, "Have content for @cgi_args");
    like($content, qr{content-type:\s*text/html}i, "Seen http header");
    unlike($content, qr{error}i, "No error seen (@cgi_args)");
    like($content, qr{other links}i, "Some expected content");
}

# assumes at least one PASS on a freebsd system
sub test_cpantestersmatrix_report_table {
    my(@cgi_args) = @_;
    my $content = _fetch_cpantestersmatrix(@cgi_args);
    like($content, qr{PASS});
    like($content, qr{freebsd});
}

sub test_cpantestersmatrix_other_links {
    my($what, @cgi_args) = @_;
    my $content = _fetch_cpantestersmatrix(@cgi_args);
    if ($what eq 'bugtracker') {
	like $content, qr{<a href="http://[^"]+">Bugtracker}, "Found bugtracker for @cgi_args";
    } else {
	die "Unhandled <$what>";
    }
}

for my $matrix_test (@matrix_tests) {
    test_cpantestersmatrix @$matrix_test;
}

for my $report_table_test (@report_table_tests) {
    test_cpantestersmatrix_report_table @$report_table_test;
}

for my $other_links_test (@other_links_tests) {
    test_cpantestersmatrix_other_links @$other_links_test;
}

__END__
