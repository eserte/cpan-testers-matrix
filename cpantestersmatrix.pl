#!/usr/bin/perl -wT
# -*- perl -*-

#
# $Id: cpantestersmatrix.pl,v 1.28 2007/11/30 23:02:15 eserte Exp $
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
sub fetch_author_data ($);
sub build_success_table ($$$);
sub build_maxver_table ($$);
sub build_author_table ($$);

my $cache_days = 1/4;

my $cache = "/tmp/cpantesters_cache_$<";
mkdir $cache, 0755 if !-d $cache;
my $author_cache = "/tmp/cpantesters_author_cache_$<";
mkdir $author_cache, 0755 if !-d $author_cache;

# XXX hmm, some globals ...
my $title = "CPAN Testers";
my $ct_link = "http://cpantesters.perl.org";
my $table;
my $tables;
my $cachefile;

my $q = CGI->new;

my $dist = $q->param("dist");
my $author = $q->param("author");

my $error;

my $dist_version;
my %other_dist_versions;

if ($author) {
    eval {
	my $r;

	$r = fetch_author_data($author);
	my $author_dist;
	($author, $author_dist, $cachefile) = @{$r}{qw(author author_dist cachefile)};
	$r = build_author_table($author, $author_dist);
	$tables = $r->{tables};
	$ct_link = $r->{ct_link};
	$title = "CPAN Testers: $r->{title}";
    };
    $error = $@;
} elsif ($dist) {
    eval {
	my $r;
	
	$r = fetch_data($dist);
	my $data;
	($dist, $data, $cachefile) = @{$r}{qw(dist data cachefile)};

	if ($q->param("maxver")) {
	    $r = build_maxver_table($data, $dist);
	} else {
	    # Get newest version
	    if (!$dist_version) {
		$dist_version = reduce { CPAN::Version->vgt($a, $b) ? $a : $b } map { $_->{version} } grep { $_->{version} } @$data;
	    }
	    $r = build_success_table($data, $dist, $dist_version);
	}
	$table = $r->{table};
	$ct_link = $r->{ct_link};
	$title = "CPAN Testers: $r->{title}";
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

  .bt th,td	  { border:none; height:2.2ex; }

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

  <form>
   CPAN User ID: <input name="author" /> <input type="submit" />
  </form>
EOF

if ($author) {

    if ($tables) {
	for my $r (@$tables) {
	    print qq{<h2><a href="$r->{ct_link}">$r->{title}</a></h2>};
	    print $r->{table};
	}
    }

} else {

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
    if (!-r $cachefile || -M $cachefile > $cache_days ||
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

sub fetch_author_data ($) {
    my($author) = @_;
    $author = uc $author;
    ($author) = $author =~ m{([A-Z-]+)};

    my $author_dist = {};

    my $cachefile = $author_cache."/".$author.".st";
    if (!-r $cachefile || -M $cachefile > $cache_days ||
	($ENV{HTTP_CACHE_CONTROL} && $ENV{HTTP_CACHE_CONTROL} eq 'no-cache')
       ) {
	require LWP;
	LWP->VERSION(5.808); # bugs in decoded_content
	require LWP::UserAgent;
	require XML::LibXML;
	require CPAN::DistnameInfo;

	my $ua = LWP::UserAgent->new;
	my $url = "http://cpantesters.perl.org/author/$author.rss";
	#my $url = "file:///home/e/eserte/trash/SREZIC.rss";
	my $resp = $ua->get($url);
	if (!$resp->is_success) {
	    warn "No success fetching <$url>: " . $resp->status_line;
	    die <<EOF
No results for CPAN id <$author> found.
EOF
	}

	my $p = XML::LibXML->new;
	my $doc = eval {
	    $p->parse_string($resp->decoded_content);
	};
	if ($@) {
	    warn $@;
	    die "Error parsing rss feed from <$url>";
	}
	my $root = $doc->documentElement;
	#$root->setNamespaceDeclURI(undef, undef); # sigh, not available in older XML::LibXML's
	for my $node ($root->childNodes) {
	    next if $node->nodeName ne 'item';
	    for my $node2 ($node->childNodes) {
		if ($node2->nodeName eq 'title') {
		    my $report_line = $node2->textContent;
		    if (my($action, $dist_plus_ver, $perl, $osname) = $report_line =~ m{^(\S+)\s+(\S+)\s+(\S+(?:\s+patch \d+)?)\s+on\s+(\S+)}) {
			my $d = CPAN::DistnameInfo->new("$author/$dist_plus_ver.tar.gz");
			my $dist = $d->dist;
			my $version = $d->version;
			push @{$author_dist->{$dist}}, { dist => $dist,
							 version => $version,
							 action => $action,
							 perl => $perl,
							 osname => $osname,
						       };
		    } else {
			warn "Cannot parse report line <$report_line>";
		    }
		    last;
		}
	    }
	}
	eval {
	    lock_nstore($author_dist, $cachefile);
	};
	if ($@) {
	    warn $!;
	    die "Internal error (nstore)";
	};
    } else {
	$author_dist = lock_retrieve($cachefile) or die "Could not load cached data";
    }

    return { author_dist => $author_dist,
	     author => $author,
	     cachefile => $cachefile,
	   }
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

    my $title = "$dist $dist_version";
    my $ct_link = "http://cpantesters.perl.org/show/$dist.html#$dist-$dist_version";

    return { table => $table,
	     title => "$dist $dist_version",
	     ct_link => $ct_link,
	   };
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

    return { table => $table,
	     title => "$dist (max version with a PASS)",
	     ct_link => "http://cpantesters.perl.org/show/$dist.html",
	   };
}

sub build_author_table ($$) {
    my($author, $author_dist) = @_;
    my @tables;
    for my $dist (sort keys %$author_dist) {
	my $dist_version = $author_dist->{$dist}->[0]->{version};
	my $r = build_success_table($author_dist->{$dist},
				    $dist,
				    $dist_version,
				   );
	my $qq = CGI->new({dist => "$dist $dist_version"});
	$r->{ct_link} = $q->url(-relative => 1) . "?" . $qq->query_string;
	push @tables, $r;
    }
    return { tables => \@tables,
	     title => $author,
	     ct_link => "http://cpantesters.perl.org/author/$author.html",
	   };
}

sub get_perl_and_patch ($) {
    my($r) = @_;
    my($perl, $patch) = $r->{perl} =~ m{^(\S+)(?:\s+patch\s+(\S+))?};
    die "$r->{perl} couldn't be parsed" if !defined $perl;
    ($perl, $patch);
}

__END__

=pod

Stable:

  rsync -av -e 'ssh -p 5022' ~/devel/cpantestersmatrix.pl root@bbbike2.radzeit.de:/home/slaven/cpantestersmatrix.pl

Devel:

  rsync -av -e 'ssh -p 5022' ~/devel/cpantestersmatrix.pl root@bbbike2.radzeit.de:/home/slaven/cpantestersmatrix2.pl

=cut
