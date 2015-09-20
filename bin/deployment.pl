#!/usr/bin/perl -w
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2015 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

use strict;
use autodie;
use FindBin;
use Getopt::Long;

sub init ();
sub step ($&);
sub confirmed_step ($&);
sub manual_check_step ($$);
sub confirm_or_exit ($$);
sub successful_system (@);
sub finish ();
sub check_travis ($);
sub debug ($);

my $dry_run;
my $debug;
GetOptions(
	   'debug' => \$debug,
	   'n|dry-run' => \$dry_run,
	  )
    or die "usage: $0 [--dry-run] [--debug]\n";

local $ENV{LC_ALL} = $ENV{LANG} = 'C';

init;
{
    my(@out) = qx{git status};
    if (!grep { /On branch master/ } @out) {
	die "Not on branch master? Output of 'git status'\n@out";
    }
}
confirmed_step "git pull and push", sub {
    print STDERR "Is everything checked in?\n";
    successful_system 'git', 'diff-files', '--quiet';
    #print STDERR "Fetching and comparing with origin...\n";
    #successful_system 'git', 'fetch', 'origin';
    #successful_system 'git', 'diff', '--exit-code', 'origin/master', 'master';
    print STDERR "Pushing to origin...\n";
    successful_system 'git', 'push';
};
step "check travis", sub {
    check_travis 'eserte/cpan-testers-matrix';
};
step "update-pps", sub {
    successful_system 'make', 'update-pps';
};
manual_check_step "pps tests", "Please go to http://matrix-cpantesters-pps and do some manual tests.";
confirmed_step "update-live-beta", sub {
    successful_system 'make', 'update-live-beta';
};
manual_check_step "beta tests", "Please go to http://beta-matrix.cpantesters.org and do some manual tests.";
confirmed_step "update-live-stable", sub {
    successful_system 'make', 'update-live-stable';
};
manual_check_step "stable tests", "Please go to http://matrix.cpantesters.org and do some manual tests.";
confirmed_step "git-post-tasks", sub {
    successful_system 'make', 'git-post-tasks';
};
finish;

{
    my $step_file;
    my %done_steps;

    sub init () {
	chdir "$FindBin::RealBin/..";

	my $step_dir = "$FindBin::RealBin/../var";
	if (!$dry_run) {
	    if (!-d $step_dir) {
		mkdir $step_dir;
	    }
	}
	$step_file = "$step_dir/deployment_steps";
	my $fh;
	if (do { no autodie; open $fh, '<', $step_file }) {
	    chomp(my @last_done_steps = <$fh>);
	    if (@last_done_steps) {
		my $age = time - (stat($step_file))[9];
		print STDERR "Previously aborted deployment (age $age seconds) with the following steps done detected:\n";
		print STDERR map { "  $_\n" } @last_done_steps;
		if ($dry_run) {
		    print STDERR "Note: dry-run mode is active. ";
		}
		print STDERR "[C]ontinue or [r]estart? ";
		while() {
		    chomp(my $yn = <STDIN>);
		    if (lc($yn) eq 'c') {
			%done_steps = map {($_,1)} @last_done_steps;
			last;
		    } elsif (lc($yn) eq 'r') {
			rename $step_file, "$step_file~";
			last;
		    } elsif ($yn eq 'exit') {
			print STDERR "Exiting...\n";
			exit 1;
		    } else {
			print STDERR "Print answer c or r (for continue or restart) ";
		    }
		}
	    }
	}
    }

    sub step ($&) {
	my($name, $code) = @_;
	_step($name, $code);
    }

    sub _step {
	my($name, $code, $with_confirmation) = @_;
	print STDERR "Step '$name'";
	if ($done_steps{$name}) {
	    print STDERR " (already done, skipping)";
	} elsif ($dry_run) {
	    print STDERR " (dry-run)";
	    if ($with_confirmation) {
		print STDERR " (confirmation requested)";
	    }
	} else {
	    print STDERR " ... ";
	    if ($with_confirmation) {
		confirm_or_exit "Run step '$name'? (y) ", "y";
	    }
	    if (eval { $code->(); 1 }) {
		open my $ofh, '>>', $step_file;
		print $ofh $name, "\n";
	    } else {
		die "Step failed: $@";
	    }
	}
	print STDERR "\n";
    }

    sub confirmed_step ($&) {
	my($name, $code) = @_;
	_step($name, $code, 1);
    }

    sub manual_check_step ($$) {
	my($name, $msg) = @_;
	step $name, sub {
	    print STDERR "$msg\n";
	    confirm_or_exit "Everything's OK? (y)", 'y';
	};
    }

    sub confirm_or_exit ($$) {
	my($msg, $confirm_string) = @_;
	print STDERR $msg . ' ';
	while() {
	    chomp(my $got = <STDIN>);
	    if ($got eq 'exit') {
		print STDERR "Exiting...\n";
		exit 1;
	    } elsif ($got eq $confirm_string) {
		last;
	    } else {
		print STDERR qq{Print answer with "$confirm_string" or "exit": };
	    }
	}
    }

    sub successful_system (@) {
	my(@args) = @_;
	system @args;
	die "Command '@args' was not successful" if $? != 0;
    }

    sub finish () {
	if (!$dry_run) {
	    if (defined $step_file && -e $step_file) {
		unlink $step_file;
		if (-e $step_file) {
		    die "Cannot delete '$step_file'";
		}
	    }
	}
    }

    sub check_travis ($) {
	my($repo) = @_;
	chomp(my $current_commit_id = `git log -1 --format=format:'%H'`);
	if (!$current_commit_id) {
	    die "Unexpected: cannot find a commit";
	}
	require LWP::UserAgent;
	require JSON::XS;
	my $ua = LWP::UserAgent->new(timeout => 10);
	my $wait = sub {
	    for (reverse(0..14)) {
		print STDERR "\rwait $_ second(s)";
		sleep 1;
	    }
	    print STDERR "\n";
	};

	my $build_id;
	{
	    my $builds_url = "http://api.travis-ci.org/repos/$repo/builds";
	    my $get_current_build = sub {
		debug "About to get from $builds_url";
		my $res = $ua->get($builds_url);
		if (!$res->is_success) {
		    die "Request to $builds_url failed: " . $res->status_line;
		}
		debug "Fetch successful";
		my $data = JSON::XS::decode_json($res->decoded_content(charset => 'none'));
		for my $build (@$data) {
		    if ($build->{commit} eq $current_commit_id) {
			return $build;
		    }
		}
		debug "Build for commit $current_commit_id not found";
		undef;
	    };
	    while () {
		my $build = $get_current_build->();
		if (!$build) {
		    print STDERR "Cannot find commit $current_commit_id at travis, will try later...\n";
		    $wait->();
		} else {
		    $build_id = $build->{id};
		    if (!defined $build_id) {
			require Data::Dumper;
			die "Unexpected: no build id found in ". Data::Dumper::Dumper($build);
		    }
		    last;
		}
	    }
	}

	{
	    my $build_url = "http://api.travis-ci.org/repos/$repo/builds/$build_id";
	    my $get_current_build = sub {
		debug "About to get from $build_url";
		my $res = $ua->get($build_url);
		if (!$res->is_success) {
		    die "Request to $build_url failed: " . $res->status_line;
		}
		debug "Fetch successful";
		my $data = JSON::XS::decode_json($res->decoded_content(charset => 'none'));
		return $data;
	    };
	    while () {
		my $build = $get_current_build->();
		my $successful = 0;
		my $failures = 0;
		my $running = 0;
		for my $job (@{ $build->{matrix} }) {
		    if (!defined $job->{result}) {
			$running++;
		    } elsif ($job->{result} == 0) {
			$successful++;
		    } else {
			$failures++;
		    }
		}
		if ($failures) {
		    die "At least one job failed.\n";
		} elsif ($running == 0) {
		    last;
		}
		print STDERR "Status at travis: running=$running successful=$successful failures=$failures\n";
		$wait->();
	    }
	}

	print STDERR "travis-ci build was successful\n";
    }

    sub debug ($) {
	my $msg = shift;
	if ($debug) {
	    print STDERR "$msg\n";
	}
    }

}

__END__
