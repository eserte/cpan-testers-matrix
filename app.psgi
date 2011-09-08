#!perl

use strict;
use warnings;

use Plack::Builder;
use Plack::App::File;
use Plack::App::WrapCGI;

use Cwd 'cwd';
use File::Spec::Functions 'catfile', 'splitpath';

my $root = (splitpath(catfile(cwd(), __FILE__)))[1];

my $favicon = Plack::App::File->new(
    file => catfile($root, 'images', 'cpantesters_favicon.ico'),
);

builder {
    mount '/favicon.ico' => $favicon;
    mount '/cpantesters_favicon.ico' => $favicon;

    mount '/' => Plack::App::WrapCGI->new(
        script  => catfile($root, 'cgi-bin', 'cpantestersmatrix.pl'),
        execute => 1,
    )->to_app;
};
