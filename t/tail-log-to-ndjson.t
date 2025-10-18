#!/usr/bin/perl -w
# -*- cperl -*-

#
# Author: Slaven Rezic
#

use strict;
use warnings;
use autodie;
use FindBin;
use Test::More;

BEGIN {
    if (!eval { require IPC::Run; IPC::Run->import(qw(run)); 1 }) {
	plan skip_all => 'IPC::Run required';
	exit 0;
    }
}
plan 'no_plan';

use File::Temp qw(tempdir);
use Getopt::Long;

sub slurp ($);

my $script = "$FindBin::RealBin/../bin/tail-log-to-ndjson.pl";

my $metabase_log_dir = tempdir("metabase-log-XXXXXXXX", TMPDIR => 1, CLEANUP => 1);
my $ndjson_dir = "$metabase_log_dir/tail-log-as-ndjson";
my $json_dir = "$metabase_log_dir/log-as-json";
my $logfile = "$metabase_log_dir/ndjson-log.log";
my $statusfile = "$metabase_log_dir/ndjson-statusfile";
my $logtxt = "$metabase_log_dir/log.txt";

GetOptions(
    "debug" => \my $debug,
    "keep!" => sub {
	if ($_[1]) {
	    $File::Temp::KEEP_ALL = 1;
	    warn "Keep temporary files in $metabase_log_dir\n";
	}
    },
)
    or die "usage?";

for my $dir ($ndjson_dir, $json_dir) {
    mkdir $dir;
}

my @cmd = (
    $^X, $script,
    "--ndjson-dir", $ndjson_dir,
    "--json-dir", $json_dir,
    "-logfile", $logfile,
    "-statusfile", $statusfile,
    $logtxt,
);

{
    open my $ofh, '>', $logtxt;
    print $ofh <<'EOF';
The last 1000 reports as of 2025-10-18T08:00:04Z:
[2025-10-18T07:59:49Z] [Carlos Guevara] [pass] [JKEENAN/IPC-System-Simple-1.30.tar.gz] [i86pc-solaris-thread-multi-64] [perl-v5.43.4] [6bad3778-abf8-11f0-8c1e-b80f595f57ba] [2025-10-18T07:59:49Z]
[2025-10-18T07:59:43Z] [Carlos Guevara] [unknown] [JDHEDDEN/threads-2.21.tar.gz] [amd64-netbsd-thread-multi] [perl-v5.43.4] [67e088d4-abf8-11f0-97a1-bb460411313d] [2025-10-18T07:59:43Z]
EOF
    close $ofh;

    my $exptected_IPC_System_Simple_ndjson_contents = <<'EOF';
{"archname":"i86pc-solaris-thread-multi-64","distribution":"IPC-System-Simple","fulldate":"202510180759","guid":"6bad3778-abf8-11f0-8c1e-b80f595f57ba","osname":"solaris","perl":"5.43.4","status":"PASS","tester":"Carlos Guevara","version":"1.30"}
EOF
    my $exptected_threads_ndjson_contents = <<'EOF';
{"archname":"amd64-netbsd-thread-multi","distribution":"threads","fulldate":"202510180759","guid":"67e088d4-abf8-11f0-97a1-bb460411313d","osname":"netbsd","perl":"5.43.4","status":"UNKNOWN","tester":"Carlos Guevara","version":"2.21"}
EOF

    for my $pass (1..2) {
	run(\@cmd, '2>', \my $err) or fail "@cmd failed (pass $pass)";
	diag "pass $pass\ncommand: @cmd\nstderr:\n$err" if $debug;
	if ($pass == 1) {
	    like $err, qr{\QIPC-System-Simple.ndjson... (first-time creation) (no existing \E.*/log-as-json/IPC-System-Simple.json\Q...) (writing data...)}, "expected diagnostics for IPC-System-Simple (pass $pass)";
	    like $err, qr{\Qthreads.ndjson... (first-time creation) (no existing \E.*/log-as-json/threads.json\Q...) (writing data...)}, "expected diagnostics for threads (pass $pass)";
	} else {
	    like $err, qr{\QIPC-System-Simple.ndjson... (append to existing ndjson file...) (found last guid...) (no new data found...)}, "expected diagnostics for IPC-System-Simple (pass $pass)";
	    like $err, qr{\Qthreads.ndjson... (append to existing ndjson file...) (found last guid...) (no new data found...)}, "expected diagnostics for threads (pass $pass)";
	}
	is slurp("$ndjson_dir/IPC-System-Simple.ndjson"), $exptected_IPC_System_Simple_ndjson_contents, 'IPC-System-Simple.ndjson contents OK';
	is slurp("$ndjson_dir/threads.ndjson"), $exptected_threads_ndjson_contents, 'threads.ndjson contents OK';
	my @ndjson_files = <$ndjson_dir/*>;
	is scalar(@ndjson_files), 2, 'expected two files';
    }
}

# REPO BEGIN
# REPO NAME slurp /home/e/eserte/src/srezic-repository 
# REPO MD5 241415f78355f7708eabfdb66ffcf6a1
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
