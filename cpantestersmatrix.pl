#!/usr/bin/perl -w
# -*- perl -*-

#
# $Id: cpantestersmatrix.pl,v 1.1 2007/11/30 23:00:13 eserte Exp $
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
use File::Basename qw(basename);
use HTML::Table;
use LWP::UserAgent;
use List::Util qw(reduce);
use YAML::Syck qw(LoadFile Load);
use version;

my $cache = "/tmp/cpantesters_cache";
mkdir $cache, 0755 if !-d $cache;

my $dist = shift;
$dist = basename $dist;

my $data;

my $cachefile = $cache."/".$dist.".yaml";
if (!-r $cachefile || -M $cachefile > 1) {
    my $ua = LWP::UserAgent->new;
    my $resp = $ua->get("http://cpantesters.perl.org/show/$dist.yaml");
    if (!$resp->is_success) {
	die $resp->as_string;
    }
    $data = Load($resp->decoded_content) or die;
    open my $fh, ">", "$cachefile.$$" or die $!;
    print $fh $resp->decoded_content;
    close $fh;
    rename "$cachefile.$$", $cachefile or die $!;
} else {
    $data = LoadFile($cachefile) or die;
}

my %perl;
my %perl_patches;
my %osname;
my %action;

my $max_version = reduce { $a gt $b ? $a : $b } map { version->new($_->{version}) } @$data;

for my $r (@$data) {
    next if version->new($r->{version}) ne $max_version;
    my($perl, $patch) = $r->{perl} =~ m{^(\S+)(?:\s+patch\s+(\S+))?};
    die "$r->{perl} couldn't be parsed" if !defined $perl;
    $perl{$perl}++;
    $perl_patches{$perl}->{$patch}++ if $patch;
    $osname{$r->{osname}}++;

    $action{$perl}->{$r->{osname}}->{$r->{action}}++;
    $action{$perl}->{$r->{osname}}->{__TOTAL__}++;
}

my @perls   = sort { $b cmp $a } map { version->new($_) } keys %perl;
my @osnames = sort { $a cmp $b } keys %osname;
my @actions = qw(PASS NA UNKNOWN FAIL);

my @matrix;
for my $perl (@perls) {
    my @row;
    for my $osname (@osnames) {
	my $acts = $action{$perl}->{$osname};
	if ($acts) {
	    my @cell;

	    my $top = 0;
	    my $left = 0;
	    for my $act (@actions) {
		#push @cell, qq{<span class="action_$act">} . ($acts->{$act}||0) . qq{</span>};
		my $percent = int(100*($acts->{$act}||0)/$acts->{__TOTAL__});
		push @cell, qq{<span class="bar action_$act" style="top:${top}px;left:${left}%; width:${percent}%;"></span>};
		$left += $percent;
		$top -= 20; # XXX bar height
	    }
	    push @row, join(" ", @cell);
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

print <<EOF;
<html>
 <head><title>$dist $max_version</title>
  <style type="text/css"><!--
  .action_PASS    { background:green; }
  .action_NA      { background:orange; }
  .action_UNKNOWN { background:orange; }
  .action_FAIL    { background:red; }

  table		  { border-collapse:collapse; }
  th,td           { border:1px solid black; }
  body		  { font-family:sans-serif; }

  .bt th,td	  { border:none; }

  .bar { 
    display: block;
    position: relative;
    height: 20px; 
  }

  --></style>
 </head>
 <body>
  <h1><a href="http://cpantesters.perl.org/show/$dist.html#$dist-$max_version">$dist $max_version</a></h1>
EOF
$table->print;
print <<EOF;
 </body>
</html>
EOF

__END__
