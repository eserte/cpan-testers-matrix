#!/usr/bin/env perl
# -*- perl -*-

use if !$ENV{DOIT_IN_REMOTE}, lib => "$ENV{HOME}/src/Doit/lib";
use Doit; # install from CPAN or do "git clone https://github.com/eserte/doit.git ~/src/Doit"
use Doit::Log;
use File::Basename qw(dirname);

my $dest_system = "analysis2022"; # requires an entry in /etc/hosts with the real IP address

sub unpriv_setup {
    my $unpriv_doit = shift;

    Doit::Log::set_label("\@ $dest_system(unpriv)");

    my $repo_localdir = "$ENV{HOME}/src/CPAN/CPAN-Testers-Matrix";
    my $repo_branch = 'master';

    $unpriv_doit->make_path(dirname($repo_localdir));

    my $unit_restart = 0;

    ## Usually no restart needed, as it is still running as a CGI script.
    #$unit_restart++ if
    $unpriv_doit->git_repo_update
	(
	 repository => 'https://github.com/eserte/cpan-testers-matrix.git',
	 directory => $repo_localdir,
	 branch => $repo_branch,
	 allow_remote_url_change => 1,
	);

    # XXX Verzeichnisse überprüfen, evtl. cache_root verlegen? (wobei: dieses Verzeichnis könnte von Zeit zu Zeit aufgeräumt werden, und solange es unterhalb von /tmp liegt, passiert das zumindest bei einem Reboot)
    ## Usually no restart needed, as it is still running as a CGI script.
    ##$unit_restart++ if
    $unpriv_doit->write_binary("$repo_localdir/cgi-bin/cpantestersmatrix.yml", <<"EOF");
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

    $unpriv_doit->make_path('/var/tmp/metabase-log/log-as-ndjson');

    return {
	    repo_localdir => $repo_localdir,
	    unit_restart => $unit_restart,
	   };
}

sub priv_setup {
    my($priv_doit, $info) = @_;

    Doit::Log::set_label("\@ $dest_system(priv)");

    my $repo_localdir = $info->{repo_localdir} // error "Missing information: repo_localdir";
    my $unit_restart = $info->{unit_restart} // error "Missing information:: unit_restart";

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

    my $cron_contents = <<'EOF';
30 * * * * eserte perl -MCPAN -e '$CPAN::Be_Silent = 1; CPAN::Index->reload'
EOF
    $priv_doit->write_binary('/etc/cron.d/cpan-update', $cron_contents);

    my $unit_contents = <<"EOF";
[Unit]
Description=cpan-testers-matrix
After=syslog.target

[Service]
ExecStart=/usr/bin/starman -l :5002 --pid /var/run/starman_cpan-testers-matrix.pid $repo_localdir/cpan-testers-matrix.psgi
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    $unit_restart++
	if $priv_doit->write_binary("/etc/systemd/system/starman_cpan-testers-matrix.service", $unit_contents);

    if ($unit_restart) {
	$priv_doit->system(qw(systemctl daemon-reload));
	$priv_doit->system(qw(systemctl enable starman_cpan-testers-matrix.service));
	$priv_doit->system(qw(systemctl restart starman_cpan-testers-matrix.service));
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

return 1 if caller;

my $doit = Doit->init;
$doit->add_component('git');
$doit->add_component('deb');

check_dest_system_hostname();

my $unpriv_doit = $doit->do_ssh_connect($dest_system);
my $info = $unpriv_doit->call_with_runner('unpriv_setup');

my $priv_doit = $doit->do_ssh_connect($dest_system, as => 'root');
$priv_doit->call_with_runner('priv_setup', $info);

# simple ping test
require LWP::UserAgent;
my $ua = LWP::UserAgent->new;
$ua->timeout(10);
my $url = "http://$dest_system:5002";
my $resp = $ua->get($url);
$resp->is_success or error "Fetching $url failed: " . $resp->dump;
$resp->decoded_content =~ /CPAN Testers Matrix/ or error "Unexpected content on $url: " . $resp->decoded_content;
info "Fetching $url was successful: " . $resp->status_line;

__END__
