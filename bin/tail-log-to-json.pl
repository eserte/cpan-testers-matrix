#!/usr/bin/perl -w
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2012,2015,2016 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

use strict;
use Getopt::Long;
use JSON::XS;
use Fcntl qw( :flock :seek O_RDONLY O_RDWR O_CREAT );

my $o_logfile;

sub mylog ($) {
    my($message) = @_;
    my $fh;
    if ($o_logfile) {
	open $fh, ">>", $o_logfile or die "Could not open >> '$o_logfile': $!";
    } else {
	$fh = \*STDERR;
    }
    $message =~ s/\s*\z/\n/;
    my @t = gmtime;
    $t[5]+=1900;
    $t[4]++;
    my $ts = sprintf "%04d%02d%02dT%02d%02d%02d", @t[5,4,3,2,1,0];
    print $fh "$ts:$message";
}

sub mydie ($) {
    my($mess) = @_;
    mylog $mess;
    warn $mess;
    exit;
}

my $o_dir;
my $o_statusfile;
my $do_seek = 1;
GetOptions("o=s" => \$o_dir,
           "statusfile=s" => \$o_statusfile,
           "logfile=s" => \$o_logfile,
	   'seek!' => \$do_seek,
          )
    or die "usage: $0 -o output_directory log.txt\n";
$o_dir
    or die "Please specify -o option (destination directory for the .json files)\n";
$o_statusfile
    or die "Please specify -statusfile option";
$o_logfile
    or die "Please specify -logfile option";
my $tail_log = shift
    or die "Please provide path to log.txt\n";

-d $o_dir
    or die "Could not find o_dir '$o_dir'";

my %distinfo;

my $lfh;
my $lockfile = $o_statusfile;
unless (open $lfh, "+<", $lockfile) {
    unless ( open $lfh, ">>", $lockfile ) {
        mydie "ALERT: Could not open >> '$lockfile': $!";
    }
    unless ( open $lfh, "+<", $lockfile ) {
        mydie "ALERT: Could not open +< '$lockfile': $!";
    }
}
if (flock $lfh, LOCK_EX|LOCK_NB) {
    mylog "Info[$$]: Got the lock, continuing";
} else {
    mydie "FATAL[$$]: lockfile '$lockfile' locked by a different process; cannot continue";
}

my $json = JSON::XS->new->pretty(1)->utf8(1)->indent(1)->space_before(1)->space_after(0);
my $status_content = do { open my $fh, $o_statusfile or mydie "could not open: $!"; local $/; <$fh>};
my $status = $status_content ? $json->decode($status_content) : {};
open my $fh, $tail_log
    or mydie "Can't open $tail_log: $!";
binmode $fh, ':utf8';
if ($do_seek && $status->{tell}) {
    seek $fh, $status->{tell}, SEEK_SET;
}
my $count = 0;
my %guid;
while(<$fh>) {
    chomp;
    next if /^The last \d+ reports/;
    next if /^\.\.\./;
    if (my($date1, $author, $status, $distpath, $archname, $perl, $guid, $date2) = $_ =~
	m{^\[(.*?)\] \[(.*?)\] \[(.*?)\] \[(.*?)\] \[(.*?)\] \[(.*?)\] \[(.*?)\] \[(.*?)\]$}) {
	# I need:
	# - status
	# - platform
	# - guid
	# - version
	# - dist
	my $osname;
	if ($archname =~ m{\b(linux|openbsd|netbsd|solaris|freebsd|MSWin32|darwin|dragonfly|cygwin|mirbsd|gnukfreebsd|haiku|bitrig)\b}) {
	    $osname = lc $1
	} else {
	    warn "Cannot parse OS out of '$archname'\n";
	}
	my $fulldate;
	if ($date1 =~ m{^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$}) {
	    $fulldate = "$1$2$3$4$5";
	} else {
	    warn "Cannot parse date out of '$date1'\n";
	}
	# example: perl-v5.14.2
	$perl =~ s{^perl-v}{};
	# example: AVENJ/MooX-Role-Pluggable-0.01.tar.gz
	# XXX use DistnameInfo or so?
	if (my($dist, $version) = $distpath =~ m{^.+/(.*)-v?(\d.*)\.(?:tar\.gz|zip|tar\.bz2|tgz)$}) {
	    push @{ $distinfo{$dist} }, {
					 status => uc($status),
					 osname => $osname,
					 ## XXX There are two GUIDs: the GUIDs defined in log.txt
					 ## are not the same as in the cpantesters db. So this one is
					 ## strictly incorrect (and maybe should be renamed)
					 guid => $guid,
					 version => $version,
					 distribution => $dist,
					 perl => $perl,
					 ## by not defining "id" there won't be a report link in the report view,
					 ## which would be misleading anyway, as the guid in log.txt is NOT the same guid
					 ## in the cpantesters db
					 #id => "dummy",
					 archname => $archname,
					 fulldate => $fulldate,
					 tester => $author,
					};
            $count++;
	} else {
	    warn "Cannot parse dist '$distpath'\n";
	}
    } else {
	warn "Can't parse line '$_'\n";
    }
}
mylog "Info[$$]: $count new record(s) read";
$status->{tell} = tell $fh;
close $fh;

while(my($dist,$v) = each %distinfo) {
    if ($dist !~ m{^[a-zA-Z0-9_-]+$}) {
	warn "Skipping possibly problematic filename '$dist'...\n";
    } else {
	my $o_file = $o_dir . "/$dist.json";
	print STDERR "$o_file...\n";
        if (-e $o_file) {
            my $old_v_serialized = do { open my $fh, $o_file or mydie "Could not open: $!"; local $/; <$fh>};
            my $old_v = $json->decode($old_v_serialized);
            $v = [@$old_v,@$v];
        }
        my %guid_seen;
        for my $i (reverse 0..$#$v) {
            my $rec = $v->[$i];
            if ($guid_seen{$rec->{guid}}++) {
                splice @$v, $i, 1;
            }
        }
	open my $ofh, ">", $o_file
	    or mydie "Can't write to $o_file: $!";
	print $ofh encode_json $v;
	close $ofh
	    or mydie $!;
    }
}
$status->{proc} = $$;
$status->{time} = time;
truncate $lfh, 0 or mydie "Could not truncate: $!";
seek $lfh, 0, SEEK_SET;
print $lfh $json->encode($status);
close $lfh or mydie "Could not close: $!";

__END__
# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
