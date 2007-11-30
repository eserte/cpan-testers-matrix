#!/usr/local/bin/perl5.10.0 -wT
# -*- perl -*-

#
# $Id: cpantestersmatrix.pl,v 1.4 2007/11/30 23:00:28 eserte Exp $
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
use CGI;
use File::Basename qw(basename);
use HTML::Table;
use LWP::UserAgent;
use List::Util qw(reduce);
use YAML::Syck qw(LoadFile Load);
use CPAN::Version;

my $cache = "/tmp/cpantesters_cache_$<";
mkdir $cache, 0755 if !-d $cache;

my $title = "CPAN Testers";
my $ct_link = "http://cpantesters.perl.org";

my $table;

my $q = CGI->new;

my $dist = $q->param("dist");
my $error;

if ($dist) {
    eval {
	$dist = basename $dist;

	my $data;

	(my $safe_dist = $dist) =~ s{[^a-zA-Z0-9_.-]}{_}g;
	($safe_dist) = $safe_dist =~ m{^(.*)$};
	my $cachefile = $cache."/".$safe_dist.".yaml";
	if (!-r $cachefile || -M $cachefile > 1) {
	    my $ua = LWP::UserAgent->new;
	    my $url = "http://cpantesters.perl.org/show/$dist.yaml";
	    my $resp = $ua->get($url);
	    if (!$resp->is_success) {
		warn $resp->as_string;
		die "Distribution results at <$url> not found";
	    }
	    $data = Load($resp->decoded_content) or die "Could not load YAML data from <$url>";
	    open my $fh, ">", "$cachefile.$$" or do { warn $!; die "Internal error (open)" };
	    print $fh $resp->decoded_content;
	    close $fh;
	    rename "$cachefile.$$", $cachefile or do { warn $!; die "Internal error (rename)" };
	} else {
	    $data = LoadFile($cachefile) or die "Could not load cached YAML data";
	}

	my %perl;
	my %perl_patches;
	my %osname;
	my %action;

	my $max_version = reduce { CPAN::Version->vgt($a, $b) ? $a : $b } map { $_->{version} } grep { $_->{version} } @$data;

	for my $r (@$data) {
	    next if $r->{version} ne $max_version;
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

		    for my $act (@actions) {
			if ($acts->{$act}) {
			    my $percent = int(100*($acts->{$act}||0)/$acts->{__TOTAL__});
			    push @cell, qq{<td width="${percent}%" class="action_$act"></td>};
			}
		    }
		    push @row, qq{<table class="bt" width="100%"><tr>} . join(" ", @cell) . qq{</tr></table>};
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

	$title .= ": $dist $max_version";
	$ct_link = "http://cpantesters.perl.org/show/$dist.html#$dist-$max_version";
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

  .bar { 
    display: block;
    position: relative;
    height: 20px; 
  }

  --></style>
 </head>
 <body>
  <h1><a href="$ct_link">$title</a></h1>
EOF
if ($error) {
    print <<EOF;
An error was encountered: $error
EOF
}
print <<EOF;
  <form>
   Distribution: <input name="dist" /> <input type="submit" />
  </form>
EOF
if ($table) {
    $table->print;
}
print <<EOF;
 </body>
</html>
EOF

__END__
