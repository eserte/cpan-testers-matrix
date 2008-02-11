#!/usr/bin/perl -wT
# -*- perl -*-

#
# $Id: cpantestersmatrix.pl,v 1.51 2008/02/11 20:42:16 eserte Exp $
# Author: Slaven Rezic
#
# Copyright (C) 2007,2008 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://srezic.sf.net/
#

package # not official yet
    CPAN::Testers::Matrix;

use strict;
use vars qw($VERSION);
$VERSION = sprintf("%d.%03d", q$Revision: 1.51 $ =~ /(\d+)\.(\d+)/);

use CGI qw(escapeHTML);
use CGI::Carp qw();
use CPAN::Version;
use File::Basename qw(basename);
use HTML::Table;
use List::Util qw(reduce);
use POSIX qw(strftime);
use Storable qw(lock_nstore lock_retrieve);

sub fetch_data ($);
sub fetch_author_data ($);
sub fetch_meta_yml ($);
sub build_success_table ($$$);
sub build_maxver_table ($$);
sub build_author_table ($$);
sub get_cache_filename_from_dist ($$);
sub meta_url ($);

my $cache_days = 1/4;

my $cache_root = "/tmp/cpantesters_cache_$<";
mkdir $cache_root, 0755 if !-d $cache_root;
my $dist_cache = "$cache_root/dist";
mkdir $dist_cache, 0755 if !-d $dist_cache;
my $author_cache = "$cache_root/author";
mkdir $author_cache, 0755 if !-d $author_cache;
my $meta_cache = "$cache_root/meta";
mkdir $meta_cache, 0755 if !-d $meta_cache;

# XXX hmm, some globals ...
my $title = "CPAN Testers Matrix";
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
my $is_latest_version;
my $latest_version;

if ($author) {
    eval {
	my $r;

	$r = fetch_author_data($author);
	my $author_dist;
	($author, $author_dist, $cachefile) = @{$r}{qw(author author_dist cachefile)};
	$r = build_author_table($author, $author_dist);
	$tables = $r->{tables};
	$ct_link = $r->{ct_link};
	$title = "CPAN Testers Matrix: $r->{title}";
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
		$dist_version = reduce { cmp_version($a,$b) > 0 ? $a : $b } map { $_->{version} } grep { $_->{version} } @$data;
	    }
	    eval {
		my $r = fetch_meta_yml($dist);
		my $meta = $r->{meta};
		$latest_version = $meta && defined $meta->{version} ? $meta->{version} : undef;
		$is_latest_version = defined $latest_version && $latest_version eq $dist_version;
	    };
	    warn $@ if $@;
	    $r = build_success_table($data, $dist, $dist_version);
	}
	$table = $r->{table};
	$ct_link = $r->{ct_link};
	$title = "CPAN Testers Matrix: $r->{title}";
    };
    $error = $@;
}

print $q->header;

my $latest_distribution_string = $is_latest_version ? " (latest distribution)" : "";

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

  .warn           { color:red; font-weight:bold; }
  .sml            { font-size: x-small; }

  --></style>
  <script type="text/javascript">
  <!-- Hide script
  function focus_first() {
    var frm = document.forms[0];
    if (frm && frm["dist"] && typeof frm["dist"].focus == "function") {
      frm["dist"].focus();
    }
  }
  // End script hiding -->
  </script>
 </head>
 <body onload="focus_first();">
  <h1><a href="$ct_link">$title</a>$latest_distribution_string</h1>
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
   <div>
    Distribution (e.g. DBI, CPAN-Reporter, YAML-Syck): <input name="dist" /> <input type="submit" />
    <input type="hidden" name="maxver" value="@{[ $q->param("maxver") ]}" />
   </div>
  </form>

  <form>
   <div>
    CPAN User ID: <input name="author" /> <input type="submit" />
   </div>
  </form>
EOF

# XXX Not yet, not satisfied with positioning!
if (0 && $author && eval { require Gravatar::URL; 1 }) {
    my $author_image_url = Gravatar::URL::gravatar_url(email => lc($author) . '@cpan.org',
						    default => 'http://bbbike.radzeit.de/BBBike/images/px_1t.gif');
    print <<EOF;
  <div style="position:absolute; right:10px; top:10px;">
    <img border="0" src="$author_image_url" />
  </div>
EOF
}

if ($author) {

    if ($tables) {
	for my $r (@$tables) {
	    print qq{<h2><a href="$r->{ct_link}">$r->{title}</a></h2>};
	    print $r->{table};
	}
    }

    print <<EOF;
<div>
<h2>Other links</h2>
<ul>
<li><a href="$ct_link">CPAN Testers</a>
<li><a href="http://search.cpan.org/~$author/">search.cpan.org</a>
</ul>
</div>
EOF

} elsif ($dist) {

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
<div style="float:left;">
<h2>Other versions</h2>
EOF
	my $html = "<ul>";
	my $seen_latest_version = defined $latest_version && $latest_version eq $dist_version;
	my $possibly_outdated_meta;
	for my $version (sort { cmp_version($b, $a) } keys %other_dist_versions) {
	    my $qq = CGI->new($q);
	    $qq->param(dist => "$dist $version");
	    $html .= qq{<li><a href="@{[ $qq->self_url ]}">$dist $version</a>};
	    if (defined $latest_version && $latest_version eq $version) {
		$html .= qq{ <span class="sml"> (latest distribution according to <a href="} . meta_url($dist) . qq{">META.yml</a>)</span>};
		$seen_latest_version++;
	    }
	    if (defined $latest_version && cmp_version($version, $latest_version) > 0) {
		$possibly_outdated_meta++;
	    }
	    $html .= "\n";
	}
## XXX yes? no?
# 	if ($possibly_outdated_meta) {
# 	    print qq{<div class="warn">NOTE: the latest <a href="} . meta_url($dist) .qq{">META.yml</a>};
# 	}
	if ($latest_version && !$seen_latest_version) {
	    print qq{<div class="warn">NOTE: no report for latest version $latest_version</div>};
	}
	$html .= "</ul>\n";
	print $html;
	print <<EOF;
</div>
EOF
    }

    (my $faked_module = $dist) =~ s{-}{::}g;
    print <<EOF;
<div style="float:left; margin-left:3em;">
<h2>Other links</h2>
<ul>
<li><a href="http://cpandeps.cantrell.org.uk/?module=$faked_module">CPAN Dependencies</a>
<li><a href="$ct_link">CPAN Testers</a>
<li><a href="http://search.cpan.org/dist/$dist/">search.cpan.org</a>
<li><a href="http://rt.cpan.org/NoAuth/Bugs.html?Dist=$dist">RT</a>
</ul>
</div>
EOF
}

print '<hr style="clear:left;">';

if ($cachefile) {
    my $file = basename $cachefile;
    my $datum = strftime("%F %T UTC", gmtime ((stat($cachefile))[9]));
    print <<EOF;
  <div>
   <i>$file</i> as of <i>$datum</i>
  </div>
EOF
}

print <<EOF;
  <div>
   <a href="http://srezic.cvs.sourceforge.net/*checkout*/srezic/srezic-misc/cgi/cpantestersmatrix.pl">cpantestersmatrix.pl</a> $VERSION
   by <a href="mailto:srezic\@cpan.org">Slaven Rezi&#x0107;</a>
  </div>
 </body>
</html>
EOF

sub fetch_meta_yml ($) {
    my($dist) = @_;

    my $meta;

    my $cachefile = get_cache_filename_from_dist($meta_cache, $dist);
    if (!-r $cachefile || -M $cachefile > $cache_days ||
	($ENV{HTTP_CACHE_CONTROL} && $ENV{HTTP_CACHE_CONTROL} eq 'no-cache')
       ) {
	require LWP;
	LWP->VERSION(5.808); # bugs in decoded_content
	require LWP::UserAgent;
	require YAML;

	my $ua = LWP::UserAgent->new;
	my $url = meta_url($dist);
	my $resp = $ua->get($url);
	if (!$resp->is_success) {
	    if ($resp->code == 500) {
		# it happens often, ignore it...
	    } else {
		warn "No success fetching <$url>: " . $resp->status_line;
	    }
	} else {
	    eval {
		$meta = YAML::Load($resp->decoded_content);
		lock_nstore($meta, $cachefile);
	    };
	    if ($@) {
		warn "While loading and storing meta data from $url: $!";
	    }
	}
    } else {
	$meta = lock_retrieve($cachefile)
	    or warn "Could not load cached meta data";
    }
    return { meta => $meta,
	     cachefile => $cachefile,
	   };
}

sub fetch_data ($) {
    my($raw_dist) = @_;

    my $data;

    my $dist = basename $raw_dist;
    if ($dist =~ m{^(.*)[- ]([\d\._]+)$}) {
	($dist, $dist_version) = ($1, $2);
    } elsif ($dist =~ m{^(.*) (.*)}) {
	($dist, $dist_version) = ($1, $2);
    }
    my $orig_dist = $dist;
    $dist =~ s{::}{-}g; # common error: module -> dist

    my $cachefile = get_cache_filename_from_dist($dist_cache, $dist);
    if (!-r $cachefile || -M $cachefile > $cache_days ||
	($ENV{HTTP_CACHE_CONTROL} && $ENV{HTTP_CACHE_CONTROL} eq 'no-cache')
       ) {
	require LWP;
	LWP->VERSION(5.808); # bugs in decoded_content
	require LWP::UserAgent;
	require YAML;
	#use YAML::Syck qw(LoadFile Load);

	my $ua = LWP::UserAgent->new;
	my $url;

	my $fetch_dist_data = sub {
	    my($dist) = @_;
	    $url = "http://cpantesters.perl.org/show/$dist.yaml";
	    my $resp = $ua->get($url);
	    $resp;
	};

	my $resp = $fetch_dist_data->($dist);
	if (!$resp->is_success) {
	    warn "No success fetching <$url>: " . $resp->status_line;
	    eval {
		require CPAN;
		require CPAN::DistnameInfo;
		local $CPAN::Be_Silent = $CPAN::Be_Silent = 1;
		my $mo = CPAN::Shell->expand("Module", $orig_dist);
		if ($mo) {
		    my $try_dist = CPAN::DistnameInfo->new($mo->cpan_file)->dist;
		    $resp = $fetch_dist_data->($try_dist);
		    if (!$resp->is_success) {
			die "No success fetching <$url>: " . $resp->status_line;
		    } else {
			$dist = $try_dist;
		    }
		}
	    };
	    warn $@ if $@;
	}
	# XXX hmmm, hack for CPAN.pm problems
	if (!$resp->is_success) {
	    eval {
		require CPAN;
		require CPAN::DistnameInfo;
		local $CPAN::Be_Silent = $CPAN::Be_Silent = 1;
		CPAN::HandleConfig->load;
		%CPAN::Config = %CPAN::Config; # cease -w
		my $pkgdetails = "$CPAN::Config->{keep_source_where}/modules/02packages.details.txt.gz";
		local $ENV{PATH} = "/usr/bin:/bin";
		open my $pkgfh, "-|", "zcat", $pkgdetails
		    or die "Cannot zcat $pkgdetails: $!";
		# overread header
		while(<$pkgfh>) {
		    chomp;
		    last if ($_ eq '');
		}
		while(<$pkgfh>) {
		    my($module,undef,$cpan_file) = split /\s+/;
		    if ($module eq $orig_dist) {
			my $try_dist = CPAN::DistnameInfo->new($cpan_file)->dist;
			$resp = $fetch_dist_data->($try_dist);
			if (!$resp->is_success) {
			    die "No success fetching <$url>: " . $resp->status_line;
			} else {
			    $dist = $try_dist;
			}
			last;
		    }
		}
	    };
	    warn $@ if $@;
	}
	if (!$resp->is_success) {
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
	# Fix distribution name
	eval { $dist = $data->[-1]->{distribution} };
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
		    if (my($action, $dist_plus_ver, $perl, $osname)
			= $report_line =~ m{^
					    (\S+)\s+ # action (PASS, FAIL ...)
					    (\S+)\s+ # distribution+version
					    (\S+(?:\s+patch(?:level)?\s+\d+|\s+RC\d+)?)\s+ # patchlevel/RC...
					    on\s+(\S+) # OS
				           }x) {
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
	    (!$maxver{$perl}->{$r->{osname}} || cmp_version($r->{version}, $maxver{$perl}->{$r->{osname}}) > 0)
	   ) {
	    $maxver{$perl}->{$r->{osname}} = $r->{version};
	}
	if (!$maxver || cmp_version($r->{version}, $maxver) > 0) {
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
    my($perl, $patch) = $r->{perl} =~ m{^(\S+)(?:\s+patch(?:level)?\s+(\S+))?};
    die "$r->{perl} couldn't be parsed" if !defined $perl;
    ($perl, $patch);
}

sub get_cache_filename_from_dist ($$) {
    my($cachedir, $dist) = @_;
    (my $safe_dist = $dist) =~ s{[^a-zA-Z0-9_.-]}{_}g;
    ($safe_dist) = $safe_dist =~ m{^(.*)$};
    my $cachefile = $cachedir."/".$safe_dist.".st";
    $cachefile;
}

sub meta_url ($) {
    my $dist = shift;
    "http://search.cpan.org/meta/$dist/META.yml";
}

BEGIN {
    if (eval { require version; 1 }) {
	*cmp_version = sub {
	    local $^W;
	    version->new($_[0]) <=> version->new($_[1]);
	};
    } else {
	*cmp_version = sub {
	    CPAN::Version->vcmp($_[0], $_[1]);
	};
    }
}

## Did not help:
# sub cmp_version {
#     my($a, $b) = @_;
#     my $cmp = CPAN::Version->vcmp($a, $b);
#     "$a $b $cmp";
#     if ($cmp == 0 && $a ne $b) {
# 	if ($a =~ /_/) {
# 	    $cmp = -1;
# 	} elsif ($b =~ /_/) {
# 	    $cmp = +1;
# 	}
#     }
#     $cmp;
# }

__END__

=head1 NAME

cpantestersmatrix.pl - present the CPAN testers results in a OS-perl version matrix

=head1 INSTALLATION

This is a CGI script. See below the PREREQUISITES section for required non-standard perl modules.
The script creates a predictable directory /tmp/cpantesters_cache_$<

=head1 PREREQUISITES

HTML::Table, LWP, XML::LibXML, CPAN::DistnameInfo, YAML.

=head1 SCRIPT CATEGORIES

CPAN

=head1 AUTHOR

Slaven ReziE<0x107>

=head1 SEE ALSO

L<http://cpandeps.cantrell.org.uk/>,
L<http://cpantesters.perl.org/>

=cut
