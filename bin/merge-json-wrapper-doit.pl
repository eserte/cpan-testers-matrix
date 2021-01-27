#!/usr/bin/env perl
# -*- perl -*-

# Run merge-json.pl for a file set between two machines: local and
# remote on the cpan-testers machine.
#
# First-time usage with a fixed start epoch:
#
#    ./merge-json-wrapper-doit.pl --start-epoch 1597125000 --max-count 10
#
# After that, a file /tmp/merge-json-wrapper.startepoch is created containing
# the next start epoch:
#
#    ./merge-json-wrapper-doit.pl --max-count 10
#
# If you feel confident, use a higher max count value, or no max count
# value at all, meaning that all files will be processed.
#
# --force-sync may be used to synchronize an update version of
# merge-json.pl.
# 
# Note: some paths, hostnames and usernames are hardcoded and reflect
# the actual running systems.

use if !$ENV{DOIT_IN_REMOTE}, lib => "$ENV{HOME}/src/Doit/lib";
use Doit; # install from CPAN or do "git clone git://github.com/eserte/doit.git ~/src/Doit"
use Doit::Log;
use Doit::File;

use File::Basename qw(basename);
use File::Glob qw(bsd_glob);
use Getopt::Long;
use POSIX qw(strftime);

my $merge_json = "/tmp/merge-json.pl";

sub exists_merge_json { -s $merge_json }

sub get_source_files {
    my($start_epoch) = @_;

    my $source_dir = "/var/tmp/metabase-log/log-as-json";

    my @file_defs;
    opendir my $dirfh, $source_dir
	or error $!;
    while(defined(my $f = readdir($dirfh))) {
	next if $f eq '.' || $f eq '..';
	if ($f !~ /\.json$/) {
	    warning "Ignore stray file '$f'...";
	    next;
	}
	my $path = "$source_dir/$f";
	my(@s) = stat $path;
	my $mtime = $s[9];
	next if $mtime < $start_epoch;
	push @file_defs, { path => $path, mtime => $mtime };
    }

    @file_defs = sort { $a->{mtime} <=> $b->{mtime} } @file_defs;

    return @file_defs;
}

return 1 if caller;

my $ts_file = "/tmp/merge-json-wrapper.startepoch";

my $doit = Doit->init;
$doit->add_component(qw(file));

GetOptions(
	   "start-epoch=s" => \my $start_epoch,
	   "max-count=i" => \my $max_count,
	   "force-sync" => \my $force_sync,
	  )
    or die "usage?";
if (!$start_epoch) {
    open my $fh, "<", $ts_file
	or error "Can't load startepoch from file $ts_file ($!) and --start-epoch not specified";
    chomp($start_epoch = <$fh>);
    if (!$start_epoch || $start_epoch !~ m{^\d+$}) {
	error "Invalid start epoch '$start_epoch'?";
    }
    info "Starting at " . strftime("%F %T", localtime $start_epoch);
}


my $remote = $doit->do_ssh_connect('new-cpan-testers', as => 'andreas');
my @file_defs = get_source_files($start_epoch);

if (!$remote->call_with_runner('exists_merge_json') || $force_sync) {
    require FindBin;
    $remote->ssh->rsync_put("$FindBin::RealBin/merge-json.pl", $merge_json);
    $remote->call_with_runner('exists_merge_json')
	or error "Problem while syncing to $merge_json";
}

my $count = 0;
for my $file_def (@file_defs) {
    my($path, $mtime) = @{$file_def}{qw(path mtime)};
    info qq{Working on '$path' (@{[ strftime("%F %T", localtime $mtime) ]})};
    $remote->ssh->rsync_put({compress=>1}, $path, "/tmp")
	or error "Error while copying $path to /tmp on remote";
    my $base = basename($path);
    # XXX should use a "proper" location for merge-json.pl
    $remote->system('/tmp/merge-json.pl', '--lockfile', "/home/andreas/var/metabase-log/log-as-json.status", "/tmp/$base", "/home/andreas/var/metabase-log/log-as-json/", "--doit");
    $doit->file_atomic_write($ts_file, sub {
				 my $fh = shift;
				 print $fh $mtime, "\n";
			     });
    $remote->ssh->system('rm', '-f', "/tmp/$base"); # must use same user as for rsync_put
    $count++;
    if ($max_count && $count >= $max_count) {
	info "--max-count reached";
	last;
    }
}
__END__
