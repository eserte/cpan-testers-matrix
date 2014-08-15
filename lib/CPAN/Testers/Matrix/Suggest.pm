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

package CPAN::Testers::Matrix::Suggest;

use strict;
use vars qw($VERSION);
$VERSION = '0.01';

use JSON::XS qw(encode_json);
use Search::Dict;

my $ct = 'text/javascript; charset=us-ascii';

sub new {
    my $class = shift;
    bless {
	   dist_file => "/var/tmp/cpan_folded_distname_list.txt",
	   max_results => 9, # my firefox starts to show a scrollbar for 10 and more results
	  }, $class;
}

sub do_suggest {
    my($self, $query) = @_;
    my($dist_file, $max_results) = @{$self}{qw(dist_file max_results)};
    open my $fh, $dist_file
	or die "Can't open $dist_file: $!";
    look $fh, $query, 0, 0;
    my @res;
    while(<$fh>) {
	chomp(my $term = $_);
	if (index($term, $query) == 0) {
	    push @res, $term;
	    last if @res >= $max_results;
	}
    }
    encode_json [$query, \@res];
}

sub psgi {
    require Plack::Request;
    return sub {
	my $env = shift;
	my $req = Plack::Request->new($env);
	my $query = $req->param('q');
	my $res_content = __PACKAGE__->new->do_suggest($query);
	return [ 200, ['Content-Type' => $ct], [$res_content] ];
    };
}

return 1 if caller;

require CGI;
my $q = CGI->new;
my $query = $q->param('q');
print $q->header($ct);
print __PACKAGE__->new->do_suggest($query);

__END__
