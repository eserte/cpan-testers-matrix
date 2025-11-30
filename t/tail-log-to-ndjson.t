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
    {
	open my $ofh, '>', $logtxt;
	print $ofh <<'EOF';
The last 1000 reports as of 2025-10-18T08:00:04Z:
[2025-10-18T07:59:49Z] [Carlos Guevara] [pass] [JKEENAN/IPC-System-Simple-1.30.tar.gz] [i86pc-solaris-thread-multi-64] [perl-v5.43.4] [6bad3778-abf8-11f0-8c1e-b80f595f57ba] [2025-10-18T07:59:49Z]
[2025-10-18T07:59:43Z] [Carlos Guevara] [unknown] [JDHEDDEN/threads-2.21.tar.gz] [amd64-netbsd-thread-multi] [perl-v5.43.4] [67e088d4-abf8-11f0-97a1-bb460411313d] [2025-10-18T07:59:43Z]
[2025-10-18T07:54:07Z] [Chris Williams (BINGOS)] [pass] [/] [x86_64-linux] [perl-v5.18.2] [a018b394-abf7-11f0-a3bc-a055f9c4ba34] [2025-10-18T07:54:07Z]
[2025-10-18T07:40:24Z] [Carlos Guevara] [pass] [ARISTOTLE/Text-Tabs+Wrap-2024.001.tar.gz] [i86pc-solaris-thread-multi-64] [perl-v5.43.4] [b50809d2-abf5-11f0-ab63-d1797d8a4f3d] [2025-10-18T07:40:24Z]
[2025-10-18T07:29:02Z] [Carlos Guevara] [pass] [TINITA/Test-YAML-1.07.tar.gz] [amd64-netbsd-thread-multi] [perl-v5.43.4] [1e9545e2-abf4-11f0-8398-beaf3347c81e] [2025-10-18T07:29:02Z]
EOF
	close $ofh;
    }

    {
	open my $ofh , '>', "$json_dir/Test-YAML.json";
	print $ofh <<'EOF';
[{"archname":"x86_64-linux-multi","fulldate":"201610080752","distribution":"Test-YAML","osname":"linux","version":"1.06","status":"UNKNOWN","perl":"5.25.5","guid":"34e0a544-8d2c-11e6-8a2d-a149d3687cca","tester":"Serguei Trouchelle (STRO)"}]
EOF
	close $ofh;
    }

    my $expected_IPC_System_Simple_ndjson_contents = <<'EOF';
{"archname":"i86pc-solaris-thread-multi-64","distribution":"IPC-System-Simple","fulldate":"202510180759","guid":"6bad3778-abf8-11f0-8c1e-b80f595f57ba","osname":"solaris","perl":"5.43.4","status":"PASS","tester":"Carlos Guevara","version":"1.30"}
EOF
    my $expected_threads_ndjson_contents = <<'EOF';
{"archname":"amd64-netbsd-thread-multi","distribution":"threads","fulldate":"202510180759","guid":"67e088d4-abf8-11f0-97a1-bb460411313d","osname":"netbsd","perl":"5.43.4","status":"UNKNOWN","tester":"Carlos Guevara","version":"2.21"}
EOF
    my $expected_Text_Tabs_Wrap_ndjson_contents = <<'EOF';
{"archname":"i86pc-solaris-thread-multi-64","distribution":"Text-Tabs+Wrap","fulldate":"202510180740","guid":"b50809d2-abf5-11f0-ab63-d1797d8a4f3d","osname":"solaris","perl":"5.43.4","status":"PASS","tester":"Carlos Guevara","version":"2024.001"}
EOF

    my $expected_Test_YAML_ndjson_contents = <<'EOF';
{"archname":"x86_64-linux-multi","distribution":"Test-YAML","fulldate":"201610080752","guid":"34e0a544-8d2c-11e6-8a2d-a149d3687cca","osname":"linux","perl":"5.25.5","status":"UNKNOWN","tester":"Serguei Trouchelle (STRO)","version":"1.06"}
{"archname":"amd64-netbsd-thread-multi","distribution":"Test-YAML","fulldate":"202510180729","guid":"1e9545e2-abf4-11f0-8398-beaf3347c81e","osname":"netbsd","perl":"5.43.4","status":"PASS","tester":"Carlos Guevara","version":"1.07"}
EOF

    for my $pass (1..2) {
	run(\@cmd, '2>', \my $err) or fail "@cmd failed (pass $pass)";
	diag "pass $pass\ncommand: @cmd\nstderr:\n$err" if $debug;
	if ($pass == 1) {
	    like $err, qr{\QIPC-System-Simple.ndjson... (first-time creation) (no existing \E.*/log-as-json/IPC-System-Simple.json\Q...) (writing data...)}, "expected diagnostics for IPC-System-Simple (pass $pass)";
	    like $err, qr{\Qthreads.ndjson... (first-time creation) (no existing \E.*/log-as-json/threads.json\Q...) (writing data...)}, "expected diagnostics for threads (pass $pass)";
	    like $err, qr{\QText-Tabs+Wrap.ndjson... (first-time creation) (no existing \E.*/log-as-json/Text-Tabs\+Wrap.json\Q...) (writing data...)}, "expected diagnostics for Text-Tabs+Wrap (pass $pass)";
	    like $err, qr{\QTest-YAML.ndjson... (first-time creation) (use data from existing \E.*/log-as-json/Test-YAML.json\Q...) (writing data...)}, "expected diagnostics for Test-YAML (pass $pass)";
	} else {
	    like $err, qr{\QIPC-System-Simple.ndjson... (no new data found...)}, "expected diagnostics for IPC-System-Simple (pass $pass)";
	    like $err, qr{\Qthreads.ndjson... (no new data found...)}, "expected diagnostics for threads (pass $pass)";
	    like $err, qr{\QText-Tabs+Wrap.ndjson... (no new data found...)}, "expected diagnostics for Text-Tabs+Wrap (pass $pass)";
	    like $err, qr{\QTest-YAML.ndjson... (no new data found...)}, "expected diagnostics for Test-YAML (pass $pass)";
	}
	like $err, qr{\QCannot parse dist '/' in line '[2025-10-18T07:54:07Z] [Chris Williams (BINGOS)] [pass] [/] [x86_64-linux] [perl-v5.18.2] [a018b394-abf7-11f0-a3bc-a055f9c4ba34] [2025-10-18T07:54:07Z]'}, 'unparsable dist';
	is slurp("$ndjson_dir/IPC-System-Simple.ndjson"), $expected_IPC_System_Simple_ndjson_contents, 'IPC-System-Simple.ndjson contents OK';
	is slurp("$ndjson_dir/threads.ndjson"), $expected_threads_ndjson_contents, 'threads.ndjson contents OK';
	is slurp("$ndjson_dir/Text-Tabs+Wrap.ndjson"), $expected_Text_Tabs_Wrap_ndjson_contents, 'Text-Tabs+Wrap.ndjson contents OK';
	is slurp("$ndjson_dir/Test-YAML.ndjson"), $expected_Test_YAML_ndjson_contents, 'Test-YAML.ndjson contents OK';
	my @ndjson_files = <$ndjson_dir/*>;
	is scalar(@ndjson_files), 4, 'expected number of files';
    }

    {
	# overwrite, simulating new contents
	open my $ofh, '>', $logtxt;
	print $ofh <<'EOF';
The last 1000 reports as of 2025-10-18T08:00:04Z:
[2025-10-18T07:47:59Z] [Carlos Guevara] [pass] [TINITA/Test-YAML-1.07.tar.gz] [i86pc-solaris-thread-multi-64] [perl-v5.43.4] [c4b21958-abf6-11f0-9c1b-c4a53ce7e222] [2025-10-18T07:47:59Z]
[2025-10-18T07:29:02Z] [Carlos Guevara] [pass] [TINITA/Test-YAML-1.07.tar.gz] [amd64-netbsd-thread-multi] [perl-v5.43.4] [1e9545e2-abf4-11f0-8398-beaf3347c81e] [2025-10-18T07:29:02Z]
EOF
	close $ofh;
    }

    my $expected_Test_YAML_ndjson_contents_2 = $expected_Test_YAML_ndjson_contents . <<'EOF';
{"archname":"i86pc-solaris-thread-multi-64","distribution":"Test-YAML","fulldate":"202510180747","guid":"c4b21958-abf6-11f0-9c1b-c4a53ce7e222","osname":"solaris","perl":"5.43.4","status":"PASS","tester":"Carlos Guevara","version":"1.07"}
EOF

    my @ndjson_files;
    {
	run(\@cmd, '2>', \my $err) or fail "@cmd failed";
	diag "command: @cmd\nstderr:\n$err" if $debug;
	like $err, qr{\QTest-YAML.ndjson... (append to existing ndjson file...)}, "expected diagnostics for Test-YAML (appending data)";
	is slurp("$ndjson_dir/Test-YAML.ndjson"), $expected_Test_YAML_ndjson_contents_2, 'Test-YAML.ndjson contents OK';
	@ndjson_files = <$ndjson_dir/*>;
	is scalar(@ndjson_files), 4, 'expected number of files';
    }

    # cleanup for subsequent tests
    unlink @ndjson_files;
}

{
    # Sometimes new log records may be inserted *in between*.
    {
	open my $ofh, '>', $logtxt;
	print $ofh <<'EOF';
The last 1000 reports as of 2025-10-20T21:50:08Z:
[2025-10-20T21:50:04Z] [Andreas J. K&ouml;nig (ANDK)] [pass] [OALDERS/LWP-Protocol-https-6.14.tar.gz] [x86_64-linux-thread-multi-ld] [perl-v5.40.3] [bc86756c-adfe-11f0-8a55-991598add7fd] [2025-10-20T21:50:04Z]
[2025-10-20T21:48:38Z] [Chris Williams (BINGOS)] [pass] [OALDERS/LWP-Protocol-https-6.14.tar.gz] [x86_64-linux-ld] [perl-v5.28.2] [89265ad4-adfe-11f0-a3bc-a055f9c4ba34] [2025-10-20T21:48:38Z]
EOF
	close $ofh;

	my $expected_ndjson_contents = <<'EOF';
{"archname":"x86_64-linux-ld","distribution":"LWP-Protocol-https","fulldate":"202510202148","guid":"89265ad4-adfe-11f0-a3bc-a055f9c4ba34","osname":"linux","perl":"5.28.2","status":"PASS","tester":"Chris Williams (BINGOS)","version":"6.14"}
{"archname":"x86_64-linux-thread-multi-ld","distribution":"LWP-Protocol-https","fulldate":"202510202150","guid":"bc86756c-adfe-11f0-8a55-991598add7fd","osname":"linux","perl":"5.40.3","status":"PASS","tester":"Andreas J. K&ouml;nig (ANDK)","version":"6.14"}
EOF

	run(\@cmd, '2>', \my $err) or fail "@cmd failed";
	diag "command: @cmd\nstderr:\n$err" if $debug;
	like $err, qr{\QLWP-Protocol-https.ndjson... (first-time creation) (no existing \E.*/log-as-json/LWP-Protocol-https.json\Q...) (writing data...)}, "expected diagnostics for LWP-Protocol-https (first-time creation)";
	is slurp("$ndjson_dir/LWP-Protocol-https.ndjson"), $expected_ndjson_contents, 'LWP-Protocol-https.ndjson contents OK';
    }

    {
	open my $ofh, '>', $logtxt;
	print $ofh <<'EOF';
The last 1000 reports as of 2025-10-20T21:55:04Z:
[2025-10-20T21:50:04Z] [Andreas J. K&ouml;nig (ANDK)] [pass] [OALDERS/LWP-Protocol-https-6.14.tar.gz] [x86_64-linux-thread-multi-ld] [perl-v5.40.3] [bc86756c-adfe-11f0-8a55-991598add7fd] [2025-10-20T21:50:04Z]
[2025-10-20T21:48:40Z] [Chris Williams (BINGOS)] [pass] [OALDERS/LWP-Protocol-https-6.14.tar.gz] [x86_64-linux-ld] [perl-v5.28.3] [8ac3d3ee-adfe-11f0-a3bc-a055f9c4ba34] [2025-10-20T21:48:40Z]
[2025-10-20T21:48:38Z] [Chris Williams (BINGOS)] [pass] [OALDERS/LWP-Protocol-https-6.14.tar.gz] [x86_64-linux-ld] [perl-v5.28.2] [89265ad4-adfe-11f0-a3bc-a055f9c4ba34] [2025-10-20T21:48:38Z]
EOF
	close $ofh;

	my $expected_ndjson_contents = <<'EOF';
{"archname":"x86_64-linux-ld","distribution":"LWP-Protocol-https","fulldate":"202510202148","guid":"89265ad4-adfe-11f0-a3bc-a055f9c4ba34","osname":"linux","perl":"5.28.2","status":"PASS","tester":"Chris Williams (BINGOS)","version":"6.14"}
{"archname":"x86_64-linux-ld","distribution":"LWP-Protocol-https","fulldate":"202510202148","guid":"8ac3d3ee-adfe-11f0-a3bc-a055f9c4ba34","osname":"linux","perl":"5.28.3","status":"PASS","tester":"Chris Williams (BINGOS)","version":"6.14"}
{"archname":"x86_64-linux-thread-multi-ld","distribution":"LWP-Protocol-https","fulldate":"202510202150","guid":"bc86756c-adfe-11f0-8a55-991598add7fd","osname":"linux","perl":"5.40.3","status":"PASS","tester":"Andreas J. K&ouml;nig (ANDK)","version":"6.14"}
EOF

	run(\@cmd, '2>', \my $err) or fail "@cmd failed";
	diag "command: @cmd\nstderr:\n$err" if $debug;
	like $err, qr{\QLWP-Protocol-https.ndjson... (out-of-band inserts detected, need to truncate first...) (append to existing ndjson file...)}, "expected diagnostics for LWP-Protocol-https (appending data)";
	is slurp("$ndjson_dir/LWP-Protocol-https.ndjson"), $expected_ndjson_contents, 'LWP-Protocol-https.ndjson contents OK';
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
