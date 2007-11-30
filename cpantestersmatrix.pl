#!/usr/bin/perl -wT
# -*- perl -*-

#
# $Id: cpantestersmatrix.pl,v 1.12 2007/11/30 23:01:01 eserte Exp $
# Author: Slaven Rezic
#
# Copyright (C) 2007 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

use strict;
use CGI qw(escapeHTML);
use CPAN::Version;
use File::Basename qw(basename);
use HTML::Table;
use LWP 5.808; # bugs in decoded_content
use LWP::UserAgent;
use List::Util qw(reduce);
#use YAML::Syck qw(LoadFile Load);
use Storable qw(lock_nstore lock_retrieve);
use YAML qw(Load);

my $cache = "/tmp/cpantesters_cache_$<";
mkdir $cache, 0755 if !-d $cache;

my $title = "CPAN Testers";
my $ct_link = "http://cpantesters.perl.org";

my $table;

my $q = CGI->new;

my $dist = $q->param("dist");
my $error;

my $dist_version;
my %other_dist_versions;

if ($dist) {
    eval {
	my $data;

	$dist = basename $dist;
	if ($dist =~ m{^(.*)[- ]([\d\._]+)$}) {
	    ($dist, $dist_version) = ($1, $2);
	}
	$dist =~ s{::}{-}g; # common error: module -> dist

	(my $safe_dist = $dist) =~ s{[^a-zA-Z0-9_.-]}{_}g;
	($safe_dist) = $safe_dist =~ m{^(.*)$};
	my $cachefile = $cache."/".$safe_dist.".st";
	if (!-r $cachefile || -M $cachefile > 0.1 ||
	    ($ENV{HTTP_CACHE_CONTROL} && $ENV{HTTP_CACHE_CONTROL} eq 'no-cache')
	   ) {
	    my $ua = LWP::UserAgent->new;
	    my $url = "http://cpantesters.perl.org/show/$dist.yaml";
	    my $resp = $ua->get($url);
	    if (!$resp->is_success) {
		warn $resp->as_string;
		die <<EOF
Distribution results for <$dist> at <$url> not found.
Maybe you entered a module name (A::B) instead of the distribution name (A-B)?
Maybe you added the author name to the distribution string?
EOF
	    }
	    $data = Load($resp->decoded_content) or die "Could not load YAML data from <$url>";
	    eval {
		lock_nstore($data, $cachefile);
	    };
	    if ($@) {
		warn $!;
		die "Internal error (nstore)";
	    };
	} else {
	    $data = lock_retrieve($cachefile) or die "Could not load cached data";
	}

	my %perl;
	my %perl_patches;
	my %osname;
	my %action;

	if (!$dist_version) {
	    $dist_version = reduce { CPAN::Version->vgt($a, $b) ? $a : $b } map { $_->{version} } grep { $_->{version} } @$data;
	}

	for my $r (@$data) {
	    if ($r->{version} ne $dist_version) {
		$other_dist_versions{$r->{version}}++;
		next;
	    }
	    my($perl, $patch) = $r->{perl} =~ m{^(\S+)(?:\s+patch\s+(\S+))?};
	    die "$r->{perl} couldn't be parsed" if !defined $perl;
	    $perl{$perl}++;
	    $perl_patches{$perl}->{$patch}++ if $patch;
	    $osname{$r->{osname}}++;

	    $action{$perl}->{$r->{osname}}->{$r->{action}}++;
	    $action{$perl}->{$r->{osname}}->{__TOTAL__}++;
	}

	my @perls   = sort { CPAN::Version->vcmp($b, $a) } keys %perl;
	my @osnames = sort { $a cmp $b } keys %osname;
	my @actions = qw(PASS NA UNKNOWN FAIL);

	my @matrix;
	for my $perl (@perls) {
	    my @row;
	    for my $osname (@osnames) {
		my $acts = $action{$perl}->{$osname};
		if ($acts) {
		    my @cell;

		    my @title;
		    for my $act (@actions) {
			if ($acts->{$act}) {
			    my $percent = int(100*($acts->{$act}||0)/$acts->{__TOTAL__});
			    push @cell, qq{<td width="${percent}%" class="action_$act"></td>};
			    push @title, $act.":".$acts->{$act};
			}
		    }
		    my $title = join(" ", @title);
		    push @row, qq{<table title="$title" class="bt" width="100%"><tr>} . join(" ", @cell) . qq{</tr></table>};
		} else {
		    push @row, "&nbsp;";
		}
	    }
	    unshift @row, $perl;
	    push @matrix, \@row;
	}

	$table = HTML::Table->new(-data => \@matrix,
				  -head => ["", @osnames],
				  -spacing => 0,
				 );
	$table->setColHead(1);
	{
	    my $cols = @osnames+1;
	    $table->setColWidth($_, int(100/$cols)."%") for (1 .. $cols);
	    #$table->setColAlign($_, 'center') for (1 .. $cols);
	}

	$title .= ": $dist $dist_version";
	$ct_link = "http://cpantesters.perl.org/show/$dist.html#$dist-$dist_version";
    };
    $error = $@;
}

print $q->header;

print <<EOF;
<html>
 <head><title>$title</title>
  <style type="text/css"><!--
  .action_PASS    { background:green; }
  .action_NA      { background:orange; }
  .action_UNKNOWN { background:orange; }
  .action_FAIL    { background:red; }

  table		  { border-collapse:collapse; }
  th,td           { border:1px solid black; }
  body		  { font-family:sans-serif; }

  .bt th,td	  { border:none; height:20px; }

  --></style>
 </head>
 <body>
  <h1><a href="$ct_link">$title</a></h1>
EOF
if ($error) {
    print <<EOF;
An error was encountered: @{[ escapeHTML($error) ]}
EOF
}
print <<EOF;
  <form>
   Distribution (e.g. DBI, CPAN-Reporter, YAML-Syck): <input name="dist" /> <input type="submit" />
  </form>
EOF
if ($table) {
    $table->print;
}
if (%other_dist_versions) {
    print <<EOF;
<h2>Other versions</h2>
<ul>
EOF
    for my $version (sort { CPAN::Version->vcmp($b, $a) } keys %other_dist_versions) {
	my $qq = CGI->new($q);
	$qq->param(dist => "$dist $version");
	print qq{<li><a href="@{[ $qq->self_url ]}">$dist $version</a>\n};
    }
    print <<EOF;
</ul>
EOF
}
print <<EOF;
 </body>
</html>
EOF

__END__

=pod

  rsync -av -e 'ssh -p 5022' ~/devel/cpantestersmatrix.pl root@bbbike2.radzeit.de:/home/slaven/cpantestersmatrix.pl

=cut
