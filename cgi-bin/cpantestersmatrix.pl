#!/usr/bin/perl -wT
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2007,2008,2009,2010 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
#

package # not official yet
    CPAN::Testers::Matrix;

use strict;
use vars qw($VERSION);
$VERSION = '1.400';

use vars qw($UA);

use CGI qw(escapeHTML);
use CGI::Carp qw();
use CGI::Cookie;
use CPAN::Version;
use File::Basename qw(basename);
use FindBin;
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
sub get_ua ();
sub fetch_error_check ($);
sub set_dist_and_version ($);
sub get_perl_and_patch ($);
sub require_yaml ();
sub trim ($);

my $cache_days = 1/4;
my $ua_timeout = 10;

my $cache_root = "/tmp/cpantesters_cache_$<";
mkdir $cache_root, 0755 if !-d $cache_root;
my $dist_cache = "$cache_root/dist";
mkdir $dist_cache, 0755 if !-d $dist_cache;
my $author_cache = "$cache_root/author";
mkdir $author_cache, 0755 if !-d $author_cache;
my $meta_cache = "$cache_root/meta";
mkdir $meta_cache, 0755 if !-d $meta_cache;

my($realbin) = $FindBin::RealBin =~ m{^(.*)$}; # untaint it
my $amendments_yml = "$realbin/cpantesters_amendments.yml";
my $amendments_st = "$realbin/cpantesters_amendments.st";
my $amendments;

my $q = CGI->new;

#XXX { local $ENV{PATH} = "/bin:/usr/bin";system("/usr/bin/ktrace", "-f", "/tmp/cpanktrace", "-p", $$);}

# XXX hmm, some globals ...
my $title = "CPAN Testers Matrix";
if ($q->script_name =~ /cpantestersmatrix2/) {
    $title .= " (beta)";
}
my @CORE_OSNAMES = qw(MSWin32 cygwin darwin freebsd linux openbsd netbsd solaris);
my $old_ct_domain = "cpantesters.perl.org";
my $new_ct_domain = "www.cpantesters.org";
my $test_ct_domain = "reports.cpantesters.org"; # not test anymore --- this is now the real thing?
my $ct_domain = $new_ct_domain;
#my $ct_domain = $old_ct_domain;
#my $ct_domain = $test_ct_domain;
my $ct_link = "http://$ct_domain";
my $dist_bugtracker_url;
#my $report_rooturl = "http://nntp.x.perl.org/group/perl.cpan.testers/";
my $report_rooturl = "http://www.cpantesters.org/cpan/report/";
my $table;
my $tables;
my $cachefile;
my $reports_header;

my %stylesheets = (
    hicontrast => {
	name => 'High Contrast',
	fun  => \&stylesheet_hicontrast,
    },
    cpantesters => {
	name => 'CPAN Testers',
	fun  => \&stylesheet_cpantesters,
    },
    matrix => {
	name => 'Matrix',
	fun  => \&stylesheet_matrix,
    },
    gradients => {
	name => 'Gradients',
	fun  => \&stylesheet_gradients,
    },
);

my $dist         = trim $q->param("dist");
my $author       = trim $q->param("author");
my $reports      = $q->param("reports");
my $edit_prefs   = $q->param("prefs");
my $update_prefs = $q->param("update_prefs");

my $error;

my $dist_version;
my %other_dist_versions;
my $is_latest_version;
my $latest_version;

my @actions = qw(PASS NA UNKNOWN INVALID FAIL);

my %prefs = do {
    my %cookies = CGI::Cookie->fetch;
    my $cookie = $cookies{preferences}
	if exists $cookies{preferences};

    if ($update_prefs || !$cookie) {
	$cookie = CGI::Cookie->new(
	    -name    => 'preferences',
	    -expires => '+10y',
	    -value   => {
		stylesheet  => do {
		    my $requested = $update_prefs && trim $q->param('stylesheet');
		    defined $requested && exists $stylesheets{$requested}
			? $requested : 'matrix';
		},
		steal_focus => (defined $q->param('steal_focus') ? 1 : 0),
	    },
	);

    }

    print $q->header(
	-cookie  => [$cookie],
	-expires => ($edit_prefs ? 'now' : '+'.int($cache_days*24).'h'),
    );

    $cookie->value;
};

if ($reports) {
    my $want_perl = $q->param("perl");
    my $want_os = $q->param("os");
    my @sort_columns = $q->param("sort");
    @sort_columns = "action" if !@sort_columns;

    if (defined $want_perl || defined $want_os) {
	$reports_header = "Reports filtered for ";
	if (defined $want_perl) {
	    $reports_header .= "perl=$want_perl ";
	}
	if (defined $want_os) {
	    $reports_header .= "os=$want_os";
	}
    }

    eval {
	my $r = fetch_data($dist);
	set_newest_dist_version($r->{data});
	my @reports;
	for my $rec (@{ $r->{data} }) {
	    next if defined $dist_version && $rec->{version} ne $dist_version;
	    my($perl, $patch) = eval { get_perl_and_patch($rec) };
	    next if !$perl;
	    next if defined $want_perl && $perl ne $want_perl;
	    next if defined $want_os && $rec->{osname} ne $want_os;
	    push @reports, $rec;
	    $rec->{patch} = $patch;
	}
	my $last_action;
	my @matrix;
	# By chance, lexical ordering fits for sort=action: FAIL is first.
	no warnings 'uninitialized';
	for my $rec (sort {
	    my $res = 0;
	    for my $sort_column (@sort_columns) {
		if      ($sort_column eq 'osvers') {
		    $res = cmp_version($a->{$sort_column}, $b->{$sort_column});
		} elsif ($sort_column eq 'perl') {
		    $res = cmp_version_with_patch($a->{$sort_column}, $b->{$sort_column});
		} elsif ($sort_column eq 'id') {
		    $res = $a->{$sort_column} <=> $b->{$sort_column};
		} else {
		    $res = $a->{$sort_column} cmp $b->{$sort_column};
		}
		last if $res != 0;
	    }
	    $res;
	} @reports) {
	    my $action_comment_html = $rec->{action_comment}||"";
	    $action_comment_html =~ s{(https?://\S+)}{<a href="$1">$1</a>}g; # simple-minded href-ify
	    #my $report_url = $report_rooturl . $rec->{id}; # prefer id over guid
	    my $report_url = $report_rooturl . ($rec->{guid} || $rec->{id}); # prefer guid over id
	    push @matrix, [ qq{<span class="fgaction_$rec->{action}">$rec->{action}</span>},
			    qq{<a href="$report_url">$rec->{id}</a>},
			    $rec->{osvers},
			    $rec->{archname},
			    (!defined $dist_version ? $rec->{version} : ()),
			    (!defined $want_perl    ? $rec->{perl} : ()),
			    (!defined $want_os      ? $rec->{osname} : ()),
			    ( defined $want_perl    ? $rec->{patch} : ()),
			    $action_comment_html,
			  ];
	}
	my $sort_href = sub {
	    my($label, $column) = @_;
	    my $qq = CGI->new($q);
	    my @new_sort_columns = ($column, grep { $_ ne $column } @sort_columns);
	    $qq->param("sort", @new_sort_columns);
	    qq{<a href="@{[ $qq->self_url ]}">$label</a>};
	};
	$table = HTML::Table->new(-head    => [$sort_href->("Result", "action"),
					       $sort_href->("Id", "id"),
					       $sort_href->("OS vers", "osvers"),
					       $sort_href->("archname", "archname"),
					       (!defined $dist_version ? $sort_href->("Dist version", "version") : ()),
					       (!defined $want_perl    ? $sort_href->("Perl version", "perl") : ()),
					       (!defined $want_os      ? $sort_href->("OS", "osname") : ()),
					       ( defined $want_perl    ? $sort_href->("Perl patch", "patch") : ()),
					       $sort_href->("Comment", "action_comment"),
					      ],
				  -spacing => 0,
				  -data    => \@matrix,
				  -class   => 'reports',
				 );
	$table->setColHead(1);
	$title .= ": $dist $dist_version";
	$ct_link = "http://$ct_domain/show/$dist.html#$dist-$dist_version";
    };
    $error = $@ if $@;
} elsif ($author) {
    eval {
	my $r = fetch_author_data($author);
	my $author_dist;
	($author, $author_dist, $cachefile, $error) = @{$r}{qw(author author_dist cachefile error)};
	$r = build_author_table($author, $author_dist);
	$tables = $r->{tables};
	$ct_link = $r->{ct_link};
	$title .= ": $r->{title}";
    };
    $error = $@ if $@;
} elsif ($dist) {
    eval {
	my $r = fetch_data($dist);
	my $data;
	($dist, $data, $cachefile, $error) = @{$r}{qw(dist data cachefile error)};

	if ($q->param("maxver")) {
	    $r = build_maxver_table($data, $dist);
	} else {
	    set_newest_dist_version($data);
	    eval {
		my $r = fetch_meta_yml($dist);
		my $meta = $r->{meta};
		$latest_version = $meta && defined $meta->{version} ? $meta->{version} : undef;
		$is_latest_version = defined $latest_version && $latest_version eq $dist_version;
		if ($meta && $meta->{resources} && $meta->{resources}->{bugtracker}) {
		    $dist_bugtracker_url = $meta->{resources}->{bugtracker};
		}
	    };
	    warn $@ if $@;
	    $r = build_success_table($data, $dist, $dist_version);
	}
	$table = $r->{table};
	$ct_link = $r->{ct_link};
	$title .= ": $r->{title}";
    };
    $error = $@ if $@;
}

my $latest_distribution_string = $is_latest_version ? " (latest distribution)" : "";

print <<EOF;
<html>
 <head><title>$title</title>
  <link type="image/ico" rel="shortcut icon" href="cpantesters_favicon.ico" />
  <meta name="ROBOTS" content="INDEX, NOFOLLOW" />
  <style type="text/css"><!--
EOF
print $stylesheets{ $prefs{stylesheet} }->{fun}->();
if ($author && eval { require Gravatar::URL; 1 }) {
    my $author_image_url = Gravatar::URL::gravatar_url(email => lc($author) . '@cpan.org',
						       default => 'http://bbbike.de/BBBike/images/px_1t.gif');
    print <<EOF;
  body { background-image:url($author_image_url); background-repeat:no-repeat; background-position: 99% 10px; }
EOF
}
print <<EOF;

  .maxver_PASSNEW { background:green;      }
  .maxver_PASSANY { background:lightgreen; }
  .maxver_NONE    { background:red;        }  

  .fgaction_PASS    { color:green;  }
  .fgaction_NA      { color:orange; }
  .fgaction_UNKNOWN { color:orange; }
  .fgaction_FAIL    { color:red;    }
  .fgaction_INVALID { color:orange; }

  table		  { border-collapse:collapse; }
  th,td           { border:1px solid black; }
  body		  { font-family:sans-serif; }

  .bt th,td	  { border:none; height:2.2ex; }

  .reports th	  { border:2px solid black; padding-left:3px; padding-right:3px; }
  .reports td	  { border:1px solid black; padding-left:3px; padding-right:3px; }

  .warn           { color:red; font-weight:bold; }
  .sml            { font-size: x-small; }
  .unimpt         { font-size: smaller; }

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
EOF
print $prefs{steal_focus} ? qq{<body onload="focus_first();">\n} : qq{<body>\n};
print <<EOF;
  <h1><a href="$ct_link">$title</a>$latest_distribution_string</h1>
EOF
if ($error) {
    my $html_error = escapeHTML($error);
    $html_error =~ s{\n}{<br/>\n}g;
    print <<EOF;
<div class="warn">
  An error was encountered:<br/>$html_error<br/>
</div>
EOF
}

print <<EOF;
  <form>
   <div>
    Distribution <span class="unimpt">(e.g. DBI, CPAN-Reporter, YAML-Syck)</span>: <input name="dist" /> <input type="submit" />
    <input type="hidden" name="maxver" value="@{[ $q->param("maxver") ]}" />
   </div>
  </form>

  <form>
   <div>
    CPAN User ID <span class="unimpt">(e.g. GAAS, TIMB, JHI)</span>: <input name="author" /> <input type="submit" />
   </div>
  </form>
EOF

if ($reports) {
    {
	my $qq = CGI->new($q);
	$qq->delete("reports");
	$qq->delete("os");
	$qq->delete("perl");
	$qq->delete("sort");
    print <<EOF;
<div style="margin-bottom:0.5cm;">
  <a href="@{[ $qq->self_url ]}">Back to matrix</a>
</div>
EOF
    }

    if (defined $reports_header) {
	print <<EOF;
<div style="margin-bottom:0.5cm;">
$reports_header	
</div>
EOF
    }

    if ($table) {
	$table->print;
    }

    dist_links();

} elsif ($author) {

    teaser();

    if ($tables) {
	for my $r (@$tables) {
	    print qq{<h2><a href="$r->{ct_link}">$r->{title}</a></h2>};
	    print $r->{table};
	}
    }

    print <<EOF;
<div style="float:left;">
<h2>Other links</h2>
<ul>
<li><a href="$ct_link">CPAN Testers</a>
<li><a href="http://search.cpan.org/~$author/">search.cpan.org</a>
</ul>
</div>
EOF

    if ($tables) {
	show_legend();
    }

} elsif ($dist) {

    teaser();

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

    dist_links();

    if ($table) {
	show_legend();
    }

} elsif ($edit_prefs) {
    print <<'EOF';
<form method="POST">
  <fieldset>
    <legend>Preferences</legend>
    <label for="stylesheet">Stylesheet:</label>
EOF

    for my $stylesheet (sort keys %stylesheets) {
	my $selected = $stylesheet eq $prefs{stylesheet}
	    ? q{checked="checked"} : "";
	$q->print(qq{<input type="radio" name="stylesheet" value="$stylesheet" $selected>$stylesheets{$stylesheet}{name}</input>});
    }

    my $steal_focus = $prefs{steal_focus}
	? q{checked="checked"} : "";

    print <<"EOF"
    <br />

    <label for="steal_focus">Steal Focus:</label>
    <input type="checkbox" name="steal_focus" $steal_focus></input>

    <br />

    <input type="submit" name="update_prefs" value="Update Preferences"></input>
  </fieldset>
</form>
EOF
}

print '<hr style="clear:left;">';

if ($cachefile) {
    my $file = basename $cachefile;
    my $datum = strftime("%F %T UTC", gmtime ((stat($cachefile))[9]));
    print <<EOF;
  <div>
   <i>$file</i> as of <i>$datum</i> <span class="sml">Use Shift-Reload for forced update</span>
  </div>
EOF
}

print <<EOF;
  <div>
   <span class="sml"><a href="?prefs=1">Change Preferences</p></span>
  </div>
  <div>
   <a href="http://github.com/eserte/cpan-testers-matrix">cpantestersmatrix.pl</a> $VERSION
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
	require_yaml;

	my $ua = get_ua;
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
		$meta = yaml_load($resp->decoded_content);
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

    set_dist_and_version($raw_dist);
    my $orig_dist = $dist;
    $dist =~ s{::}{-}g; # common error: module -> dist

    my $resp;
    my $good_cachefile;
    my $url;
    my $cachefile = get_cache_filename_from_dist($dist_cache, $dist);
    my $error;

 GET_DATA: {
	if (-r $cachefile && -M $cachefile < $cache_days &&
	    (!$ENV{HTTP_CACHE_CONTROL} || $ENV{HTTP_CACHE_CONTROL} ne 'no-cache')
	   ) {
	    $good_cachefile = $cachefile;
	    last GET_DATA;
	}

	require_yaml;

	my $ua = get_ua;

	my $fetch_dist_data = sub {
	    my($dist) = @_;
	    $url = "http://$ct_domain/show/$dist.yaml";
	    my $resp = $ua->get($url);
	    $resp;
	};

	$resp = $fetch_dist_data->($dist);
	last GET_DATA if $resp->is_success;

	$error = fetch_error_check($resp);
	if ($error) {
	    if (-r $cachefile) {
		$error .= sprintf "\nReusing old cached file, %.1f day(s) old\n", -M $cachefile;
		$good_cachefile = $cachefile;
		last GET_DATA;
	    } else {
		die $error;
	    }
	}

	warn "No success fetching <$url>: " . $resp->status_line;
	my $fallback_dist;
	if (eval { require "$realbin/parse_cpan_packages_fast.pl"; 1 }) {
	    eval {
		my $mod_info = Parse::CPAN::Packages::Fast->new->package($orig_dist);
		$fallback_dist = $mod_info->distribution;
	    };
	    warn $@ if $@;
	} else {
	    eval {
		require CPAN;
		require CPAN::DistnameInfo;
		local $ENV{PATH} = "/usr/bin:/bin";
		local $CPAN::Be_Silent = $CPAN::Be_Silent = 1;
		my $mo = CPAN::Shell->expand("Module", $orig_dist);
		if ($mo) {
		    $fallback_dist = CPAN::DistnameInfo->new($mo->cpan_file);
		}
	    };
	    warn $@ if $@;
	}
	if ($fallback_dist) {
	    eval {
		my $try_dist = $fallback_dist->dist;
		$resp = $fetch_dist_data->($try_dist);
		if (!$resp->is_success) {
		    die "No success fetching <$url>: " . $resp->status_line;
		} else {
		    $dist = $try_dist;
		}
	    };
	    warn $@ if $@;
	}
	last GET_DATA if $resp->is_success;

	# XXX hmmm, hack for CPAN.pm problems
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
		if (lc $module eq lc $orig_dist) { # allow lowercase written modules
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
	last if $resp->is_success;

	die <<EOF
Distribution results for <$dist> at <$url> not found.
Maybe you entered a module name (A::B) instead of the distribution name (A-B)?
Maybe you added the author name to the distribution string?
Note that the distribution name is case-sensitive.
EOF
    }

    if ($good_cachefile) {
	$data = lock_retrieve($cachefile)
	    or die "Could not load cached data";
	# Fix distribution name
	eval { $dist = $data->[-1]->{distribution} };
    } elsif ($resp && $resp->is_success) {
	$data = yaml_load($resp->decoded_content)
	    or die "Could not load YAML data from <$url>";
	for my $result (@$data) {
	    amend_result($result);
	}
	eval {
	    lock_nstore($data, $cachefile);
	};
	if ($@) {
	    warn $!;
	    die "Internal error (nstore)";
	};
    }

    return { data => $data,
	     dist => $dist,
	     cachefile => $cachefile,
	     error => $error,
	   };
}

sub fetch_author_data ($) {
    my($author) = @_;
    $author = uc $author;
    ($author) = $author =~ m{([A-Z-]+)};

    my $author_dist = {};

    my $resp;
    my $good_cachefile;
    my $url;
    my $cachefile = $author_cache."/".$author.".st";
    my $error;

 GET_DATA: {
	if (-r $cachefile && -M $cachefile < $cache_days &&
	    (!$ENV{HTTP_CACHE_CONTROL} || $ENV{HTTP_CACHE_CONTROL} ne 'no-cache')
	   ) {
	    $good_cachefile = $cachefile;
	    last GET_DATA;
	}

	require XML::LibXML;
	require CPAN::DistnameInfo;

	my $ua = get_ua;
	if ($ct_domain eq $new_ct_domain || $ct_domain eq $test_ct_domain) {
	    $url = "http://$new_ct_domain/author/$author.yaml";
	} else {
	    $url = "http://$old_ct_domain/author/$author.rss"; # XXX must use old site because of limitation to 100 records
	}
	#$url = "file:///home/e/eserte/trash/SREZIC.yaml";
	$resp = $ua->get($url);
	last GET_DATA if $resp->is_success;

	$error = fetch_error_check($resp);
	if ($error) {
	    if (-r $cachefile) {
		warn "No success fetching <$url>: " . $resp->status_line;
		$error .= sprintf "\nReusing old cached file, %.1f day(s) old\n", -M $cachefile;
		$good_cachefile = $cachefile;
		last GET_DATA;
	    } else {
		die $error;
	    }
	}

	die <<EOF;
No results for CPAN id <$author> found.
EOF
    }

    if ($good_cachefile) {
	$author_dist = lock_retrieve($cachefile)
	    or die "Could not load cached data";
    } elsif ($resp && $resp->is_success) {
	if ($url =~ m{\.ya?ml$}) {
	    require_yaml;
	    my $data = yaml_load($resp->decoded_content);
	    for my $result (@$data) {
		my $dist;
		if (defined $result->{dist}) { # new style
		    $dist = $result->{distribution} = $result->{dist};
		} elsif (defined $result->{distribution}) { # old style
		    $dist = $result->{dist} = $result->{distribution};
		}
		amend_result($result);
		push @{$author_dist->{$dist}}, $result;
	    }
	} else {
	    # assume RSS
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
		my $about = $node->getAttribute("rdf:about") || ''; # XXX may be undef with some XML::LibXML versions?!
		my($report_id) = $about =~ m{/perl\.cpan\.testers/(\d+)};
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
			    my $id = $report_id;
			    my $result = { dist => $dist,
					   version => $version,
					   action => $action,
					   id => $report_id,
					   perl => $perl,
					   osname => $osname,
					 };
			    amend_result($result);
			    push @{$author_dist->{$dist}}, $result;
			} else {
			    warn "Cannot parse report line <$report_line>";
			}
			last;
		    }
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
    }

    return { author_dist => $author_dist,
	     author => $author,
	     cachefile => $cachefile,
	     error => $error,
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

    # Here trap errors in source yaml (perl version=0, osname="")
    my @perls   = grep { $_ } sort { CPAN::Version->vcmp($b, $a) } keys %perl;
    my @osnames = grep { $_ } sort { $a cmp $b } keys %osname;

    # Add "core" osnames to the list of existing ones
    @osnames = do {
	my %osnames = map { ($_,1) } (@osnames, @CORE_OSNAMES);
	sort keys %osnames;
    };

    my $reports_param = sub {
	my $qq = CGI->new($q);
	$qq->param("reports", 1);
	if ($qq->param("author")) {
	    $qq->delete("author");
	    $qq->param("dist", "$dist $dist_version");
	}
	$qq;
    };

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
			my $level = (grep {$acts->{$act} & $_} 16, 8, 4, 2, 1)[0];
			$level = 16 if !defined $level;
			push @cell, qq{<td width="${percent}%" class="action_${act} action_${act}_$level"></td>};
			push @title, $act.":".$acts->{$act};
		    }
		}
		my $title = join(" ", @title);
		my $qq = $reports_param->();
		$qq->param("os", $osname);
		$qq->param("perl", $perl);
		push @row, qq{<a href="@{[ $qq->self_url ]}"><table title="$title" class="bt" width="100%"><tr>} . join(" ", @cell) . qq{</tr></table></a>};
	    } else {
		push @row, "&nbsp;";
	    }
	}
	{
	    my $qq = $reports_param->();
	    $qq->param("perl", $perl);
	    unshift @row, qq{<a href="@{[ $qq->self_url ]}">$perl</a>};
	}
	push @matrix, \@row;
    }

    my $table = HTML::Table->new(-data => \@matrix,
				 -head => [
					   do {
					       my $qq = $reports_param->();
					       qq{<a href="@{[ $qq->self_url ]}">ALL</a>};
					   },
					   (map {
					       my $osname = $_;
					       my $qq = $reports_param->();
					       $qq->param("os", $osname);
					       qq{<a href="@{[ $qq->self_url ]}">$osname</a>};
					   } @osnames),
					  ],
				 -spacing => 0,
				);
    $table->setColHead(1);
    {
	my $cols = @osnames+1;
	$table->setColWidth($_, int(100/$cols)."%") for (1 .. $cols);
	#$table->setColAlign($_, 'center') for (1 .. $cols);
    }

    my $title = "$dist $dist_version";
    my $ct_link = "http://$ct_domain/show/$dist.html#$dist-$dist_version";

    return { table => $table,
	     title => "$dist $dist_version",
	     ct_link => $ct_link,
	   };
}

sub show_legend {
 	print <<EOF;
<div style="float:left; margin-left:3em; margin-bottom:5px;">
  <h2>Legend</h2>
  <table>
EOF
	if ($q->param("maxver")) {
	    print <<EOF;
    <tr><td width="50" class="maxver_PASSNEW"></td><td>PASS newest</td></tr>
    <tr><td width="50" class="maxver_PASSANY"></td><td>PASS some older version</td></tr>
    <tr><td width="50" class="maxver_NONE"></td><td>no PASS at all (either FAIL, UNKNOWN, NA, or INVALID)</td></tr>
EOF
	} else {
	    for my $act (@actions) {
		print <<EOF;
    <tr>
      <td width="50" class="action_$act"></td><td>$act</td>
    </tr>
EOF
	    }
	}
	print <<EOF;
  </table>
</div>
EOF
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
		push @row, qq{<div class="maxver_NONE">&nbsp;</div>};
	    } elsif ($maxver{$perl}->{$osname} ne $maxver) {
		push @row, qq{<div class="maxver_PASSANY">$maxver{$perl}->{$osname}</div>};
	    } else {
		push @row, qq{<div class="maxver_PASSNEW">$maxver</div>};
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
	     ct_link => "http://$ct_domain/show/$dist.html",
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
	     ct_link => "http://$ct_domain/author/$author.html",
	   };
}

# Sets the globals $dist and $dist_version
sub set_dist_and_version ($) {
    my $raw_dist = shift;
    my $_dist = basename $raw_dist;
    if ($_dist =~ m{^(.*) (.*)}) {
	($dist, $dist_version) = ($1, $2);
    } elsif ($_dist =~ m{^Acme-(?:24|6502)$}) { # XXX heuristics to get Acme-6502 right, need a better solution!
	# keep existing global $dist
    } elsif ($_dist =~ m{^(.*)[- ](v?[\d\._]+)$}) {
	($dist, $dist_version) = ($1, $2);
    }
}

# Sets the globals $dist_version
sub set_newest_dist_version {
    my($data) = @_;
    if (!$dist_version) {
	$dist_version = reduce { cmp_version($a,$b) > 0 ? $a : $b } map { $_->{version} } grep { $_->{version} } @$data;
    }
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

sub get_ua () {
    require LWP;
    LWP->VERSION(5.808); # bugs in decoded_content
    require LWP::UserAgent;
    return $UA if $UA;
    $UA = LWP::UserAgent->new;
    $UA->timeout($ua_timeout);
    ## Does not help, www.cpantesters.org does not send compressed yaml files
    #$UA->default_headers->push_header(Accept_encoding => 'gzip');
    $UA;
}

sub fetch_error_check ($) {
    my $resp = shift;
    if ($resp->status_line =~ /timeout/i) {
	<<EOF;
Timeout while fetching data from $ct_domain.
EOF
    } elsif ($resp->code == 500) {
	<<EOF;
Error while fetching data from $ct_domain: <@{[ $resp->status_line ]}>
EOF
    } else {
	"";
    }
}

BEGIN {
    # version 0.74 has some strange "Invalid version object" bug
    if (eval { require version; version->VERSION(0.76); 1 }) {
	*cmp_version = sub {
	    local $^W;
	    safe_version($_[0]) <=> safe_version($_[1]);
	};
	*safe_version = sub {
	    my $version_string = shift;
	    while(length $version_string) {
		my $version = eval { version->new($version_string) };
		if (!$@) {
		    return $version;
		}
		$version_string = substr($version_string,0,-1);
	    }
	    "0";
	};
    } else {
	*cmp_version = sub {
	    CPAN::Version->vcmp($_[0], $_[1]);
	};
    }
}

sub stylesheet_hicontrast {
    <<EOF;
  .action_PASS    { background:#00ff00; }
  .action_NA      { background:#0000c0; }
  .action_UNKNOWN { background:#0000c0; }
  .action_FAIL    { background:#800000; }
  .action_INVALID { background:#0000c0; }
EOF
}

sub stylesheet_cpantesters {
    <<EOF;
  .action_PASS    { background:#5ad742; }
  .action_NA      { background:#d6d342; }
  .action_UNKNOWN { background:#d6d342; }
  .action_FAIL    { background:#d63c39; }
  .action_INVALID { background:#d6d342; }
EOF
}

sub stylesheet_matrix {
    <<EOF;
  .action_PASS    { background:green;  }
  .action_NA      { background:orange; }
  .action_UNKNOWN { background:orange; }
  .action_FAIL    { background:red;    }
  .action_INVALID { background:orange; }
EOF
}

sub stylesheet_gradients {
    <<EOF;
  .action_PASS       { background: #5ad742; }
  .action_PASS_1     { background: #7af762; }
  .action_PASS_2     { background: #5ad742; }
  .action_PASS_4     { background: #3ab722; }
  .action_PASS_8     { background: #1a9702; }
  .action_PASS_16    { background: #0a7700; }

  .action_NA         { background: #e6f362; }
  .action_NA_1       { background: #ffff82; }
  .action_NA_2       { background: #e6f362; }
  .action_NA_4       { background: #d6d342; }
  .action_NA_8       { background: #b6b322; }
  .action_NA_16      { background: #969302; }

  .action_UNKNOWN    { background: #e6f362; }
  .action_UNKNOWN_1  { background: #ffff82; }
  .action_UNKNOWN_2  { background: #e6f362; }
  .action_UNKNOWN_4  { background: #d6d342; }
  .action_UNKNOWN_8  { background: #b6b322; }
  .action_UNKNOWN_16 { background: #969302; }

  .action_FAIL       { background: #f65c59; }
  .action_FAIL_1     { background: #ff7c79; }
  .action_FAIL_2     { background: #f65c59; }
  .action_FAIL_4     { background: #d63c39; }
  .action_FAIL_8     { background: #b61c19; }
  .action_FAIL_16    { background: #960c09; }

  .action_INVALID    { background: #e6f362; }
  .action_INVALID_1  { background: #ffff82; }
  .action_INVALID_2  { background: #e6f362; }
  .action_INVALID_4  { background: #d6d342; }
  .action_INVALID_8  { background: #b6b322; }
  .action_INVALID_16 { background: #969302; }
EOF
}

sub teaser {
    if ($q && !$q->param("maxver")) {
	print <<EOF;
<div style="margin-bottom:0.5cm; font-size:smaller; ">
  You can click on the matrix cells or row/column headers to get the list of corresponding reports.<br/>
  Alternative color schemes are available: try <i>View &gt; Page Style</i> or <i>View &gt; Use Style</i> in your browser.
</div>
EOF
    }
}

sub dist_links {
    (my $faked_module = $dist) =~ s{-}{::}g;
    my $dist_bugtracker_url = $dist_bugtracker_url || "https://rt.cpan.org/NoAuth/Bugs.html?Dist=$dist";
    print <<EOF;
<div style="float:left; margin-left:3em;">
<h2>Other links</h2>
<ul>
<li><a href="http://cpandeps.cantrell.org.uk/?module=$faked_module">CPAN Dependencies</a>
<li><a href="$ct_link">CPAN Testers</a>
<li><a href="http://search.cpan.org/dist/$dist/">search.cpan.org</a>
<li><a href="$dist_bugtracker_url">Bugtracker</a>
EOF
    if (defined $dist_version) {
	print <<EOF;
<li><a href="http://analysis.cpantesters.org/solved?distv=$dist-$dist_version">Reports analysis</a> (beta)
EOF
    }
    print <<EOF;
</ul>
</div>
EOF
}

sub get_amendments {
    my $amendments = {};
    eval {
	if (-r $amendments_st && -s $amendments_st && -M $amendments_st < -M $amendments_yml) {
	    $amendments = lock_retrieve $amendments_st;
	} elsif (-r $amendments_yml) {
	    require_yaml;
	    my $raw_amendments = yaml_load_file($amendments_yml);
	    for my $amendment (@{ $raw_amendments->{amendments} }) {
		for my $id (@{ $amendment->{id} }) {
		    $amendments->{$id} = $amendment;
		}
	    }
	    lock_nstore($amendments, $amendments_st);
	} else {
	    warn "$amendments_yml not readable!";
	}
    };
    warn $@ if $@;
    $amendments;
}

sub amend_result {
    my $result = shift;

    # Formerly it was called 'action', now it is 'status' (and there's
    # a 'state', which is lowercase)
    $result->{action} = $result->{status} if !exists $result->{action};
    # May happen in author YAMLs --- inconsistency!
    $result->{action} = $result->{state}  if !defined $result->{action};
    # Another one: 'archname' is now 'platform'
    $result->{archname} = $result->{platform} if !exists $result->{archname};
## This is not needed:
#    # canonify perl version: strip leading "v"
#    $result->{perl} =~ s{^v}{} if exists $result->{perl};

    my $id = $result->{id};
    my $action_comment;
    $amendments ||= get_amendments();
    if (defined $id && $amendments && exists $amendments->{$id}) {
	if (my $new_action = $amendments->{$id}->{action}) {
	    $result->{action} = $new_action;
	}
	$result->{action_comment} = $amendments->{$id}->{comment};
    }
}

sub cmp_version_with_patch {
    my($a, $b) = @_;
    for ($a, $b) {
	if (my($ver, $patch) = $_ =~ m{^(\S+)\s+patch\s+(\S+)}) {
	    no warnings 'numeric';
	    $_ = $ver . "." . sprintf("%09d", $patch);
	}
    }
    cmp_version($a, $b);
}

sub require_yaml () {
    if (eval { require YAML::Syck; 1 }) {
	*yaml_load      = \&YAML::Syck::Load;
	*yaml_load_file = \&YAML::Syck::LoadFile;
    } else {
	require YAML;
	*yaml_load      = \&YAML::Load;
	*yaml_load_file = \&YAML::LoadFile;
    }
}

# REPO BEGIN
# REPO NAME trim /home/e/eserte/work/srezic-repository 
# REPO MD5 ab2f7dfb13418299d79662fba10590a1

=head2 trim($string)

=for category Text

Trim starting and leading white space and squeezes white space to a
single space.

=cut

sub trim ($) {
    my $s = shift;
    return $s if !defined $s;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    $s =~ s/\s+/ /;
    $s;
}
# REPO END

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

=head1 TODO

=over

=item *

Move the alternative stylesheet selection into a HTML menu, so it's
accessible for every browser. Plus, the user's choice might be stored
in a cookie.

=item *

The incoming YAML data has redundant data --- remove all the
redundancy before creating the Storable file.

=back

=head1 PREREQUISITES

CPAN::DistnameInfo, HTML::Table, List::Util, LWP, Storable, version,
XML::LibXML, YAML::Syck.

=head1 COREQUISITES

Gravatar::URL

=head1 SCRIPT CATEGORIES

CPAN

=head1 AUTHOR

Slaven ReziE<0x107>

=head1 SEE ALSO

L<http://cpandeps.cantrell.org.uk/>,
L<http://www.cpantesters.org/> (new),
L<http://cpantesters.perl.org/> (old)

=cut
