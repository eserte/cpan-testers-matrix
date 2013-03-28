#!/usr/bin/perl -w
# -*- perl -*-

#
# Author: Slaven Rezic
#
# Copyright (C) 2012,2013 Slaven Rezic. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.
#
# Mail: slaven@rezic.de
# WWW:  http://www.rezic.de/eserte/
#

use strict;
use CGI qw(-oldstyle_urls);

my $q = CGI->new;
my $i = $q->param('i');
$i++;
if ($i > 2) {
    die "ZDJELAMEDA: too many retries ($i)\n";
}

my $link = do {
    my $qq = CGI->new($q);
    $qq->param(i => $i);
    $qq->self_url;
};

print $q->header;
print $q->start_html('zdjelameda');
print qq{If you're a bot, then <a href="$link">retry</a>!};
print $q->end_html;

__END__
