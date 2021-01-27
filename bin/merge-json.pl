#!/usr/bin/env perl
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2020 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

# Merge two files created with tail-log-to-json.
# 2nd file is the destination.
# May use the same lockfile as tail-log-to-json itself (option: -lockfile)
# Per default only a dry-run is done; use --doit to really write the merge out.

use strict;
use warnings;

use Cwd qw(realpath);
use Fcntl qw(:flock);
use File::Basename qw(basename);
use Getopt::Long;
use JSON::XS;

sub slurp ($);

my $lockfile;
my $doit;
GetOptions(
	   "lockfile=s" => \$lockfile,
	   "doit!" => \$doit,
	  )
    or die "usage?";

my $lfh;
if ($lockfile) {
 GET_LOCK: {
	my $MAX_TRIES = 90;
	for my $try (1..$MAX_TRIES) {
	    open $lfh, '<', $lockfile
		or do { warn "Can't open $lockfile ($try/$MAX_TRIES): $!"; next };
	    flock $lfh, LOCK_EX|LOCK_NB
		or do { warn "Can't lock $lockfile ($try/$MAX_TRIES): $!"; next };
	    last GET_LOCK;
	} continue {
	    sleep 1;
	}
	die "Permanent error: cannot lock $lockfile\n";
    }
}

my($from_file, $to_file) = @ARGV;
if (!defined $to_file) { die "usage: $0 fromfile tofile\n" }

if (-d $to_file) {
    $to_file .= "/" . basename($from_file);
    $to_file = realpath $to_file;
    warn "INFO: Use '$to_file' as destination file.\n";
}

my $from = decode_json slurp $from_file;
my $to   = decode_json slurp $to_file;

my %to_seen_guid = map { ($_->{guid} => 1) } @$to;

my $misses = 0;
for my $rec (sort { $b->{fulldate} cmp $a->{fulldate} } @$from) {
    my $guid = $rec->{guid};
    die "Unexpected: record $rec in $from_file without $guid" if !$guid;
    if (!exists $to_seen_guid{$guid}) {
	warn "MISSING: $rec->{fulldate} $rec->{guid}\n";
	$misses++;
	for(my $to_i = $#$to; $to_i >= -1; $to_i--) {
	    if ($to_i < 0 || $to->[$to_i]->{fulldate} lt $rec->{fulldate}) {
		splice @$to, $to_i+1, 0, $rec;
		warn "... INSERTED at pos ".($to_i+1)."\n";
		last;
	    }
	}
    }
}

if (!$misses) {
    warn "INFO: nothing to insert!\n";
} else {
    if ($doit) {
	open my $ofh, ">", "$to_file.$$"
	    or die "Error while opening $to_file.$$: $!";
	print $ofh encode_json $to;
	close $ofh
	    or die "Error while writing to $to_file.$$: $!";
	rename "$to_file.$$", $to_file
	    or die "Error while renaming $to_file.$$ to $to_file: $!";
    } else {
	warn "INFO: This was a dry-run --- please re-run with --doit\n";
    }
}

# REPO BEGIN
# REPO NAME slurp /home/e/eserte/src/srezic-repository 
# REPO MD5 241415f78355f7708eabfdb66ffcf6a1

=head2 slurp($file)

=for category File

Return content of the file I<$file>. Die if the file is not readable.

An alternative implementation would be

    sub slurp ($) { open my $fh, shift or die $!; local $/; <$fh> }

but this probably won't work with very old perls.

=cut

sub slurp ($) {
    my($file) = @_;
    my $fh;
    my $buf;
    open $fh, $file
	or die "Can't slurp file $file: $!";
    local $/ = undef;
    $buf = <$fh>;
    close $fh;
    $buf;
}
# REPO END


__END__
