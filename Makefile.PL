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
    my $postamble = '';
    my $fix_permissions_data_target = (
				       $^O eq 'freebsd'                       ? 'fix-permissions-data-freebsd' :
				       $^O eq 'linux' && getpwnam('www-data') ? 'fix-permissions-data-debian' :
				       'fix-permissions-data-unhandled'
				      );
    $postamble .= "fix-permissions-data: $fix_permissions_data_target\n\n";
    $postamble .= <<'EOF';
validate-cpantestersmatrix-data:
	pkwalify -f etc/cpantesters_amendments.kwalify data/cpantesters_amendments.yml

validate-config:
	[ ! -e cgi-bin/cpantestersmatrix.yml ] || pkwalify -f etc/cpantestersmatrix_config.kwalify cgi-bin/cpantestersmatrix.yml

update:	git-pull fix-permissions

git-pull:
	git pull --ff-only

fix-permissions: fix-permissions-data
	chmod ugo+rx cgi-bin/cpantestersmatrix.pl cgi-bin/zdjelameda.pl
	chmod ugo+r data/*.yml htdocs/* images/*

fix-permissions-data-freebsd:
	sudo chgrp www data
	sudo chmod g+w data

fix-permissions-data-debian:
	sudo chgrp www-data data
	sudo chmod g+w data

BOTCHECKER=	${HOME}/src/botchecker/Botchecker.pm

EOF

    for my $def (
		 ['live', 'live-matrix'],
		 ['pps', 'pps-matrix'],
		) {
	my($type, $host) = @$def;
	$postamble .= <<EOF;

rsync-$type-cpantestersmatrix:	rsync-$type-cpantestersmatrix-beta rsync-$type-cpantestersmatrix-stable

rsync-$type-cpantestersmatrix-beta:
	rsync -av \${BOTCHECKER} $host:/root/work/cpan-testers-matrix.beta/cgi-bin/

rsync-$type-cpantestersmatrix-stable:
	rsync -av \${BOTCHECKER} $host:/root/work/cpan-testers-matrix/cgi-bin/

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
