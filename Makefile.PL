# -*- cperl -*-
use strict;
use ExtUtils::MakeMaker;

my $eumm_recent_enough = $ExtUtils::MakeMaker::VERSION >= 6.54;

if (!$eumm_recent_enough) {
    *MY::dist_core = sub {
	<<'EOF';
dist :
	$(NOECHO) $(ECHO) "Sorry, use a newer EUMM!"

EOF
    };
}

WriteMakefile(NAME =>         'CPAN::Testers::Matrix',
	      VERSION_FROM => 'cgi-bin/cpantestersmatrix.pl',
	      ($eumm_recent_enough ?
	       (META_ADD => { resources => { repository => 'git://github.com/eserte/cpan-testers-matrix.git' },
			    }) : ()),
	      PREREQ_PM => { 'CPAN::DistnameInfo'          => 0,
			     'CPAN::Version'               => 0,
			     'Gravatar::URL'               => 0, # optional
			     'HTML::Table'                 => 0,
			     'Kwalify'			   => 0, # only for validation of "amendment" data
			     'LWP'			   => 5.808,
#XXX does not build under stackato ---			     'Parse::CPAN::Packages::Fast' => 0, # may work also without
			     'version'			   => 0.76, # may work also with CPAN::Version
			     'JSON::XS'			   => 0,
			     'YAML::Syck'		   => 0, # may work also with YAML, but not recommended
			     #'XML::LibXML'                => 0, # was needed for the old .rss files
#XXX additional stackato prereqs
'Plack::Builder' => 0,
'CGI::Emulate::PSGI' => 0,
'CGI::Compile' => 0,
			   },
	     );

sub MY::postamble {
    my $postamble = <<'EOF';
validate-cpantestersmatrix-data:
	pkwalify -f etc/cpantesters_amendments.kwalify data/cpantesters_amendments.yml

fix-permissions:
	chmod ugo+rx cgi-bin/cpantestersmatrix.pl
	chmod ugo+r data/*.yml htdocs/* images/*

rsync-live-cpantestersmatrix-stable:	fix-permissions rsync-live-cpantestersmatrix-favicon rsync-live-cpantestersmatrix-js
	@echo -n "Are you sure? This is stable! CTRL-C if not! "
	@read yn
	rsync -av cgi-bin/cpantestersmatrix.pl live-matrix:/root/work/cpantestersmatrix/cpantestersmatrix.pl

rsync-live-cpantestersmatrix-devel:	fix-permissions rsync-live-cpantestersmatrix-favicon rsync-live-cpantestersmatrix-js
	rsync -av cgi-bin/cpantestersmatrix.pl live-matrix:/root/work/cpantestersmatrix/cpantestersmatrix2.pl

rsync-live-cpantestersmatrix-favicon:	fix-permissions
	rsync -av images/cpantesters_favicon.ico live-matrix:/root/work/cpantestersmatrix/cpantesters_favicon.ico

rsync-live-cpantestersmatrix-robots.txt: fix-permissions
	rsync -av htdocs/robots.txt live-matrix:/root/work/cpantestersmatrix/robots.txt

rsync-live-cpantestersmatrix-js: fix-permissions
	rsync -av htdocs/matrix_cpantesters.js live-matrix:/root/work/cpantestersmatrix/matrix_cpantesters.js

rsync-live-cpantestersmatrix-data:	fix-permissions validate-cpantestersmatrix-data
	rsync -av data/cpantesters_amendments.yml live-matrix:/root/work/cpantestersmatrix/cpantesters_amendments.yml

fix-live-cpantestersmatrix-permissions:
	ssh live-matrix chgrp www-data /root/work/cpantestersmatrix
	ssh live-matrix chmod g+w /root/work/cpantestersmatrix

EOF
    $postamble;
}
