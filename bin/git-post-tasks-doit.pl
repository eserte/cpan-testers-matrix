#!/usr/bin/env perl
# -*- perl -*-

use if !$ENV{DOIT_IN_REMOTE}, lib => "$ENV{HOME}/src/Doit/lib";
use Doit;
use Doit::Log;
use Getopt::Long;
use POSIX qw(strftime);

sub generate_git_tag {
    my $base = "deployment/bbbikede/" . strftime("%Y%m%d", localtime);
    my $tag = $base;
    my $doit = shift;

    for my $i (0..9) {
        my $try = $i == 0 ? $tag : "${tag}_$i";
        my $exists = eval {
            $doit->info_system(qw(git rev-parse --verify), $try);
            1;
        };
        if (!$exists) {
            return $try;
        }
    }

    error("Too many tags exist with base $tag (_0 to _9)");
}

return 1 if caller;

my $doit = Doit->init;
GetOptions("ignore-dirty-workdir" => \my $ignore_dirty_workdir)
    or error "usage: $0 [--ignore-dirty-workdir] [--dry-run]";

# Ensure working tree is clean
$doit->system(qw(git diff-index --quiet --cached HEAD));

my $dirty_git_error = $ignore_dirty_workdir ? sub { warning @_ } : sub { error @_ };

my $changed = eval {
    $doit->system(qw(git diff-files --quiet));
    0;
};
if ($changed) {
    my @diff = split /\n/, $doit->info_qx(qw(git diff-files));
    $dirty_git_error->("There are uncommitted changes:\n" . join("\n", @diff) . "\nPlease commit or stash your changes first.");
}

my @untracked = split /\n/, $doit->info_qx(qw(git ls-files --exclude-standard --others));
if (@untracked) {
    $dirty_git_error->("There are untracked files:\n" . join("\n", @untracked) . "\nPlease clean up untracked files first.");
}

# Generate tag
my $tag = generate_git_tag($doit);
info("Using tag: $tag");

# Create and push tag
$doit->system(qw(git tag -a -m), "* $tag", $tag);
$doit->system(qw(git push));
$doit->system(qw(git push origin), $tag);

__END__
