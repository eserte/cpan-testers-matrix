#!/usr/bin/perl -wT
# -*- perl -*-

#
# $Id: cpantestersmatrix.pl,v 1.23 2007/11/30 23:01:52 eserte Exp $
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
use List::Util qw(reduce);
use Storable qw(lock_nstore lock_retrieve);

sub fetch_data ($);
sub build_success_table ($$$);
sub build_maxver_table ($$);

my $cache = "/tmp/cpantesters_cache_$<";
mkdir $cache, 0755 if !-d $cache;

# XXX hmm, some globals ...
my $title = "CPAN Testers";
my $ct_link = "http://cpantesters.perl.org";
my $table;
my $cachefile;

my $q = CGI->new;

my $dist = $q->param("dist");
my $error;

my $dist_version;
my %other_dist_versions;

if ($dist) {
    eval {
	my $r;

	$r = fetch_data($dist);
	my $data;
	($dist, $data, $cachefile) = @{$r}{qw(dist data cachefile)};

	if ($q->param("maxver")) {
	    $r = build_maxver_table($data, $dist);
	    $table = $r->{table};
	} else {
	    # Get newest version
	    if (!$dist_version) {
		$dist_version = reduce { CPAN::Version->vgt($a, $b) ? $a : $b } map { $_->{version} } grep { $_->{version} } @$data;
	    }
	    $r = build_success_table($data, $dist, $dist_version);
	    $table = $r->{table};
	}
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
    my $html_error = escapeHTML($error);
    $html_error =~ s{\n}{<br/>\n}g;
    print <<EOF;
An error was encountered:<br/>$html_error<br/>
EOF
}
print <<EOF;
  <form>
   Distribution (e.g. DBI, CPAN-Reporter, YAML-Syck): <input name="dist" /> <input type="submit" />
   <input type="hidden" name="maxver" value="@{[ $q->param("maxver") ]}" />
  </form>
EOF

if ($table) {
    $table->print;
}

if ($table) {
    print "<ul>";
    if (!$q->param("maxver")) {
	my $qq = CGI->new($q);
	$qq->param("maxver" => 1);
	print qq{<li><a href="@{[ $qq->self_url ]}">Max version with a PASS</a>\n};
    } else {
	my $qq = CGI->new($q);
	$qq->param("maxver" => 0);
	print qq{<li><a href="@{[ $qq->self_url ]}">Per-version view</a>\n};
    }
    print "</ul>";
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

print "<hr>";

if ($cachefile) {
    my $file = basename $cachefile;
    my $datum = scalar localtime ((stat($cachefile))[9]);
    print <<EOF;
  <div>
   <i>$file</i> as of <i>$datum</i>
  </div>
EOF
}

print <<EOF;
  <div>
   by <a href="mailto:srezic\@cpan.org">Slaven Rezi&#x0107;</a>
  </div>
 </body>
</html>
EOF

sub fetch_data ($) {
    my($raw_dist) = @_;

    my $data;

    my $dist = basename $raw_dist;
    if ($dist =~ m{^(.*)[- ]([\d\._]+)$}) {
	($dist, $dist_version) = ($1, $2);
    }
    $dist =~ s{::}{-}g; # common error: module -> dist

    (my $safe_dist = $dist) =~ s{[^a-zA-Z0-9_.-]}{_}g;
    ($safe_dist) = $safe_dist =~ m{^(.*)$};
    my $cachefile = $cache."/".$safe_dist.".st";
    if (!-r $cachefile || -M $cachefile > 1 ||
	($ENV{HTTP_CACHE_CONTROL} && $ENV{HTTP_CACHE_CONTROL} eq 'no-cache')
       ) {
	require LWP;
	LWP->VERSION(5.808); # bugs in decoded_content
	require LWP::UserAgent;
	require YAML;
	#use YAML::Syck qw(LoadFile Load);

	my $ua = LWP::UserAgent->new;
	my $url = "http://cpantesters.perl.org/show/$dist.yaml";
	my $resp = $ua->get($url);
	if (!$resp->is_success) {
	    warn "No success fetching <$url>: " . $resp->status_line;
	    die <<EOF
Distribution results for <$dist> at <$url> not found.
Maybe you entered a module name (A::B) instead of the distribution name (A-B)?
Maybe you added the author name to the distribution string?
Note that the distribution name is case-sensitive.
EOF
	}
	$data = YAML::Load($resp->decoded_content) or die "Could not load YAML data from <$url>";
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
    return { data => $data,
	     dist => $dist,
	     cachefile => $cachefile,
	   };
}

sub build_success_table ($$$) {
    my($data, $dist, $dist_version) = @_;

    my %perl;
    my %perl_patches;
    my %osname;
    my %action;

    for my $r (@$data) {
	if ($r->{version} ne $dist_version) {
	    $other_dist_versions{$r->{version}}++;
	    next;
	}
	my($perl, $patch) = get_perl_and_patch($r);
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

    my $table = HTML::Table->new(-data => \@matrix,
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

    return { table => $table };
}

sub build_maxver_table ($$) {
    my($data, $dist) = @_;

    my %perl;
    my %osname;
    my %maxver;
    my %hasreport;
    my $maxver;

    for my $r (@$data) {
	my($perl, undef) = get_perl_and_patch($r);
	$perl{$perl}++;
	$osname{$r->{osname}}++;

	$hasreport{$perl}->{$r->{osname}}++;
	if ($r->{action} eq 'PASS' &&
	    (!$maxver{$perl}->{$r->{osname}} || CPAN::Version->vgt($r->{version}, $maxver{$perl}->{$r->{osname}}))
	   ) {
	    $maxver{$perl}->{$r->{osname}} = $r->{version};
	}
	if (!$maxver || CPAN::Version->vgt($r->{version}, $maxver)) {
	    $maxver = $r->{version};
	}
    }

    my @perls   = sort { CPAN::Version->vcmp($b, $a) } keys %perl;
    my @osnames = sort { $a cmp $b } keys %osname;

    my @matrix;
    for my $perl (@perls) {
	my @row;
	for my $osname (@osnames) {
	    if (!$hasreport{$perl}->{$osname}) {
		push @row, "-";
	    } elsif (!exists $maxver{$perl}->{$osname}) {
		push @row, qq{<div style="background:red;">&nbsp;</div>};
	    } elsif ($maxver{$perl}->{$osname} ne $maxver) {
		push @row, qq{<div style="background:lightgreen;">$maxver{$perl}->{$osname}</div>};
	    } else {
		push @row, qq{<div style="background:green;">$maxver</div>};
	    }
	}
	unshift @row, $perl;
	push @matrix, \@row;
    }

    my $table = HTML::Table->new(-data => \@matrix,
				 -head => ["", @osnames],
				 -spacing => 0,
				);
    $table->setColHead(1);
    {
	my $cols = @osnames+1;
	$table->setColWidth($_, int(100/$cols)."%") for (1 .. $cols);
	#$table->setColAlign($_, 'center') for (1 .. $cols);
    }

    $title .= ": $dist (max version with a PASS)";
    $ct_link = "http://cpantesters.perl.org/show/$dist.html";

    return { table => $table };
}

sub get_perl_and_patch ($) {
    my($r) = @_;
    my($perl, $patch) = $r->{perl} =~ m{^(\S+)(?:\s+patch\s+(\S+))?};
    die "$r->{perl} couldn't be parsed" if !defined $perl;
    ($perl, $patch);
}

__END__

=pod

  rsync -av -e 'ssh -p 5022' ~/devel/cpantestersmatrix.pl root@bbbike2.radzeit.de:/home/slaven/cpantestersmatrix.pl

=cut
