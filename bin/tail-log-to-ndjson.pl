#!/usr/bin/perl -w
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2023 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  https://github.com/eserte/cpan-testers-matrix/
#

use strict;
use Getopt::Long;
use JSON::XS;
use Fcntl qw( :flock :seek O_RDONLY O_RDWR O_CREAT );
use File::ReadBackwards;

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

my $ndjson_dir;
my $json_dir;
my $o_statusfile; # acts as a lock file and contains some information about the last run
GetOptions("ndjson-dir=s" => \$ndjson_dir,
	   "json-dir=s"   => \$json_dir,
           "statusfile=s" => \$o_statusfile,
           "logfile=s"    => \$o_logfile,
          )
    or die "usage: $0 --ndjson-dir output_directory log.txt\n";
$ndjson_dir
    or die "Please specify --ndjson-dir option (destination directory for the .ndjson files)\n";
$o_statusfile
    or die "Please specify --statusfile option";
$o_logfile
    or die "Please specify --logfile option";
my $tail_log = shift
    or die "Please provide path to log.txt\n";
@ARGV
    and die "Unhandled arguments: @ARGV\n";

-d $ndjson_dir
    or die "Could not find ndjson-dir '$ndjson_dir'";

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

my $status_jsoner = JSON::XS->new->pretty(1)->utf8(1)->indent(1)->space_before(1)->space_after(0);
my $status_content = do { open my $fh, $o_statusfile or mydie "could not open: $!"; local $/; <$fh>};
my $status = $status_content ? $status_jsoner->decode($status_content) : {};

my $jsoner = JSON::XS->new->pretty(0)->utf8(1)->canonical(1);

open my $fh, $tail_log
    or mydie "Can't open $tail_log: $!";
binmode $fh, ':utf8';
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
	if ($archname =~ m{\b(linux|openbsd|netbsd|midnightbsd|solaris|freebsd|MSWin32|darwin|dragonfly|cygwin|mirbsd|gnukfreebsd|haiku|bitrig|android)\b}) {
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
	    unshift @{ $distinfo{$dist} }, {
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
	    warn "Cannot parse dist '$distpath' in line '$_'\n";
	}
    } else {
	warn "Can't parse line '$_'\n";
    }
}
mylog "Info[$$]: $count new record(s) read";
close $fh;

while(my($dist,$v) = each %distinfo) {
    if ($dist !~ m{^[a-zA-Z0-9_-]+$}) {
	warn "Skipping possibly problematic filename '$dist'...\n";
    } else {
	my $ndjson_file = $ndjson_dir . "/$dist.ndjson";
	print STDERR "$ndjson_file... ";
	my @out_v;
	if (!-e $ndjson_file) {
	    print STDERR "(first-time creation) ";
	    {
		my $json_file;
		if (defined $json_dir && do { $json_file = $json_dir . "/$dist.json" } && -e $json_file) {
		    print STDERR "(use data from existing $json_file...) ";
		    my $old_v_serialized = do { open my $fh, $json_file or mydie "Could not open '$json_file': $!"; local $/; <$fh>};
		    my $old_v = $jsoner->decode($old_v_serialized);
		    @out_v = (@$old_v,@$v);
		}
	    }
	    my %guid_seen;
	    for my $i (0..$#out_v) {
		my $rec = $out_v[$i];
		if ($guid_seen{$rec->{guid}}++) {
		    splice @out_v, $i, 1;
		}
	    }
	    print STDERR "(writing data...)";
	    open my $ofh, ">", $ndjson_file
		or mydie "Can't write to '$ndjson_file': $!";
	    for my $item (@out_v) {
		print $ofh $jsoner->encode($item), "\n";
	    }
	    close $ofh
		or mydie $!;
	    print STDERR "\n";
	} else {
	    print STDERR "(append to existing ndjson file...) ";
	    my $bw = File::ReadBackwards->new($ndjson_file)
		or mydie "Can't read '$ndjson_file' using File::ReadBackwards: $!";
	    my $last_line = $bw->readline;
	    my $last_record = $jsoner->decode($last_line);
	    my $last_guid = $last_record->{guid};
	    my $start_index;
	    for my $i (0 .. $#$v) {
		if ($v->[$i]->{guid} eq $last_guid) {
		    print STDERR "(found last guid...) ";
		    $start_index = $i+1;
		    last;
		}
	    }
	    if (!defined $start_index) {
		print STDERR "(did not found last guid, append everything...) ";
		$start_index = 0;
	    }
	    if ($start_index > $#$v) {
		print STDERR "(no new data found...) ";
	    } else {
		print STDERR "(appending data...)";
		open my $ofh, ">>", $ndjson_file
		    or mydie "Can't write to '$ndjson_file': $!";
		for my $i ($start_index .. $#$v) {
		    print $ofh $jsoner->encode($v->[$i]), "\n";
		}
		close $ofh
		    or mydie $!;
	    }
	    print STDERR "\n";
	}
    }
}
$status->{last_pid} = $$;
$status->{last_time} = time;
truncate $lfh, 0 or mydie "Could not truncate: $!";
seek $lfh, 0, SEEK_SET;
print $lfh $status_jsoner->encode($status);
close $lfh or mydie "Could not close: $!";

__END__
# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# End:
