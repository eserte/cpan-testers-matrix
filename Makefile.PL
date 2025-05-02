# -*- cperl -*-
use 5.010; # defined-or
use strict;
use Cwd 'realpath', 'getcwd';
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
	      PREREQ_PM => {
			     'CGI'			   => 0,
			     'CPAN::DistnameInfo'          => 0,
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
	      MIN_PERL_VERSION => 5.10.0,
	     );

sub MY::postamble {
    my $srcroot = realpath(getcwd().'/../..');
    my $postamble = '';
    my $fix_permissions_data_target = (
				       $^O eq 'freebsd'                       ? 'fix-permissions-data-freebsd' :
				       $^O eq 'linux' && getpwnam('www-data') ? 'fix-permissions-data-debian' :
				       'fix-permissions-data-unhandled'
				      );
    $postamble .= "fix-permissions-data: $fix_permissions_data_target\n\n";
    $postamble .= <<"EOF";
SRCROOT=	$srcroot

EOF
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

BOTCHECKER=	${SRCROOT}/botchecker/Botchecker.pm
BOTCHECKER_JS=	${SRCROOT}/botchecker/Botchecker_js.pm

EOF

    for my $def (
		 ['live',       'live-matrix',       '/srv/www'],
		 ['pps',        'pps-matrix',        '/root/work'],
		 ['pps-jessie', 'pps-jessie-matrix', '/srv/www'],
		) {
	my($type, $host, $wwwroot) = @$def;
	if ($type eq 'pps' || $type eq 'pps-jessie') {
	    $postamble .= <<EOF;
update-$type-from-home: rsync-$type-cpantestersmatrix
	ssh -A $host 'cd $wwwroot/cpan-testers-matrix.beta && git fetch home && git checkout home/master'
	ssh -A $host 'cd $wwwroot/cpan-testers-matrix.fast && git fetch home && git checkout home/master'
	ssh -A $host 'cd $wwwroot/cpan-testers-matrix && git fetch home && git checkout home/master'

update-$type: rsync-$type-cpantestersmatrix
	ssh -A $host 'cd $wwwroot/cpan-testers-matrix.beta && git checkout master && git pull --ff-only'
	ssh -A $host 'cd $wwwroot/cpan-testers-matrix.fast && git checkout master && git pull --ff-only'
	ssh -A $host 'cd $wwwroot/cpan-testers-matrix && git checkout master && git pull --ff-only'

EOF
	} else {
	    $postamble .= <<EOF;
update-$type-beta: rsync-$type-cpantestersmatrix-beta
	ssh -A $host 'cd $wwwroot/cpan-testers-matrix.beta && git checkout master && git pull --ff-only'

update-$type-beta-from-home: rsync-$type-cpantestersmatrix-beta
	ssh -A $host 'cd $wwwroot/cpan-testers-matrix.beta && git fetch home && git checkout home/master'

update-$type-fast: rsync-$type-cpantestersmatrix-fast
	ssh -A $host 'cd $wwwroot/cpan-testers-matrix.fast && git checkout master && git pull --ff-only'

update-$type-fast-from-home: rsync-$type-cpantestersmatrix-fast
	ssh -A $host 'cd $wwwroot/cpan-testers-matrix.fast && git fetch home && git checkout home/master'

update-$type-stable: rsync-$type-cpantestersmatrix
	ssh -A $host 'cd $wwwroot/cpan-testers-matrix && git checkout master && git pull --ff-only'

EOF
	}
	$postamble .= <<EOF;
rsync-$type-cpantestersmatrix:	rsync-$type-cpantestersmatrix-beta rsync-$type-cpantestersmatrix-fast rsync-$type-cpantestersmatrix-stable

rsync-$type-cpantestersmatrix-beta:
	perl -c \${BOTCHECKER}
	perl -c \${BOTCHECKER_JS}
	rsync -av \${BOTCHECKER} \${BOTCHECKER_JS} $host:$wwwroot/cpan-testers-matrix.beta/cgi-bin/

rsync-$type-cpantestersmatrix-fast:
	perl -c \${BOTCHECKER}
	perl -c \${BOTCHECKER_JS}
	rsync -av \${BOTCHECKER} \${BOTCHECKER_JS} $host:$wwwroot/cpan-testers-matrix.fast/cgi-bin/

rsync-$type-cpantestersmatrix-stable:
	perl -c \${BOTCHECKER}
	perl -c \${BOTCHECKER_JS}
	rsync -av \${BOTCHECKER} \${BOTCHECKER_JS} $host:$wwwroot/cpan-testers-matrix/cgi-bin/

fix-$type-cpantestersmatrix-permissions:
	ssh $host chgrp www-data $wwwroot/cpantestersmatrix
	ssh $host chmod g+w $wwwroot/cpantestersmatrix

EOF
    }

    $postamble .= <<'EOF';
git-post-tasks:
	$(NOECHO) echo -n "This will tag and push. OK? "
	$(NOECHO) read yn
	bin/git-post-tasks-doit.pl

EOF

    $postamble;
}
