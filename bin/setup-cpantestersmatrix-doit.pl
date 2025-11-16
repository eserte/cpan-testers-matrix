#!/usr/bin/env perl
# -*- perl -*-

use if !$ENV{DOIT_IN_REMOTE}, lib => "$ENV{HOME}/src/Doit/lib";
use if !$ENV{DOIT_IN_REMOTE}, lib => "$ENV{HOME}/src/Doit-Experiments/lib";
use Doit; # install from CPAN or do "git clone https://github.com/eserte/doit.git ~/src/Doit"
          # also                    "git clone https://github.com/eserte/Doit-Experiments.git ~/src/Doit-Experiments"
use Doit::Log;
use File::Basename qw(dirname);
use Hash::Util 'lock_keys';

my $dest_system = "analysis2022"; # requires an entry in /etc/hosts with the real IP address

my %variant_info = (
    fast2 => {
	install_root       => undef, # XXX will be filled later using $HOME
	repo_localdir_base => 'CPAN-Testers-Matrix', # XXX should be CPAN-Testers-Matrix.fast2
	repo_branch        => 'master',
	conf_file_content  => <<"EOF",
# PLEASE DO NOT EDIT (source is @{[ __FILE__ ]} line @{[ __LINE__ ]})
cpan_home: $ENV{HOME}/.cpan
plain_packages_file: /tmp/plain_packages_file
static_dist_dir: /var/tmp/metabase-log/log-as-ndjson
cache_root: /tmp/cpantesters_fast_cache
serializer: Sereal
filefmt_dist: ndjson
ndjson_append_url: http://127.0.0.1:6081/matrixndjson
#ndjson_append_url: http://127.0.0.1:3002/matrixndjson
EOF
	unit_name          => 'cpan-testers-matrix', # used also for description and pidfile name # in this caseshould be cpan-testers-matrix.fast2
	port               => 5002,
        listen_host        => '127.0.0.1',
	external_url       => 'https://fast2-matrix.cpantesters.org', # used for ping test
    },
    fast => {
	install_root       => '/srv/www',
	repo_localdir_base => 'CPAN-Testers-Matrix.fast',
	repo_branch        => 'master',
	conf_file_content  => <<"EOF",
# PLEASE DO NOT EDIT (source is @{[ __FILE__ ]} line @{[ __LINE__ ]})
cpan_home: /opt/cpan/.cpan
plain_packages_file: /tmp/plain_packages_file.fast
static_dist_dir: /var/tmp/metabase-log/log-as-ndjson.fast
cache_root: /tmp/cpantesters_cache.fast
serializer: Sereal
EOF
	unit_name          => 'cpan-testers-matrix.std',
	port               => 5003,
        listen_host        => '127.0.0.1',
	#external_url       => 'https://fast-matrix.cpantesters.org', # enable after moving site
    },
    std => {
	install_root       => '/srv/www',
	repo_localdir_base => 'CPAN-Testers-Matrix.std',
	repo_branch        => 'master',
	conf_file_content  => <<"EOF",
# PLEASE DO NOT EDIT (source is @{[ __FILE__ ]} line @{[ __LINE__ ]})
cpan_home: /opt/cpan/.cpan
plain_packages_file: /tmp/plain_packages_file.std
cache_root: /var/tmp/cpantesters_cache.std
serializer: Sereal
EOF
	unit_name          => 'cpan-testers-matrix.std',
	port               => 5004,
        listen_host        => '127.0.0.1',
	#external_url       => 'https://matrix.cpantesters.org', # enable after moving site
    },
    beta => {
	install_root       => '/srv/www',
	repo_localdir_base => 'CPAN-Testers-Matrix.beta',
	repo_branch        => 'master',
	conf_file_content  => <<"EOF",
# PLEASE DO NOT EDIT (source is @{[ __FILE__ ]} line @{[ __LINE__ ]})
cpan_home: /opt/cpan/.cpan
plain_packages_file: /tmp/plain_packages_file.beta
cache_root: /var/tmp/cpantesters_cache.beta
serializer: Sereal
EOF
	unit_name          => 'cpan-testers-matrix.beta',
	port               => 5005,
        listen_host        => '127.0.0.1',
	#external_url       => 'https://beta-matrix.cpantesters.org', # enable after moving site
    },
);

sub git_setup {
    my($doit, $variant) = @_;

    my $variant_info = $variant_info{$variant} // error "No support for variant $variant";
    lock_keys %$variant_info;

    my $uname = (getpwuid($<))[0];
    Doit::Log::set_label("\@ $dest_system($uname)");

    my $install_root = $variant_info->{install_root} // "$ENV{HOME}/src/CPAN";
    my $repo_localdir = $install_root . '/' . $variant_info->{repo_localdir_base};
    my $repo_branch = $variant_info->{repo_branch};

    $doit->make_path(dirname($repo_localdir));

    my $unit_restart = 0;

    ## Usually no restart needed, as it is still running as a CGI script.
    #$unit_restart++ if
    $doit->git_repo_update
	(
	 repository => 'https://github.com/eserte/cpan-testers-matrix.git',
	 directory => $repo_localdir,
	 branch => $repo_branch,
	 allow_remote_url_change => 1,
	);

    # XXX Verzeichnisse überprüfen, evtl. cache_root verlegen? (wobei: dieses Verzeichnis könnte von Zeit zu Zeit aufgeräumt werden, und solange es unterhalb von /tmp liegt, passiert das zumindest bei einem Reboot)
    ## Usually no restart needed, as it is still running as a CGI script.
    ##$unit_restart++ if
    $doit->write_binary("$repo_localdir/cgi-bin/cpantestersmatrix.yml", $variant_info->{conf_file_content});
    if ($variant_info->{conf_file_content} =~ /^static_dist_dir:\s*(\S+)$/m) { # XXX actually would be better to do YAML parsing, but maybe we don't have YAML available
	$doit->make_path($1);
    }

    return {
	    repo_localdir => $repo_localdir,
	    unit_restart => $unit_restart,
	   };
}

sub priv_setup {
    my($priv_doit, $variant, $info) = @_;

    my $variant_info = $variant_info{$variant} // error "No support for variant $variant";
    lock_keys %$variant_info;

    my $uname = (getpwuid($<))[0];
    Doit::Log::set_label("\@ $dest_system($uname)");

    my $repo_localdir = $info->{repo_localdir} // error "Missing information: repo_localdir";
    my $unit_restart = $info->{unit_restart} // error "Missing information:: unit_restart";

    $priv_doit->make_path('/opt/cpan');

    $priv_doit->chown(-1, 'www-data', "$repo_localdir/data");
    $priv_doit->chmod(0775, "$repo_localdir/data");

    if (!eval { $priv_doit->info_qx({quiet=>1}, 'grep', '-sqr', '^[^#].*ppa.launchpad.net/eserte/bbbike', '/etc/apt/sources.list.d'); 1 }) {
	$priv_doit->system(qw(add-apt-repository ppa:eserte/bbbike));
    }

    $priv_doit->deb_install_packages
	(qw(
	       starman
	       libcgi-pm-perl
	       libcpan-distnameinfo-perl
	       libgravatar-url-perl
	       libhtml-table-perl
	       libjson-xs-perl
	       libparse-cpan-packages-fast-perl
	       liburi-query-perl
	       libversion-perl
	       libwww-perl
	       libyaml-syck-perl
	       libfile-readbackwards-perl
	       libsereal-decoder-perl
	       libsereal-encoder-perl
	       libplack-perl
	  ));

    # At this point libyaml-syck-perl is already available, see deb_install_packages call above
    require YAML::Syck;
    my $conf_data = YAML::Syck::Load($variant_info->{conf_file_content});
    if ($conf_data->{static_dist_dir}) {
	$priv_doit->make_path($conf_data->{static_dist_dir});
	$priv_doit->chown('www-data', -1, $conf_data->{static_dist_dir});
    }

    {
	my $cron_contents = <<"EOF" . <<'EOF';
# PLEASE DO NOT EDIT (source is @{[ __FILE__ ]} line @{[ __LINE__ ]})
EOF
# for variant fast2-matrix (until migrated to /srv/www)
30 * * * * eserte perl -MCPAN -e '$CPAN::Be_Silent = 1; CPAN::Index->reload'
# for all other variants
33 * * * * root   env HOME=/opt/cpan perl -MCPAN -e '$CPAN::Be_Silent = 1; CPAN::Index->reload'
EOF
	$priv_doit->write_binary('/etc/cron.d/cpan-update', $cron_contents);
    }

    if ($variant eq 'fast') {
	my $cron_wrapper = '/home/eserte/bin/sh/cron-wrapper';
	if (!$priv_doit->ft_exists($cron_wrapper)) {
	    error "Please make sure that $cron_wrapper exists (i.e. checking out eserte's bin/sh"; # XXX should be a public repo!
	}
	my $cron_contents = <<"EOF";
# PLEASE DO NOT EDIT (source is @{[ __FILE__ ]} line @{[ __LINE__ ]})
2,7,12,17,22,27,32,37,42,47,52,57 * * * * eserte $cron_wrapper nice ionice -n7 $repo_localdir/bin/tail-log-to-ndjson-wrapper.pl
EOF
	## XXX currently disabled, as tail-log-to-ndjson-wrapper.pl needs more work
	#$priv_doit->write_binary('/etc/cron.d/fast-matrix', $cron_contents);
    }

    my $unit_contents = <<"EOF";
[Unit]
Description=$variant_info->{unit_name}
After=syslog.target

[Service]
User=www-data
Group=www-data

RuntimeDirectory=starman_$variant_info->{unit_name}
PIDFile=/run/starman_$variant_info->{unit_name}/starman.pid

ExecStart=/usr/bin/starman -l $variant_info->{listen_host}:$variant_info->{port} --pid /run/starman_$variant_info->{unit_name}/starman.pid $repo_localdir/cpan-testers-matrix.psgi
Environment="BOTCHECKER_JS_ENABLED=1"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    $unit_restart++
	if $priv_doit->write_binary("/etc/systemd/system/starman_$variant_info->{unit_name}.service", $unit_contents);

    if ($unit_restart) {
	$priv_doit->system(qw(systemctl daemon-reload));
	$priv_doit->system(qw(systemctl enable),"starman_$variant_info->{unit_name}.service");
	$priv_doit->system(qw(systemctl restart), "starman_$variant_info->{unit_name}.service");
    }
}

sub check_dest_system_hostname {
    require Socket;
    require Net::hostent;
    my $hostent = Net::hostent::gethost($dest_system);
    if (!$hostent) {
	warning "Cannot resolve '$dest_system'. Maybe a custom /etc/hosts entry for this host is necessary? (Script will likely fail later)";
    }
}

sub ping_test {
    my($doit, $url) = @_;
    require LWP::UserAgent;
    require Sys::Hostname;
    my $msg_prefix = "Fetching $url from " . Sys::Hostname::hostname();
    my $ua = LWP::UserAgent->new;
    $ua->timeout(10);
    my $resp;
    my $max_try = 3;
 TRY: for my $try (1..$max_try) {
	$resp = $ua->get($url);
	last TRY if $resp->is_success;
	warning "Try $try/$max_try not successful (" . $resp->status_line . ")";
	sleep 1 if $try < $max_try;
    }
    $resp->is_success or do {
	error "$msg_prefix failed: " . $resp->dump . <<EOF;
Diagnostics help:
- check 'systemctl status starman_....service' for error messages
- make sure that botchecker is deployed if BOTCHECKER_JS_ENABLED=1 is set
EOF
    };
    $resp->decoded_content =~ /(CPAN Testers Matrix|JavaScript Required)/ or error "$msg_prefix, but unexpected content: " . $resp->decoded_content;
    info "$msg_prefix was successful: " . $resp->status_line;
}

return 1 if caller;

require Getopt::Long;

$ENV{LC_ALL} = 'C.UTF-8'; # conservative choice, avoid locale warnings

my $doit = Doit->init;
$doit->add_component('git');
$doit->add_component('deb');
$doit->add_component('DoitX::Ft');

my $variant = 'fast2';
Getopt::Long::GetOptions("variant=s" => \$variant)
    or error "usage: $0 [--dry-run] [--variant std|beta|fast|fast2]\n";
my $variant_info = $variant_info{$variant}
    or error "unsupported variant '$variant', use: " . join(", ", sort keys %variant_info);

check_dest_system_hostname();

my $remote_priv_doit = $doit->do_ssh_connect($dest_system, as => 'root');

my $remote_git_doit;
if ($variant eq 'fast2') { # XXX this will change once everything runs in /srv/www
    $remote_git_doit = $doit->do_ssh_connect($dest_system);
} else {
    $remote_git_doit = $remote_priv_doit;
}
my $info = $remote_git_doit->call_with_runner('git_setup', $variant);

$remote_priv_doit->call_with_runner('priv_setup', $variant, $info);

# ping test(s)
if ($variant_info->{listen_host} =~ m{^(|0\.0\.0\.0)$}) {
    $doit->call_with_runner('ping_test', "http://$dest_system:$variant_info->{port}");
} else {
    $remote_git_doit->call_with_runner('ping_test', "http://127.0.0.1:$variant_info->{port}");
}
if ($variant_info->{external_url}) {
    $doit->call_with_runner('ping_test', $variant_info->{external_url});
}

__END__
