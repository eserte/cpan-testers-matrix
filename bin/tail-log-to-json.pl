#!/usr/bin/perl -w
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2012 Slaven Rezic. All rights reserved.
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
    open my $fh, ">>", $o_logfile or die "Could not open >> '$o_logfile': $!";
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
    exit;
}

my $o_dir;
my $o_statusfile;
GetOptions("o=s" => \$o_dir,
           "statusfile=s" => \$o_statusfile,
           "logfile=s" => \$o_logfile,
          )
    or die "usage: $0 -o output_directory log.txt\n";
$o_dir
    or mydie "Please specify -o option (destination directory for the .json files)\n";
$o_logfile
    or mydie "Please specify -logfile option";
$o_statusfile
    or mydie "Please specify -statusfile option";
my $tail_log = shift
    or mydie "Please provide path to log.txt\n";

-d $o_dir
    or mydie "Could not find o_dir '$o_dir'";

my %distinfo;

my $seek = 0;
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

my $json = JSON::XS->new->pretty(1)->indent(1)->space_before(1)->space_after(0);
my $status_content = do { open my $fh, $o_statusfile or mydie "could not open: $!"; local $/; <$fh>};
my $status = $status_content ? $json->decode($status_content) : {};
open my $fh, $tail_log
    or mydie "Can't open $tail_log: $!";
if ($status->{tell}) {
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
	if ($archname =~ m{\b(linux|openbsd|netbsd|solaris|freebsd|MSWin32|darwin|dragonfly|cygwin|mirbsd)\b}) {
	    $osname = lc $1
	} else {
	    warn "Cannot parse OS out of '$archname'\n";
	}
	# example: perl-v5.14.2
	$perl =~ s{^perl-v}{};
	# example: AVENJ/MooX-Role-Pluggable-0.01.tar.gz
	# XXX use DistnameInfo or so?
	if (my($dist, $version) = $distpath =~ m{^.+/(.*)-v?(\d.*)\.(?:tar\.gz|zip|tar\.bz2|tgz)$}) {
	    push @{ $distinfo{$dist} }, {
					 status => uc($status),
					 osname => $osname,
					 guid => $guid,
					 version => $version,
					 distribution => $dist,
					 perl => $perl,
					 id => "dummy",
					 archname => $archname,
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
