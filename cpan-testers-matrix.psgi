#!perl

use strict;
use warnings;
use FindBin;

use Plack::Builder;
use Plack::App::Directory;
use Plack::App::File;
use Plack::App::WrapCGI;

use File::Basename 'basename';
use File::Spec::Functions 'catfile', 'splitpath';
use File::Glob 'bsd_glob';

use constant USE_FORK_NOEXEC => $ENV{USE_FORK_NOEXEC};
BEGIN {
    if (USE_FORK_NOEXEC) {
	warn "Preloading...\n";
	eval q{
use CGI ();
use CGI::Carp ();
use CGI::Cookie ();
use CPAN::Version ();
use File::Basename ();
use HTML::Table ();
use List::Util ();
use LWP::UserAgent ();
use POSIX ();
use URI::Query ();
use Gravatar::URL ();
use Parse::CPAN::Packages::Fast ();
use CPAN::DistnameInfo ();
use version ();
use YAML::Syck ();
use JSON::XS ();
use Storable ();
use Sereal::Encoder ();
use Sereal::Decoder ();
use Time::Local ();
};
	warn $@ if $@;
	warn "Preloading done.\n";
    }
}

my $root = $FindBin::RealBin;

my $favicon = Plack::App::File->new(
    file => catfile($root, 'images', 'cpantesters_favicon.ico'),
)->to_app;

my @mounts;
for my $htdoc (bsd_glob(catfile($root, 'htdocs', '*'))) {
    my $location = '/' . basename($htdoc);
    if (-d $htdoc) {
	push @mounts,  [ $location => Plack::App::Directory->new({root => $htdoc})->to_app ];
    } elsif (-f $htdoc) {
	push @mounts, [ $location => Plack::App::File->new(file => $htdoc)->to_app ];
    } else {
	warn "Ignoring $htdoc...\n";
    }
}

my $script = catfile($root, 'cgi-bin', $ENV{TRAVIS} ? 'cpantestersmatrix-travis.pl' : 'cpantestersmatrix.pl');
my $cgi_app = Plack::App::WrapCGI->new(
    script  => $script,
    execute => USE_FORK_NOEXEC ? 'noexec' : 1,
)->to_app;
my $cgi_app_or_404 = sub {
    my $env = shift;
    if ($env->{PATH_INFO} eq '/') {
        return $cgi_app->($env);
    }
    return [404, ['Content-Type' => 'text/plain'], ['Not Found']];
};

builder {
    mount '/favicon.ico' => $favicon;
    mount '/cpantesters_favicon.ico' => $favicon;

    mount '/images' => Plack::App::Directory->new({ root => catfile($root, 'images') });

    for my $mount (@mounts) {
	mount $mount->[0] => $mount->[1];
    }

    if (USE_FORK_NOEXEC) {
	mount '/slow' => Plack::App::WrapCGI->new(
            script  => $script,
	    execute => 1,
	)->to_app;
	mount '/fast' => Plack::App::WrapCGI->new(
            script  => $script,
	    execute => 'noexec',
	)->to_app;
    }

    mount '/' => $cgi_app_or_404;
};
