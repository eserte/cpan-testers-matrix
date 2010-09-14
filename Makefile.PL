# -*- cperl -*-
use strict;
use ExtUtils::MakeMaker;

eval {
    if ((getpwuid($<))[0] eq 'eserte' && $ExtUtils::MakeMaker::VERSION < 6.54) {
	warn <<EOF;
**********************************************************************
* WARNING:
* ExtUtils::MakeMaker too old. META.yml will be imcomplete
**********************************************************************
EOF
    }
};

WriteMakefile(NAME =>         'CPAN::Testers::Matrix',
	      VERSION_FROM => 'cgi-bin/cpantestersmatrix.pl',
	      ($ExtUtils::MakeMaker::VERSION >= 6.54 ?
	       (META_ADD => { resources => { repository => 'git://github.com/eserte/cpan-testers-matrix.git' },
			    }) : ()),
	      PREREQ_PM => { 'CPAN::DistnameInfo'          => 0,
			     'CPAN::Version'               => 0,
			     'Gravatar::URL'               => 0, # optional
			     'HTML::Table'                 => 0,
			     'Kwalify'			   => 0, # only for validation of "amendment" data
			     'LWP'			   => 5.808,
			     'Parse::CPAN::Packages::Fast' => 0, # may work also without
			     'version'			   => 0.76, # may work also with CPAN::Version
			     'YAML::Syck'		   => 0, # may work also with YAML, but not recommended
			     'XML::LibXML'                 => 0,
			   },
	     );

sub MY::postamble {
    my $postamble = <<'EOF';
validate-cpantestersmatrix-data:
	pkwalify -f etc/cpantesters_amendments.kwalify data/cpantesters_amendments.yml

EOF
    $postamble;
}
