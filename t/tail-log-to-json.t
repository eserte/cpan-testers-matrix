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
use JSON::PP ();

sub slurp ($);
sub eq_json ($$;$);

my $script = "$FindBin::RealBin/../bin/tail-log-to-json.pl";

my $metabase_log_dir = tempdir("metabase-log-XXXXXXXX", TMPDIR => 1, CLEANUP => 1);
my $json_dir = "$metabase_log_dir/log-as-json";
my $logfile = "$metabase_log_dir/log.log";
my $statusfile = "$metabase_log_dir/statusfile";
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

mkdir $json_dir;

my @cmd = (
    $^X, $script,
    "-o", $json_dir,
    "-logfile", $logfile,
    "-statusfile", $statusfile,
    $logtxt,
);

my $jsoner = JSON::PP->new->pretty(0)->utf8(1)->canonical(1);

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

    chomp(my $expected_IPC_System_Simple_json_contents = <<'EOF');
[{"archname":"i86pc-solaris-thread-multi-64","distribution":"IPC-System-Simple","fulldate":"202510180759","guid":"6bad3778-abf8-11f0-8c1e-b80f595f57ba","osname":"solaris","perl":"5.43.4","status":"PASS","tester":"Carlos Guevara","version":"1.30"}]
EOF
    chomp(my $expected_threads_json_contents = <<'EOF');
[{"archname":"amd64-netbsd-thread-multi","distribution":"threads","fulldate":"202510180759","guid":"67e088d4-abf8-11f0-97a1-bb460411313d","osname":"netbsd","perl":"5.43.4","status":"UNKNOWN","tester":"Carlos Guevara","version":"2.21"}]
EOF
    chomp(my $expected_Text_Tabs_Wrap_json_contents = <<'EOF');
[{"archname":"i86pc-solaris-thread-multi-64","distribution":"Text-Tabs+Wrap","fulldate":"202510180740","guid":"b50809d2-abf5-11f0-ab63-d1797d8a4f3d","osname":"solaris","perl":"5.43.4","status":"PASS","tester":"Carlos Guevara","version":"2024.001"}]
EOF

    chomp(my $expected_Test_YAML_json_contents = <<'EOF');
[{"archname":"amd64-netbsd-thread-multi","distribution":"Test-YAML","fulldate":"202510180729","guid":"1e9545e2-abf4-11f0-8398-beaf3347c81e","osname":"netbsd","perl":"5.43.4","status":"PASS","tester":"Carlos Guevara","version":"1.07"}]
EOF

    for my $pass (1..2) {
	run(\@cmd, '2>', \my $err) or fail "@cmd failed (pass $pass)";
	diag "pass $pass\ncommand: @cmd\nstderr:\n$err" if $debug;
	if ($pass == 1) {
	    like $err, qr{\QIPC-System-Simple.json...\E$}m, "expected diagnostics for IPC-System-Simple (pass $pass)";
	    like $err, qr{\Qthreads.json...\E$}m, "expected diagnostics for threads (pass $pass)";
	    like $err, qr{\QText-Tabs+Wrap.json...\E$}m, "expected diagnostics for Text-Tabs+Wrap (pass $pass)";
	    like $err, qr{\QTest-YAML.json...\E$}m, "expected diagnostics for Test-YAML (pass $pass)";
	    like $err, qr{\QCannot parse dist '/'\E$}m, "unparsable dist (pass $pass)";
	} else {
	    unlike $err, qr{\QIPC-System-Simple.json...\E$}m, "expected missing diagnostics for IPC-System-Simple (pass $pass)";
	    unlike $err, qr{\Qthreads.json...\E$}m, "expected missing diagnostics for threads (pass $pass)";
	    unlike $err, qr{\QText-Tabs+Wrap.json...\E$}m, "expected missing diagnostics for Text-Tabs+Wrap (pass $pass)";
	    unlike $err, qr{\QTest-YAML.json...\E$}m, "expected missing diagnostics for Test-YAML (pass $pass)";
	    unlike $err, qr{\QCannot parse dist '/'\E$}m, "missing diagnostics for unparsable dist (pass $pass)";
	}
	eq_json slurp("$json_dir/IPC-System-Simple.json"), $expected_IPC_System_Simple_json_contents, 'IPC-System-Simple.json contents OK';
	eq_json slurp("$json_dir/threads.json"), $expected_threads_json_contents, 'threads.json contents OK';
	eq_json slurp("$json_dir/Text-Tabs+Wrap.json"), $expected_Text_Tabs_Wrap_json_contents, 'Text-Tabs+Wrap.json contents OK';
	eq_json slurp("$json_dir/Test-YAML.json"), $expected_Test_YAML_json_contents, 'Test-YAML.json contents OK';
	my @json_files = <$json_dir/*>;
	is scalar(@json_files), 4, 'expected number of files';
    }

    {
	# overwrite, simulating new contents
	open my $ofh, '>', $logtxt;
	print $ofh <<'EOF';
The last 1000 reports as of 2025-10-18T20:50:04Z:
[2025-10-18T20:45:51Z] [Lukas Mai] [fail] [DDICK/Crypt-URandom-0.54.tar.gz] [x86_64-linux] [perl-v5.26.1] [6eedc2ac-ac63-11f0-a271-6dd1f058a8b3] [2025-10-18T20:45:51Z]
[2025-10-18T20:45:41Z] [Lukas Mai] [fail] [DDICK/Crypt-URandom-0.54.tar.gz] [x86_64-linux] [perl-v5.30.3] [6950f422-ac63-11f0-8d1f-bfd0f058a8b3] [2025-10-18T20:45:41Z]
EOF
	close $ofh;
    }

    chomp(my $expected_Crypt_URandom_json_contents = <<'EOF');
[{"archname":"x86_64-linux","distribution":"Crypt-URandom","fulldate":"202510182045","guid":"6950f422-ac63-11f0-8d1f-bfd0f058a8b3","osname":"linux","perl":"5.30.3","status":"FAIL","tester":"Lukas Mai","version":"0.54"},{"archname":"x86_64-linux","distribution":"Crypt-URandom","fulldate":"202510182045","guid":"6eedc2ac-ac63-11f0-a271-6dd1f058a8b3","osname":"linux","perl":"5.26.1","status":"FAIL","tester":"Lukas Mai","version":"0.54"}]
EOF
    {
	my @cmd_without_seek = (@cmd, "-no-seek");
	run(\@cmd_without_seek, '2>', \my $err) or fail "@cmd_without_seek failed";
	diag "command: @cmd_without_seek\nstderr:\n$err" if $debug;
	like $err, qr{\QCrypt-URandom.json...\E$}m, "expected diagnostics for Crypt-URandom (appending data)";
	{
	    local $TODO = "unexpected order";
	    eq_json slurp("$json_dir/Crypt-URandom.json"), $expected_Crypt_URandom_json_contents, 'Crypt-URandom.json contents OK';
	}
	my @json_files = <$json_dir/*>;
	is scalar(@json_files), 5, 'expected number of files';
    }
}

sub eq_json ($$;$) {
    my($got, $expected, $name) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    is $jsoner->encode($jsoner->decode($got)), $expected, $name;
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
