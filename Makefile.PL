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
			     'Parse::CPAN::Packages::Fast' => 0, # may work also without
			     'URI::Query'		   => 0.08, # escaping is wrong before this version
			     'version'			   => 0.76, # may work also with CPAN::Version
			     'JSON::XS'			   => 0,
			     'YAML::Syck'		   => 0, # may work also with YAML, but not recommended
			   },
	     );

sub MY::postamble {
    my $postamble = <<'EOF';
validate-cpantestersmatrix-data:
	pkwalify -f etc/cpantesters_amendments.kwalify data/cpantesters_amendments.yml

validate-config:
	[ ! -e cgi-bin/cpantestersmatrix.yml ] || pkwalify -f etc/cpantestersmatrix_config.kwalify cgi-bin/cpantestersmatrix.yml

fix-permissions:
	chmod ugo+rx cgi-bin/cpantestersmatrix.pl cgi-bin/zdjelameda.pl
	chmod ugo+r data/*.yml htdocs/* images/*

AUXFILES=	${HOME}/src/botchecker/Botchecker.pm

auxiliary-files-exist-check:
	for i in ${AUXFILES}; do [ -r $$i ] || exit 1; done

EOF

    for my $def (
		 ['live', 'live-matrix'],
		 ['pps', 'pps-matrix'],
		) {
	my($type, $host) = @$def;
	$postamble .= <<EOF;

rsync-$type-cpantestersmatrix-stable:	auxiliary-files-exist-check fix-permissions rsync-$type-cpantestersmatrix-images rsync-$type-cpantestersmatrix-js rsync-$type-cpantestersmatrix-data
EOF
	if ($type eq 'live') {
	    $postamble .= <<EOF;
	\@echo -n "Are you sure? This is stable! CTRL-C if not! "
	\@read yn
EOF
	}
	$postamble .= <<EOF;
	rsync -av \${AUXFILES} $host:/root/work/cpantestersmatrix/
	rsync -av cgi-bin/cpantestersmatrix.pl $host:/root/work/cpantestersmatrix/cpantestersmatrix.pl
EOF
	if ($type eq 'live') {
	    $postamble .= <<EOF;
	\@echo "Call now: \${MAKE} after-deployment-set-tags"
EOF
	}
	$postamble .= <<EOF;

rsync-$type-cpantestersmatrix-devel:	fix-permissions rsync-$type-cpantestersmatrix-images rsync-$type-cpantestersmatrix-js rsync-$type-cpantestersmatrix-data
	rsync -av cgi-bin/cpantestersmatrix.pl $host:/root/work/cpantestersmatrix/cpantestersmatrix2.pl

rsync-$type-cpantestersmatrix-misc: fix-permissions
	rsync -av cgi-bin/zdjelameda.pl $host:/root/work/cpantestersmatrix/zdjelameda.pl

rsync-$type-cpantestersmatrix-images:	fix-permissions
	rsync -av images/ $host:/root/work/cpantestersmatrix/images/

rsync-$type-cpantestersmatrix-robots.txt: fix-permissions
	rsync -av htdocs/robots.txt $host:/root/work/cpantestersmatrix/robots.txt

rsync-$type-cpantestersmatrix-js: fix-permissions
	rsync -av htdocs/matrix_cpantesters.js $host:/root/work/cpantestersmatrix/matrix_cpantesters.js

rsync-$type-cpantestersmatrix-data:	fix-permissions validate-cpantestersmatrix-data
	rsync -av data/cpantesters_amendments.yml $host:/root/work/cpantestersmatrix/cpantesters_amendments.yml

fix-$type-cpantestersmatrix-permissions:
	ssh $host chgrp www-data /root/work/cpantestersmatrix
	ssh $host chmod g+w /root/work/cpantestersmatrix

EOF
    }

    $postamble .= <<EOF;
after-deployment-set-tags:
	git tag -f deployment/bbbikede/current
	git tag -a -m "automatic deployment" deployment/bbbikede/`date +%Y%m%d` || echo "If setting this tag fails, then try using a suffix e.g. _2"

EOF

    $postamble;
}
