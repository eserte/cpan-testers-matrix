#!/usr/bin/perl -T
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2007,2008,2009,2010,2011,2012,2013,2014,2015 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
#

package # not official yet
    CPAN::Testers::Matrix;

use strict;
use warnings;
use vars qw($VERSION);
$VERSION = '2.20';

use vars qw($UA);

use FindBin;
my $realbin;
BEGIN { ($realbin) = $FindBin::RealBin =~ m{^(.*)$} } # untaint it
use lib $realbin;

use CGI qw(escapeHTML);
#use CGI::Carp qw();
use CGI::Cookie;
use CPAN::Version;
use File::Basename qw(basename);
use HTML::Table;
use List::Util qw(reduce sum);
use POSIX qw(strftime);
use URI::Query 0.08 qw();

sub fetch_data ($);
sub fetch_author_data ($);
sub fetch_meta ($);
sub build_success_table ($$$);
sub build_maxver_table ($$);
sub build_author_table ($$);
sub get_cache_filename_from_dist ($$);
sub get_cache_filename_from_author ($$);
sub add_serializer_suffix ($);
sub cache_retrieve ($);
sub cache_store ($$);
sub meta_yaml_url ($);
sub meta_json_url ($);
sub get_ua ();
sub fetch_error_check ($);
sub set_dist_and_version ($);
sub get_perl_and_patch ($);
sub require_deserializer_dist ();
sub require_deserializer_author ();
sub require_yaml ();
sub require_json ();
sub beta_html ();
sub trim ($);
sub get_config ($);
sub obfuscate_from ($);
sub downtime_teaser ();
sub dist_version_url ($$$);
sub iso_date_to_epoch ($);

my $cache_days = 1/8;
my $ua_timeout = 10;

my $current_stable_perl = "5.22.0"; # please always end with ".0"

#use constant FILEFMT_AUTHOR => 'yaml';
use constant FILEFMT_AUTHOR => 'json';
#use constant FILEFMT_DIST   => 'yaml';
use constant FILEFMT_DIST   => 'json';

use constant USE_JQUERY_TABLESORTER => 1;

# XXX experiment, maybe use it by default?
use constant USE_IF_MODIFIED_SINCE => 0;

use constant JS_DEBUG => 0;

my $config_yml = "$realbin/cpantestersmatrix.yml";

# Two things:
# - if set, then the "log.txt" view is enabled, with
#   some changes in UI and caching
# - and this is the directory where the json files
#   are stored
my $static_dist_dir = get_config('static_dist_dir');
my $is_log_txt_view;
if ($static_dist_dir) {
    $is_log_txt_view = 1;
    $cache_days = 5/1440;
}

my $cache_root = (get_config("cache_root") || "/tmp/cpantesters_cache") . "_" . $<;
mkdir $cache_root, 0755 if !-d $cache_root;
my $dist_cache = "$cache_root/dist";
if (FILEFMT_DIST eq 'json') {
    $dist_cache .= '_json';
}
mkdir $dist_cache, 0755 if !-d $dist_cache;
my $author_cache = "$cache_root/author";
if (FILEFMT_AUTHOR eq 'json') {
    $author_cache .= '_json';
}
mkdir $author_cache, 0755 if !-d $author_cache;
my $meta_cache = "$cache_root/meta";
mkdir $meta_cache, 0755 if !-d $meta_cache;

my $serializer = get_config("serializer") || 'Storable';

my $amendments_yml = "$realbin/cpantesters_amendments.yml";
if (!-e $amendments_yml) {
    # Maybe using the cgi-bin/data layout?
    my $try = "$realbin/../data/cpantesters_amendments.yml";
    if (-e $try) {
	$amendments_yml = $try;
    }
}
(my $amendments_st = $amendments_yml) =~ s{\.yml$}{};
$amendments_st .= "." . $<;
$amendments_st = add_serializer_suffix($amendments_st);
my $amendments;

# XXX hmm, some globals ...
my $title = "CPAN Testers Matrix";

my $q = CGI->new;
if (eval { require Botchecker; 1 }) {
    eval {
	Botchecker::run($q);
    };
    warn $@ if $@;
}

my $is_beta = $q->script_name =~ /(cpantestersmatrix2|beta)/ || $q->virtual_host =~ m{\bbeta\b};

#XXX { local $ENV{PATH} = "/bin:/usr/bin";system("/usr/bin/ktrace", "-f", "/tmp/cpanktrace", "-p", $$);}

# XXX hmm, some globals ...
my $dist_title = "";
my @CORE_OSNAMES = qw(mswin32 cygwin darwin freebsd linux openbsd netbsd solaris);
my $new_ct_domain = "www.cpantesters.org";
my $ct_domain = $new_ct_domain;
my $ct_link = "http://$ct_domain";
my $dist_bugtracker_url;
#my $report_rooturl = "http://nntp.x.perl.org/group/perl.cpan.testers/";
my $report_rooturl = "http://www.cpantesters.org/cpan/report/";
my $table;
my $tables;
my $cachefile;
my $reports_header;
my $report_stats;

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
my $meta_fetched_from;

my @actions = qw(PASS NA UNKNOWN INVALID FAIL);

my %prefs = do {
    my %cookies = CGI::Cookie->fetch;
    my $cookie = $cookies{preferences}
	if exists $cookies{preferences};

    my $do_set_cookie;
    if ($update_prefs || !$cookie) {
	$cookie = CGI::Cookie->new(
	    -name    => 'preferences',
	    -expires => '+75y',
	    -value   => {
		stylesheet  => do {
		    my $requested = $update_prefs && trim $q->param('stylesheet');
		    defined $requested && exists $stylesheets{$requested}
			? $requested : 'matrix';
		},
		steal_focus => (defined $q->param('steal_focus') ? 1 : 0),
		exclude_old_devel => (defined $q->param('exclude_old_devel') ? 1 : 0),
	    },
	);
	$do_set_cookie = 1;
    }

    print $q->header(
	($do_set_cookie ? (-cookie => [$cookie]) : ()),
	-expires => (
		     $edit_prefs            ? 'now' : # prefs page
		     $q->query_string eq '' ? '+1d' : # home page
		     '+'.int($cache_days*1440).'m'    # any other page
		    ),
    );

    $cookie->value;
};

my $first_report_epoch;
my $last_report_epoch;

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
	$cachefile = $r->{cachefile}; # used in footer
	set_newest_dist_version($r->{data});
	apply_data_from_meta($dist);
	my @reports;
	for my $rec (@{ $r->{data} }) {
	    next if defined $dist_version && $rec->{version} ne $dist_version;
	    my($perl, $patch) = eval { get_perl_and_patch($rec) };
	    next if !$perl;
	    next if defined $want_perl && $perl ne $want_perl;
	    next if $prefs{exclude_old_devel} && is_old_devel_perl($perl);
	    next if defined $want_os && $rec->{osname} ne $want_os;
	    push @reports, $rec;
	    $rec->{patch} = $patch;
	}
	my $last_action;
	my @matrix;
	# By chance, lexical ordering fits for sort=action: FAIL is first.
	no warnings 'uninitialized';

	my @sort_column_defs = map {
	    my($sort_order, $sort_column) = $_ =~ m{^(-|\+)?(.*)};
	    $sort_order = '+' if !$sort_order;
	    [$sort_order, $sort_column];
	} @sort_columns;

	for my $rec (sort {
	    my $res = 0;
	    for my $sort_column_def (@sort_column_defs) {
		my($sort_order, $sort_column) = @$sort_column_def;
		if      ($sort_column eq 'osvers') {
		    $res = cmp_version($a->{$sort_column}, $b->{$sort_column});
		} elsif ($sort_column eq 'perl') {
		    $res = cmp_version_with_patch($a->{$sort_column}, $b->{$sort_column});
		} elsif ($sort_column eq 'id') {
		    $res = $a->{$sort_column} <=> $b->{$sort_column};
		} else {
		    $res = $a->{$sort_column} cmp $b->{$sort_column};
		}
		if ($sort_order eq '-') {
		    $res *= -1;
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
			    $rec->{tester},
			    $rec->{fulldate},
			    $action_comment_html,
			  ];
	}

	my $leader_sort_order = $sort_column_defs[0]->[0];
	my $sort_href;
	if (USE_JQUERY_TABLESORTER) {
	    $sort_href = sub {
		my($label, $column) = @_;
		$label;
	    };
	} else {
	    $sort_href = sub {
		my($label, $column) = @_;
		my $qq = CGI->new($q);
		my $this_is_leader_column = $sort_column_defs[0]->[1] eq $column;
		my $this_sort_order = ($this_is_leader_column
				       ? ($leader_sort_order eq '+' ? '-' : '+') # toggle
				       : '+'                                     # always ascending
				      );
		my @new_sort_column_defs = (
					    [$this_sort_order, $column],
					    grep { $_->[1] ne $column } @sort_column_defs
					   );
		$qq->param("sort", map {
		    my($sort_order, $column) = @$_;
		    $sort_order = '' if $sort_order eq '+'; # some browsers cannot deal with a (correctly escaped) +
		    $sort_order . $column;
		} @new_sort_column_defs);
		qq{<a href="@{[ $qq->self_url ]}">$label</a>} .
		    ($this_is_leader_column ? ' ' . ($leader_sort_order eq '+' ? '&#x25BC;' : '&#x25B2;') : '');
	    };
	}
	my @head = (
		    $sort_href->("Result", "action"),
		    $sort_href->("Id", "id"),
		    $sort_href->("OS vers", "osvers"),
		    $sort_href->("archname", "archname"),
		    (!defined $dist_version ? $sort_href->("Dist version", "version") : ()),
		    (!defined $want_perl    ? $sort_href->("Perl version", "perl") : ()),
		    (!defined $want_os      ? $sort_href->("OS", "osname") : ()),
		    ( defined $want_perl    ? $sort_href->("Perl patch/RC", "patch") : ()),
		    $sort_href->("Tester", "tester"),
		    $sort_href->("Date", "fulldate"),
		    $sort_href->("Comment", "action_comment"),
		   );
	$table = HTML::Table->new(
				  -spacing => 0,
				  -class   => 'reports' . (USE_JQUERY_TABLESORTER ? ' tablesorter' : ''),
				 );
	$table->setAttr('id="reports"');
	$table->addSectionRow('thead', 0, @head);
	$table->setSectionRCellsHead('thead', 0, 1, 1);
	for my $data_row (@matrix) {
	    $table->addSectionRow('tbody', 0, @$data_row);
	}
	$table->setSectionColHead('tbody', 0, 1, 1);
	$dist_title = ": $dist $dist_version";
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
	$dist_title = ": $r->{title}";
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
	    apply_data_from_meta($dist);
	    $r = build_success_table($data, $dist, $dist_version);
	    if ($r->{first_report_date}) {
		$first_report_epoch = iso_date_to_epoch $r->{first_report_date};
	    }
	    if ($r->{last_report_date}) {
		$last_report_epoch = iso_date_to_epoch $r->{last_report_date};
	    }
	    $report_stats = join("<br>\n",
				 ($r->{first_report_date} ? qq{First report: <i id="first_report_date">$r->{first_report_date} UTC</i>} : ()),
				 ($r->{last_report_date}  ?  qq{Last report: <i id="last_report_date" >$r->{last_report_date} UTC</i>} : ()),
				 (%{ $r->{total_actions} } ? (map { qq{<span class="action_$_">&nbsp;</span> $_: $r->{total_actions}->{$_}} } keys %{ $r->{total_actions} }) : ()),
				 ($r->{total_configurations} ? "Number of tested configurations: $r->{total_configurations}" : ()),
				);
	}
	$table = $r->{table};
	$ct_link = $r->{ct_link};
	$dist_title = ": $r->{title}";
    };
    $error = $@ if $@;
}

my $latest_distribution_string = $is_latest_version ? " (latest distribution)" : "";

print <<EOF;
<html>
 <head><title>$title$dist_title</title>
  <link type="image/ico" rel="shortcut icon" href="cpantesters_favicon.ico" />
  <link rel="apple-touch-icon" href="images/cpantesters_icon_57.png" />
  <link rel="apple-touch-icon" sizes="72x72" href="images/cpantesters_icon_72.png" />
  <link rel="apple-touch-icon" sizes="114x114" href="images/cpantesters_icon_114.png" />
  <link rel="search" href="/opensearch.xml" type="application/opensearchdescription+xml" title="CPAN Testers Matrix">
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

  h1>a            { color:black; text-decoration: none; }

  div.downtime_teaser { float:right; font-size:x-small; background-color:#fffff0; color:#000000; border: 1px solid black; -moz-border-radius:10px; border-radius:10px; padding:10px; }
EOF
if ($reports && USE_JQUERY_TABLESORTER) {
    print <<EOF;
  table.tablesorter thead tr .header {
    background-image: url(jquery.tablesorter.blue/bg.gif);
    background-repeat: no-repeat;
    background-position: center right;
    cursor: pointer;
    padding-right: 20px;
  }
  table.tablesorter thead tr .headerSortUp { background-image: url(jquery.tablesorter.blue/asc.gif); }
  table.tablesorter thead tr .headerSortDown { background-image: url(jquery.tablesorter.blue/desc.gif); }
EOF
}
print <<EOF;
  --></style>
  <script type="text/javascript">
  <!-- Hide script
  function focus_first() {
    var frm = document.forms[0];
    if (frm && frm["dist"] && typeof frm["dist"].focus == "function") {
      frm["dist"].focus();
    }
  }

EOF
print qq{  var js_debug = } . (JS_DEBUG ? 'true' : 'false') . ";\n";
print <<EOF;
  // End script hiding -->
  </script>
  <script type="text/javascript" src="matrix_cpantesters.js?v=20150419"></script>
EOF
if ($reports && USE_JQUERY_TABLESORTER) {
    print <<'EOF';
  <script type="text/javascript" src="jquery-1.9.1.min.js"></script>
  <script type="text/javascript" src="jquery.tablesorter.min.js"></script>
  <script type="text/javascript">
  <!-- Hide script
  $.tablesorter.addParser({ 
    id: 'versions', 
    is: function(s) { 
      // return false so this parser is not auto detected 
      return false; 
    }, 
    format: function(s) {
      var verArr = s.split(".");
      var makeInt = function(v) {
        var madeInt = parseInt(v);
        if (!isFinite(madeInt)) { madeInt = 0 }
        return madeInt;
      };
      var ret = makeInt(verArr[0]) + makeInt(verArr[1])/1000 + makeInt(verArr[2])/1000000;
      return ret;
    }, 
    type: 'numeric' 
  }); 
  $(document).ready(function() {
    var sl = [];
    if (window.location.hash && window.location.hash.match(/sl=(\d+),(\d+)/)) {
      sl = [[RegExp.$1,RegExp.$2]];
    }
    $("#reports").tablesorter({
      sortList: sl,
      headers: {
        2: {
          sorter:'versions'
        },
        4: {
          sorter:'versions'
        }
      }
    });
    $("#reports").bind("sortEnd",function() {
      var sl = this.config.sortList;
      if (sl != null && sl.length) {
        window.location.hash = "sl=" + sl[0][0] + "," + sl[0][1];
      }
    });
  });
  // End script hiding -->
  </script>
EOF
}
print <<EOF;
 </head>
EOF
my $downtime_teaser = downtime_teaser;
my $cachefile_time;
if ($cachefile) {
    $cachefile_time = (stat($cachefile))[9];
}
print qq{<body onload="} .
    ($prefs{steal_focus} ? qq{focus_first(); } : '') .
    ($downtime_teaser ? qq{rewrite_server_datetime(); } : '') .
    ($first_report_epoch ? qq{new DynamicDate($first_report_epoch, 'first_report_date', {no_seconds:true, debug:js_debug}); } : '') .
    ($last_report_epoch  ? qq{new DynamicDate($last_report_epoch,  'last_report_date',  {no_seconds:true, debug:js_debug}); } : '') .
    ($cachefile_time     ? qq{new DynamicDate($cachefile_time,     'cachedate',         {no_seconds:true, debug:js_debug}); } : '') .
    (0                   ? qq{shift_reload_alternative(); } : '') .
    qq{">\n};
{
    my $h1_innerhtml = $title . ($is_beta ? beta_html : '') . escapeHTML($dist_title);
    if ($latest_distribution_string ne '') {
	$h1_innerhtml .= qq{<span class="unimpt">$latest_distribution_string</span>};
    }
    if (defined $dist && defined $dist_version) {
	$h1_innerhtml = '<a href="' . dist_version_url($q, $dist, $dist_version) . '">' . $h1_innerhtml . '</a>';
    }
    print "<h1>$h1_innerhtml</h1>\n";
}

if ($is_log_txt_view) {
    print <<EOF;
<div class="warn">NOTE: This is the <a href="http://metabase.cpantesters.org/tail/log.txt">log.txt</a> view <span class="sml">(<a href="http://www.nntp.perl.org/group/perl.cpan.testers.discuss/2012/11/msg2906.html">What's this?</a>)</span></div><br/>
EOF
}

if ($error) {
    my $html_error = escapeHTML($error);
    $html_error =~ s{\n}{<br/>\n}g;
    print <<EOF;
<div class="warn">
  An error was encountered:<br/>$html_error<br/>
</div>
EOF
}
if ($downtime_teaser) {
    print $downtime_teaser;
}

print <<EOF;
  <form onsubmit="reset_location_hash()">
   <div>
    Distribution <span class="unimpt">(e.g. DBI, CPAN-Reporter, YAML-Syck)</span>: <input name="dist" /> <input type="submit" />
EOF
if ($q->param('maxver')) {
    print <<EOF;
    <input type="hidden" name="maxver" value="@{[ $q->param("maxver") ]}" />
EOF
}
print <<EOF;
   </div>
  </form>

  <form onsubmit="reset_location_hash()">
   <div>
    CPAN User ID <span class="unimpt">(e.g. TIMB, JHI, ANDK)</span>: <input name="author" /> <input type="submit" />
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

    if (USE_JQUERY_TABLESORTER) {
	print <<EOF;
<noscript><div style="margin-top:5px; font-size:smaller;">Column sorting is only possible with Javascript enabled!</div></noscript>
EOF
    }

    dist_links();

} elsif ($author) {

    teaser();

    if ($tables) {
	print qq{<ul>\n};
	for my $r (@$tables) {
	    print qq{<li><a href="#$r->{anchor}">$r->{title}</a></li>\n};
	}
	print qq{</ul>\n};

	for my $r (@$tables) {
	    print qq{<h2><a href="$r->{ct_link}" name="$r->{anchor}">$r->{title}</a></h2>};
	    print $r->{table};
	}
    }

    print <<EOF;
<div style="float:left;">
<h2>Other links</h2>
<ul>
<li><a href="$ct_link">CPAN Testers</a>
<li><a href="http://search.cpan.org/~$author/">search.cpan.org</a>
<li><a href="https://metacpan.org/author/$author/">metacpan.org</a>
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
	    $qq->delete("maxver");
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
	my $seen_latest_version = defined $latest_version && cmp_version($latest_version, $dist_version) == 0;
	my $possibly_outdated_meta;
	for my $version (sort { cmp_version($b, $a) } keys %other_dist_versions) {
	    $html .= qq{<li><a href="@{[ dist_version_url($q, $dist, $version) ]}">$dist $version</a>};
	    if (defined $latest_version && cmp_version($latest_version, $version) == 0) {
		$html .= qq{ <span class="sml"> (latest distribution};
		if ($meta_fetched_from) {
		    $html .= qq{ according to <a href="$meta_fetched_from">latest META file</a>};
		}
		$html .= qq{)</span>};
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
	if (defined $latest_version && !$seen_latest_version) {
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

    if ($report_stats) {
	show_stats($report_stats);
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
	$q->print(qq{<label style="padding-right:1em;"><input type="radio" name="stylesheet" value="$stylesheet" $selected>$stylesheets{$stylesheet}{name}</input></label>});
    }

    my $steal_focus = $prefs{steal_focus}
	? q{checked="checked"} : "";
    my $exclude_old_devel = $prefs{exclude_old_devel}
	? q{checked="checked"} : "";

    print <<"EOF"
    <br />

    <label for="steal_focus">Steal Focus:</label>
    <input type="checkbox" name="steal_focus" id="steal_focus" $steal_focus></input>

    <br />

    <label for="exclude_old_devel">Exclude old development versions:</label>
    <input type="checkbox" id="exclude_old_devel" name="exclude_old_devel" $exclude_old_devel></input>

    <br />

    <input type="submit" name="update_prefs" value="Update Preferences"></input>
  </fieldset>
</form>
EOF
}

print '<hr style="clear:left;">';

if ($cachefile) {
    my $file = basename $cachefile;
    my $datum = strftime("%Y-%m-%d %H:%M:%S UTC", gmtime($cachefile_time));
    print <<EOF;
  <div>
   <i>$file</i> as of <i id="cachedate">$datum</i> <span class="sml" id="shift_reload">Use Shift-Reload for forced update</span>
  </div>
EOF
}

my $sponsor_blurb = "";
use Sys::Hostname ();
if (Sys::Hostname::hostname eq "ds8143") {
    $sponsor_blurb = <<'EOF'
  <style>
    .webfusion {
      background-color: #000;
      color: #fff;
      background: -moz-linear-gradient(center top , #020802 0%, #282A28 100%) repeat scroll 0 0 rgba(0, 0, 0, 0);
      border-bottom: 4px solid #4FAB45;
      border-top: 2px solid #4FAB45;
      margin-top:1ex;
      padding-left:1em;
      padding-top:1ex;
      padding-bottom:1ex;
    }
    .webfusion a:link    { text-decoration:none; font-weight:bold; color: #fff; }
    .webfusion a:visited { text-decoration:none; font-weight:bold; color: #fff; }
    .webfusion a:hover   { text-decoration:none; font-weight:bold; color: #fff; }
    .webfusion a:active  { text-decoration:underline; font-weight:bold; color: #fff; }
    .webfusion img { vertical-align: middle; }
  </style>
  <div class="webfusion"><i>This site is gratefully hosted on a <a href="http://www.webfusion.co.uk/dedicated-servers/">Dedicated Server</a>, sponsored by <a alt="Webfusion" href="http://www.webfusion.co.uk"><img src="http://www.webfusion.co.uk/library/images/logo.png"/></a></i></div>
EOF
}

print <<EOF;
  <div>
   <span class="sml"><a href="?prefs=1">Change Preferences</a></span>
  </div>
  <div>
   <a href="http://github.com/eserte/cpan-testers-matrix">cpantestersmatrix.pl</a> $VERSION
   by <a href="http://search.cpan.org/~srezic/">Slaven Rezi&#x0107;</a>
  </div>$sponsor_blurb
@{[ defined &Botchecker::zdjela_meda ? Botchecker::zdjela_meda() : '' ]}
 </body>
</html>
EOF

sub fetch_meta ($) {
    my($dist) = @_;

    my $meta;

    my $cachefile = get_cache_filename_from_dist($meta_cache, $dist);
    if (!-r $cachefile || -M $cachefile > $cache_days ||
	($ENV{HTTP_CACHE_CONTROL} && $ENV{HTTP_CACHE_CONTROL} eq 'no-cache')
       ) {
	my @errors;

	my $ua = get_ua;

	my $fetch_meta_yaml_from_sco = sub {
	    require_yaml;
	    my $yaml_url = meta_yaml_url($dist);
	    my $yaml_resp = $ua->get($yaml_url);
	    if ($yaml_resp->is_success) {
		my $yaml = $yaml_resp->decoded_content;
		if (length $yaml) {
		    eval {
			$meta = yaml_load($yaml);
			if ($meta) {
			    $meta->{__fetched_from} = $yaml_url;
			}
		    };
		    if ($@) {
			push @errors, "While deserializing meta data from <$yaml_url>: $@";
		    }
		} else {
		    push @errors, "Got empty YAML from <$yaml_url>";
		}
	    } else {
		push @errors, "No success fetching <$yaml_url>: " . $yaml_resp->status_line;
	    }
	};

	my $fetch_meta_json_from_sco = sub {
	    require_json;
	    my $json_url = meta_json_url($dist);
	    my $json_resp = $ua->get($json_url);
	    if ($json_resp->is_success) {
		my $json = $json_resp->decoded_content(charset => 'none');
		if (length $json) {
		    eval {
			$meta = json_load($json);
			if ($meta) {
			    $meta->{__fetched_from} = $json_url;
			}
		    };
		    if ($@) {
			push @errors, "While deserializing meta data from $json_url: $@";
		    }
		} else {
		    push @errors, "Got empty JSON from <$json_url>";
		}
	    } else {
		push @errors, "No success fetching <$json_url>: " . $json_resp->status_line;
	    }
	};

	my $fetch_meta_json_from_metacpan = sub {
	    require_json;
	    my $api_url = "http://api.metacpan.org/release/" . $dist;
	    my $api_resp = $ua->get($api_url);
	    if ($api_resp->is_success) {
		my $json = $api_resp->decoded_content(charset => 'none');
		if (length $json) {
		    eval {
			my $data = json_load($json);
			$meta = $data->{metadata};
			if ($meta) {
			    $meta->{__fetched_from} = $api_url;
			}
		    };
		    if ($@) {
			push @errors, "While deserializing meta data from $api_url: $@";
		    }
		} else {
		    push @errors, "Got empty JSON from <$api_url>";
		}
	    } else {
		push @errors, "No success fetching <$api_url>: " . $api_resp->status_line;
	    }
	};

	$fetch_meta_json_from_metacpan->();
	if (!$meta) {
	    warn "Could not get META from metacpan API, errors so far: " . join("; ", @errors);
	    $fetch_meta_yaml_from_sco->();
	    if (0 && !$meta) {
		$fetch_meta_json_from_sco->();
	    }
	}

	if ($meta) {
	    eval {
		cache_store $meta, $cachefile;
	    };
	    if ($@) {
		warn "Failed to cache the meta data into $cachefile: $@";
	    }
	} else {
	    eval {
		cache_store {}, $cachefile;
	    };
	    warn "Could not get META: " . (!@errors ? "(but there are no errors?!)" : join("; ", @errors));
	}
    } else {
	$meta = cache_retrieve $cachefile
	    or warn "Could not load cached meta data";
    }
    return { meta => $meta,
	     cachefile => $cachefile,
	   };
}

sub fetch_data ($) {
    my($raw_dist) = @_;

    die "dist is missing\n" if !defined $raw_dist;

    my $data;

    set_dist_and_version($raw_dist);
    my $orig_dist = $dist;
    if ($dist =~ m{::}) {
	my $resolve_module_to_dist_sub = sub {
	    my $cpan_home = get_config("cpan_home");
	    die "cpan_home not configued in $config_yml" if !$cpan_home;
	    my $plain_packages_file = get_config("plain_packages_file");
	    die "plain_packages_file not configued in $config_yml" if !$plain_packages_file;
	    my $packages_file = "$cpan_home/sources/modules/02packages.details.txt.gz";
	    die "$packages_file not readable" if !-r $packages_file;
	    require Parse::CPAN::Packages::Fast;
	    die "Old PCPF without _module_lookup" if !Parse::CPAN::Packages::Fast->can('_module_lookup');

	    my $ret = Parse::CPAN::Packages::Fast->_module_lookup($dist, $packages_file, $plain_packages_file . '_' . $<);
	    return if !$ret || !$ret->{dist};
	    my $d = CPAN::DistnameInfo->new($ret->{dist});
	    return if !$d;
	    $d->dist;
	};
	my $maybe_dist = eval { $resolve_module_to_dist_sub->() };
	if ($@) {
	    warn $@;
	    $dist =~ s{::}{-}g; # simple
	} elsif ($maybe_dist) {
	    $dist = $maybe_dist;
	} else {
	    die <<EOF;
Module <$dist> is unknown.
EOF
	}
    }

    my $resp;
    my $good_cachefile;
    my $url;
    my $cachefile = get_cache_filename_from_dist($dist_cache, $dist);
    my $error;

    # Avoid multiple simultaneous fetches
    my $lckfile = "$cachefile.lck";
    my $lckobj = CPAN::Testers::Matrix::LockFile->new($lckfile);

 GET_DATA: {
	if (-r $cachefile && -M $cachefile < $cache_days &&
	    (!$ENV{HTTP_CACHE_CONTROL} || $ENV{HTTP_CACHE_CONTROL} ne 'no-cache')
	   ) {
	    $good_cachefile = $cachefile;
	    last GET_DATA;
	}

	require_deserializer_dist;

	my $ua = get_ua;

	if ($static_dist_dir) {
	    if ($dist =~ m{/}) {
		die "Invalid distribution name";
	    }
	    $url = "file://$static_dist_dir/$dist." . FILEFMT_DIST;
	} else {
	    $url = "http://$ct_domain/show/$dist." . FILEFMT_DIST;
	}

	my $fetch_dist_data = sub {
	    my($dist) = @_;
	    my $req = HTTP::Request->new('GET', $url);
	    if (USE_IF_MODIFIED_SINCE && $url =~ m{^http}) {
		if (!$ENV{HTTP_CACHE_CONTROL} || $ENV{HTTP_CACHE_CONTROL} ne 'no-cache') {
		    if (my $mtime = (stat($cachefile))[9]) {
			$req->if_modified_since($mtime);
		    }
		}
	    }
	    my $resp = $ua->request($req);
	    $resp;
	};

	$resp = $fetch_dist_data->($dist);
	last GET_DATA if $resp->is_success;

	if ($resp->code == 404) {
	    die <<EOF
Distribution results for <$dist> at <$url> not found.
Maybe you mistyped the distribution name?
Maybe you added the author name to the distribution string?
Note that the distribution name is case-sensitive.
EOF
	} elsif ($resp->code == 304) {
	    if (!-r $cachefile) {
		die <<EOF;
Unexpected error: got 304 Not Modified, but cached file
'$cachefile' does not exist anymore or is not readable.
EOF
	    }
	    my $new_mtime = $resp->date;
	    if ($new_mtime) {
		utime $new_mtime, $new_mtime, $cachefile;
	    }
	    $good_cachefile = $cachefile;
	    last GET_DATA;
	}

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

	warn "Unknown error, should never happen: ". $resp->headers->as_string;
	die "Unknown error, should never happen";
    }

    if ($good_cachefile) {
	$data = cache_retrieve $cachefile
	    or die "Could not load cached data";
	# Fix distribution name
	eval { $dist = $data->[-1]->{distribution} };
    } elsif ($resp && $resp->is_success) {
	eval {
	    $data = deserialize_dist($resp->decoded_content)
	};
	if ($@ || !$data) {
	    my $msg = "Could not load " . (FILEFMT_DIST eq 'yaml' ? 'YAML' : 'JSON') . " data from <$url>";
	    no warnings 'uninitialized'; # $@ may be undef
	    warn "$msg. Error: '$@'";
	    die "$msg\n";
	}
	for(my $result_i = 0; $result_i <= $#$data; $result_i++) {
	    my $result = $data->[$result_i];
	    amend_result($result);
	    if (remove_result($result)) {
		splice @$data, $result_i, 1;
		$result_i--;
	    }
	}
	eval {
	    cache_store $data, $cachefile;
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
    if (!length $author) {
	die "Invalid CPAN user id.\n";
    }

    my $author_dist = {};

    my $resp;
    my $good_cachefile;
    my $url;
    my $cachefile = get_cache_filename_from_author($author_cache, $author);
    my $error;

    # Avoid multiple simultaneous fetches
    my $lckfile = "$cachefile.lck";
    my $lckobj = CPAN::Testers::Matrix::LockFile->new($lckfile);

 GET_DATA: {
	if (-r $cachefile && -M $cachefile < $cache_days &&
	    (!$ENV{HTTP_CACHE_CONTROL} || $ENV{HTTP_CACHE_CONTROL} ne 'no-cache')
	   ) {
	    $good_cachefile = $cachefile;
	    last GET_DATA;
	}

	require CPAN::DistnameInfo;

	my $ua = get_ua;
	$url = "http://$new_ct_domain/author/$author." . FILEFMT_AUTHOR;

	# check first if the file is too large XXX should not be necessary :-(
	my $head_resp = $ua->head($url);
	last GET_DATA if !$head_resp->is_success;
	my $content_length = $head_resp->content_length;
	if (defined $content_length) {
	    my $max_content_length = $] >= 5.014 ? 150_000_000 : 15_000_000;
	    if ($content_length > $max_content_length) {
		my $msg = <<EOF;
Sorry, $url is too large to be processed (content-length: $content_length)
EOF
		warn $msg; # for error.log
		die $msg;
	    }
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
	$author_dist = cache_retrieve $cachefile
	    or die "Could not load cached data";
    } elsif ($resp && $resp->is_success) {
	require_deserializer_author;
	my $data = deserialize_author($resp->decoded_content);
	for my $result (@$data) {
	    my $dist;
	    if (defined $result->{dist}) { # new style
		$dist = $result->{distribution} = $result->{dist};
	    } elsif (defined $result->{distribution}) { # old style
		$dist = $result->{dist} = $result->{distribution};
	    }
	    amend_result($result);
	    if (!remove_result($result)) {
		push @{$author_dist->{$dist}}, $result;
	    }
	}
	eval {
	    cache_store $author_dist, $cachefile;
	};
	if ($@) {
	    warn $!;
	    die "Internal error (nstore)";
	};
    } else {
	# no success
	undef $cachefile;
	$error = "Cannot fetch author file <$url>\n";
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
    my %total_actions;
    my $first_report_date;
    my $last_report_date;

    for my $r (@$data) {
	if ($r->{version} ne $dist_version) {
	    $other_dist_versions{$r->{version}}++;
	    next;
	}
	my($perl, $patch) = get_perl_and_patch($r);
	$perl{$perl}++;
	$perl_patches{$perl}->{$patch}++ if $patch;
	my $osname = $r->{osname};
	$osname{$osname}++;

	my $action = $r->{action};
	$action{$perl}->{$osname}->{$action}++;
	$action{$perl}->{$osname}->{__TOTAL__}++;

	my $date = $r->{fulldate};
	if (defined $date) {
	    if (!defined $first_report_date || $first_report_date gt $date) {
		$first_report_date = $date;
	    }
	    if (!defined $last_report_date || $last_report_date lt $date) {
		$last_report_date = $date;
	    }
	}

	$total_actions{$action}++;
    }

    # Here trap errors in source yaml/json (perl version=0, osname="")
    my @perls   = grep { $_ } sort { CPAN::Version->vcmp($b, $a) } keys %perl;
    my @osnames = grep { $_ } sort { $a cmp $b } keys %osname;

    # Add "core" osnames to the list of existing ones
    @osnames = do {
	my %osnames = map { ($_,1) } (@osnames, @CORE_OSNAMES);
	sort keys %osnames;
    };

    my $reports_param = do {
	my $qq = CGI->new($q);
	$qq->param("reports", 1);
	if ($qq->param("author")) {
	    $qq->delete("author");
	    $qq->param("dist", "$dist $dist_version");
	}

	my $qs = $qq->query_string;

	sub { URI::Query->new($qs) };
    };

    my @matrix;
    my %acts_per_perl; # perl -> act -> count
    my %acts_per_osname; # osname -> act -> count
    for my $perl (@perls) {
	next if $prefs{exclude_old_devel} && is_old_devel_perl($perl);
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
			$acts_per_perl{$perl}->{$act}     += $acts->{$act};
			$acts_per_osname{$osname}->{$act} += $acts->{$act};
		    }
		}
		my $title = join(" ", @title);
		my $qq = $reports_param->();
		$qq->replace("os", $osname);
		$qq->replace("perl", $perl);
		push @row, qq{<a href="?@{[ $qq->stringify(";") ]}"><table title="$title" class="bt" width="100%"><tr>} . join(" ", @cell) . qq{</tr></table></a>};
	    } else {
		push @row, "&nbsp;";
	    }
	}
	{
	    my $qq = $reports_param->();
	    $qq->replace("perl", $perl);
	    my $title = join(" ", map { my $cnt = $acts_per_perl{$perl}->{$_}; $cnt ? "$_:$cnt" : () } @actions);
	    unshift @row, qq{<a title="$title" href="?@{[ $qq->stringify(";") ]}">$perl</a>};
	}
	push @matrix, \@row;
    }

    my $table = HTML::Table->new(-data => \@matrix,
				 -head => [
					   do {
					       my $qq = $reports_param->();
					       qq{<a href="?@{[ $qq->stringify(";") ]}">ALL</a>};
					   },
					   (map {
					       my $osname = $_;
					       my $qq = $reports_param->();
					       $qq->replace("os", $osname);
					       my $title = join(" ", map { my $cnt = $acts_per_osname{$osname}->{$_}; $cnt ? "$_:$cnt" : () } @actions);
					       qq{<a title="$title" href="?@{[ $qq->stringify(";") ]}">$osname</a>};
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
	     first_report_date => $first_report_date,
	     last_report_date => $last_report_date,
	     total_actions => \%total_actions,
	     total_configurations => sum map { scalar values %$_ } values %action,
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

sub show_stats {
    my($report_stats) = @_;
    print <<EOF;
<div style="float:left; margin-left:3em; margin-bottom:5px;">
  <h2>Stats</h2>
$report_stats
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
	$r->{anchor} = "$dist-$dist_version";
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
    } elsif ($_dist =~ m{^POSIX-1003$}) { # another heuristic
	# keep existing global $dist
    } elsif ($_dist =~ m{^POSIX-2008$}) { # another heuristic
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

# Return ($perl, $patch) where
# - $perl is the perl version like "5.20.0"
# - $patch is either a patch number or string (for non-released perls
#   in the p4 era), an RC, or undef if nothing applies
sub get_perl_and_patch ($) {
    my($r) = @_;
    my($perl, $rest) = $r->{perl} =~ m{^(\S+)(.*)};
    die "$r->{perl} couldn't be parsed" if !defined $perl;
    my $patch;
    if (defined $rest && length $rest) {
	if ($rest =~ m{^(?:\s+patch(?:level)?\s+(\S+))$}) {
	    $patch = $1;
	} elsif ($rest =~ m{^\s+(RC\d+)$}) {
	    $patch = $1;
	}
    }
    ($perl, $patch);
}

sub get_cache_filename_from_dist ($$) {
    my($cachedir, $dist) = @_;
    (my $safe_dist = $dist) =~ s{[^a-zA-Z0-9_.-]}{_}g;
    ($safe_dist) = $safe_dist =~ m{^(.*)$};
    add_serializer_suffix($cachedir."/".$safe_dist);
}

# Note: this function assumes that $author is already sanitized, see fetch_author_data
sub get_cache_filename_from_author ($$) {
    my($author_cache, $author) = @_;
    add_serializer_suffix($author_cache."/".$author);
}

sub add_serializer_suffix ($) {
    my($file) = @_;
    if ($serializer eq 'Sereal') {
	$file . '.sereal';
    } else {
	$file . '.st';
    }
}

sub meta_yaml_url ($) {
    my $dist = shift;
    "http://search.cpan.org/meta/$dist/META.yml";
}

sub meta_json_url ($) {
    my $dist = shift;
    "http://search.cpan.org/meta/$dist/META.json";
}

sub get_ua () {
    require LWP;
    LWP->VERSION(5.808); # bugs in decoded_content
    require LWP::UserAgent;
    return $UA if $UA;
    $UA = LWP::UserAgent->new;
    $UA->timeout($ua_timeout);
    ## Does not help, www.cpantesters.org does not send compressed yaml/json files
    #$UA->default_headers->push_header(Accept_encoding => 'gzip');
    $UA;
}

sub fetch_error_check ($) {
    my $resp = shift;
    my $msg;
    if ($resp->status_line =~ /timeout/i) {
	$msg = <<EOF;
Timeout while fetching data from $ct_domain: timeout=${ua_timeout}s
EOF
    } elsif ($resp->code == 500) {
	$msg = <<EOF;
Error while fetching data from $ct_domain: <@{[ $resp->status_line ]}>
EOF
    } elsif ($resp->code == 404) {
	$msg = <<EOF;
Cannot fetch data from $ct_domain (file not found)
EOF
    } elsif ($resp->header('Client-Warning') =~ m{Redirect loop detected}) {
	$msg = <<EOF;
Cannot fetch data from $ct_domain (redirect loop)
EOF
    } else {
	$msg = "";
    }
    if (length $msg) {
	warn $msg;
    }
    $msg;
}

BEGIN {
    # version 0.74 has some strange "Invalid version object" bug
    #
    # Later version.pm versions (e.g. 0.76 or 0.77) are quite noisy. For
    # example for Tk.pm there are a lot of warnings in the form:
    #   Version string '804.025_beta10' contains invalid data; ignoring: '_beta10'
    # CPAN::Version's vcmp is also OK and does not warn, so use it.
    if (0 && eval { require version; version->VERSION(0.76); 1 }) {
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
	    my($left,$right) = @_;
	    if ($left =~ m{-TRIAL} || $right =~ m{-TRIAL}) {
		($left,my($left_trial)) = $left =~ m{^(.*?)(-TRIAL\d*)?$};
		($right,my($right_trial)) = $right =~ m{^(.*?)(-TRIAL\d*)?$};
		my $cmp = CPAN::Version->vcmp($left, $right);
		return $cmp if $cmp != 0;
		if (defined $left_trial) {
		    if (defined $right_trial) {
			if ($left_trial eq $right_trial) {
			    return 0;
			}
			my($left_trial_number, $right_trial_number);
			for my $def (
				     [$left_trial,  \$left_trial_number],
				     [$right_trial, \$right_trial_number],
				    ) {
			    my($trial, $number_ref) = @$def;
			    $$number_ref = $trial =~ m{(\d+)$};
			    $$number_ref = 1 if !defined $$number_ref;
			}
			return $left_trial_number <=> $right_trial_number;
		    } else {
			return -1;
		    }
		} elsif (defined $right_trial) {
		    return +1;
		} else {
		    return 0;
		}
	    } else {
		CPAN::Version->vcmp($left, $right);
	    }
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
  You can click on the matrix cells or row/column headers to get the list of corresponding reports.
</div>
EOF
    }
}

sub dist_links {
    (my $faked_module = $dist) =~ s{-}{::}g;
    my $dist_bugtracker_url = $dist_bugtracker_url || "https://rt.cpan.org/Public/Dist/Display.html?Name=$dist";
    print <<EOF;
<div style="float:left; margin-left:3em;">
<h2>Other links</h2>
<ul>
<li><a href="http://deps.cpantesters.org/?module=$faked_module">CPAN Dependencies</a>
<li><a href="$ct_link">CPAN Testers</a>
<li><a href="http://search.cpan.org/dist/$dist/">search.cpan.org</a>
<li><a href="https://metacpan.org/release/$dist">metacpan.org</a>
<li><a href="$dist_bugtracker_url">Bugtracker</a>
EOF
    if (defined $dist_version) {
	print <<EOF;
<li><a href="http://analysis.cpantesters.org/solved?distv=$dist-$dist_version">Reports analysis</a> @{[ beta_html ]}
EOF
    }
    if ($is_log_txt_view) { # we're on the log.txt view, show link back
	print <<EOF;
<li><a class="sml" href="http://matrix.cpantesters.org/?@{[ $q->query_string ]}">Regular matrix</a> <span class="sml"></span>
EOF
    } else {
	print <<EOF;
<li><a class="sml" href="http://fast-matrix.cpantesters.org/?@{[ $q->query_string ]}">Matrix via log.txt</a> <!--<span class="sml">(temporary!)</span>-->
EOF
    }
    print <<EOF;
</ul>
</div>
EOF
}

{
    my $config;
    sub get_config ($) {
	my $key = shift;

	if (!$config) {
	    if (-r $config_yml) {
		require_yaml;
		$config = eval { yaml_load_file($config_yml) };
		if (!$config) {
		    warn "Failed to load $config_yml: $@";
		}
	    }
	    $config = {} if !$config; # mark that there was a load attempt
	}

	my $val = $config->{$key};
	no warnings 'uninitialized';
	($val) = $val =~ m{^(.*)$}; # we trust everything here
	$val;
    }
}

sub get_amendments {
    my $amendments = {};
    eval {
	if (-r $amendments_st && -s $amendments_st && -M $amendments_st < -M $amendments_yml) {
	    $amendments = cache_retrieve $amendments_st;
	} elsif (-r $amendments_yml) {
	    require_yaml;
	    my $raw_amendments = yaml_load_file($amendments_yml);
	    for my $amendment (@{ $raw_amendments->{amendments} }) {
		for my $id (@{ $amendment->{id} }) {
		    $amendments->{$id} = $amendment;
		}
	    }
	    cache_store $amendments, $amendments_st;
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
    # May happen in author YAML/JSONs --- inconsistency!
    $result->{action} = $result->{state}  if !defined $result->{action};
    # Another one: 'archname' is now 'platform'
    $result->{archname} = $result->{platform} if !exists $result->{archname};

    ## Happens after 2011-10 (again?)
    ## canonify perl version: strip leading "v"
    #$result->{perl} =~ s{^v}{} if exists $result->{perl};

    # Happens after 2013-XX
    # normalize osnames (everything should be lowercase now)
    if ($result->{osname}) {
	$result->{osname} = lc $result->{osname};
    }

    # Some normalizations
    $result->{fulldate} =~ s{^(....)(..)(..)(..)(..)$}{$1-$2-$3 $4:$5} if exists $result->{fulldate};
    $result->{tester} = obfuscate_from $result->{tester};

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

sub remove_result {
    my $result = shift;
    return 1 if $result->{action} && $result->{action} eq 'REMOVE';
    0;
}

sub apply_data_from_meta {
    my($dist) = @_;
    eval {
	my $r = fetch_meta($dist);
	my $meta = $r->{meta};
	$latest_version = $meta && defined $meta->{version} ? $meta->{version} : undef;
	$is_latest_version = defined $latest_version && defined $dist_version && cmp_version($latest_version, $dist_version) == 0;
	if ($meta) {
	    if ($meta->{resources} && $meta->{resources}->{bugtracker}) {
		if (ref $meta->{resources}->{bugtracker} eq 'HASH') {
		    $dist_bugtracker_url = $meta->{resources}->{bugtracker}->{web};
		} else {
		    $dist_bugtracker_url = $meta->{resources}->{bugtracker};
		}
	    }
	    if ($meta->{__fetched_from}) {
		$meta_fetched_from = $meta->{__fetched_from};
	    }
	}
    };
    warn $@ if $@;
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

sub is_old_devel_perl {
    my $perl = shift;
    return 0 if cmp_version($perl, $current_stable_perl) >= 0;
    if (my($major,$minor) = $perl =~ m{^(\d+)\.(\d+)}) {
	return 1 if $minor >= 7 && $minor%2==1;
	return 0;
    } else {
	return undef;
    }
}

sub require_deserializer_dist () {
    if (FILEFMT_DIST eq 'json') {
	require_json;
	*deserialize_dist      = \*json_load;
    } else {
	require_yaml;
	*deserialize_dist      = \*yaml_load;
    }
}

sub require_deserializer_author () {
    if (FILEFMT_AUTHOR eq 'json') {
	require_json;
	*deserialize_author      = \*json_load;
    } else {
	require_yaml;
	*deserialize_author      = \*yaml_load;
    }
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

sub require_json () {
    require JSON::XS;
    no warnings 'once';
    *json_load      = \&JSON::XS::decode_json;
    *json_load_file = sub {
	my $file = shift;
	open my $fh, $file or die $!;
	local $/;
	my $buf = <$fh>;
	JSON::XS::decode_json($buf);
    };
}

sub beta_html () {
    q{<span style="font-size:5pt; font-family: sans-serif; border:1px solid red; padding:0px 2px 0px 2px; background-color:yellow; color:black;">BETA</span>};
}

# Taken CPAN/Blame/Model/Solved.pm from git://repo.or.cz/andk-cpan-tools.git
sub obfuscate_from ($) {
    my $from = shift;
    my $obfuscated_from = $from;
    if ($from) {
	our %from_to_obfuscated;
	return $from_to_obfuscated{$from} if exists $from_to_obfuscated{$from};

	for ($obfuscated_from) {
	    s/\s+\(\(root|Charlie &\)\)$//; # "root" is meaningless, strip it
	    s/.+\(([^\)]+)\).*/$1/;
	    last if s/.*\(\"([^"]+)\"\)/$1/;
	    last if s/.+\(([^\)]+)\)/$1/;
	    last if s/\@([^.]+)\..+/ at $1/;
	    last if s/\@/.../;
	}
	for ($obfuscated_from) {
	    s/<.*//; # found <briang
	    s/\s+$//;
	    s/^\s+//;
	    s/^\"([^"]+)\"$/$1/;
	}

	$from_to_obfuscated{$from} = $obfuscated_from;
    }
    $obfuscated_from;
}

sub cache_store ($$) {
    my($data, $cachefile) = @_;
    if ($serializer eq 'Storable') {
	require Storable;
	Storable::lock_nstore($data, $cachefile);
    } elsif ($serializer eq 'Sereal') {
	require Sereal::Encoder;
	open my $ofh, ">", "$cachefile.$$"
	    or die "Can't write to $cachefile.$$: $!";
	print $ofh Sereal::Encoder::encode_sereal($data);
	close $ofh
	    or die "While writing to $cachefile.$$: $!";
	rename "$cachefile.$$", $cachefile
	    or die "While renaming $cachefile.$$ to $cachefile: $!";
    } else {
	die "Unknown serializer '$serializer'";
    }
}

sub cache_retrieve ($) {
    my($cachefile) = @_;
    if ($serializer eq 'Storable') {
	require Storable;
	Storable::lock_retrieve($cachefile);
    } elsif ($serializer eq 'Sereal') {
	require Sereal::Decoder;
	open my $fh, "<", $cachefile
	    or die "Can't read from $cachefile: $!";
	local $/;
	Sereal::Decoder::decode_sereal(<$fh>);
    } else {
	die "Unknown serializer '$serializer'";
    }
}

sub downtime_teaser () {
    my @downtimes = (
		     [1374012000, 1374033600], # 2013-07-17T06:00:00 CEST - 2013-07-17T00:00:00 CEST
		     [1374098400, 1374120000], # 2013-07-18T06:00:00 CEST - 2013-07-18T00:00:00 CEST
		     [1374616800, 1374638400], # 2013-07-24T06:00:00 CEST - 2013-07-24T00:00:00 CEST
		    );
    my @active_downtimes = grep { $_->[1] >= time } @downtimes;
    return if !@active_downtimes;

    my $html = '<div class="downtime_teaser">';
    $html .= '&#x26a0; There will be shorter downtimes of matrix.cpantesters.org in the following period' . (@active_downtimes > 1 ? 's' : '') . ":\n<ul>\n";
    for my $active_downtime (@active_downtimes) {
	my($from_epoch, $to_epoch) = @$active_downtime;
	my($from_iso, $to_iso) = map { strftime "%FT%T %Z", localtime $_ } $from_epoch, $to_epoch;
	$html .= qq{<li>from <span data-time="$from_epoch">$from_iso</span> until <span data-time="$to_epoch">$to_iso</span>}
    }
    $html .= "</ul></div>\n";
    $html;
}

sub dist_version_url ($$$) {
    my($q, $dist, $version) = @_;
    my $qq = CGI->new($q);
    $qq->param(dist => "$dist $version");
    $qq->self_url;
}

sub iso_date_to_epoch ($) {
    my $iso_date = shift;
    # may deal with partial ISO8601 date like "2013-04-06 10:32"
    # assume UTC timezone
    if (my($y,$m,$d,$H,$M,$S) = $iso_date =~ m{^(\d+)-(\d+)-(\d+) (\d+):(\d+)(?::(\d+))?}) {
	$S ||= 0;
	require Time::Local;
	Time::Local::timegm_nocheck($S,$M,$H,$d,$m-1,$y);
    } else {
	undef;
    }
}

{
    package # do not index
	CPAN::Testers::Matrix::LockFile;

    use Fcntl qw(LOCK_EX O_RDWR O_CREAT);

    sub new {
	my($class, $lckfile) = @_;
	die if !$lckfile;
	sysopen my $lck, $lckfile, O_RDWR | O_CREAT, 0644
	    or die "Can't write to $lckfile: $!";
	flock $lck, LOCK_EX
	    or die "Can't flock $lckfile: $!";
	bless { lck => $lck, lckfile => $lckfile }, $class;
    }

    sub DESTROY {
	my $self = shift;
	my $lckfile = $self->{lckfile};
	die if !$lckfile;
	unlink $lckfile;
    }
}

# REPO BEGIN
# REPO NAME trim /home/e/eserte/work/srezic-repository 
# REPO MD5 ab2f7dfb13418299d79662fba10590a1

# =head2 trim($string)
# 
# =for category Text
# 
# Trim starting and leading white space and squeezes white space to a
# single space.
# 
# =cut

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

This is a cgi or psgi script. See the INSTALL document in the
distribution for some installation hints.

=head1 NOTES

The script creates a predictable directory F<< /tmp/cpantesters_cache_$< >>

=head1 AUTHOR

Slaven ReziE<0x107>

Contributions by: Florian Ragwitz and Sebastien Aperghis-Tramoni

=head1 SEE ALSO

L<http://deps.cpantesters.org/>,
L<http://www.cpantesters.org/>

=cut
