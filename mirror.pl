#!/usr/bin/perl -w

=pod

Helper script to merge repository files for LMS <= 7.8 from the svn repository
into one single extensions.xml file for LMS 7.9. Can be run standalone or as a CGI script.

This script can add a servers.xml. It can carry a list of server
version to be used by LMS to check for updates:

{
    'osx' => {
        'revision' => '1425041484',
        'name' => 'osx',
        'url' => 'http://downloads.slimdevices.com/nightly/7.9/sc/1b92e24/LogitechMediaServer-7.9.0-1425041484.pkg',
        'version' => '7.9.0'
    },
    'deb' => {
        'url' => 'http://downloads.slimdevices.com/nightly/7.9/sc/1b92e24/logitechmediaserver_7.9.0~1425041484_all.deb',
        'version' => '7.9.0',
        'revision' => '1425041484',
        'name' => 'deb'
    },
    'win' => {
        'url' => 'http://downloads.slimdevices.com/nightly/7.9/sc/1b92e24/LogitechMediaServer-7.9.0-1425041484.exe',
        'version' => '7.9.0',
        'name' => 'win',
        'revision' => '1425041484'
    },
    ...
};

=cut

use strict;
use utf8;

# constants for nightly checks of beta builds
use constant BASE_URL_SERVER => 'http://downloads.slimdevices.com/nightly/';
use constant NIGHTLY_VERSIONS => qw/7.9.4 8.0.0/;
use constant SERVERS_URL => BASE_URL_SERVER . '?ver=';
use constant BASE_DIR => '/home/httpd/vhosts/herger.net/repos.squeezecommunity.org/';
use constant TEMP_DIR => '/home/httpd/vhosts/herger.net/private/repos_tmp/';

my $WEB;
my $REPOSFILE = BASE_DIR . 'extensions.xml';
my $TEMPFILE = TEMP_DIR . $$ . 'temp.xml';

if ($ENV{'REQUEST_METHOD'}) {
    require CGI;
    $WEB = 1;
}

use Data::Dumper;
use LWP::UserAgent;
use XML::Simple;

use constant REPOS => 'http://svn.slimdevices.com/repos/slim/vendor/plugins/repo.xml';
use constant OTHER => 'http://svn.slimdevices.com/repos/slim/vendor/plugins/other.xml';

use constant TITLE => [
    { lang => 'CS', content => 'Jiné pluginy třetích stran' },
    { lang => 'DA', content => 'Udvidelsesmoduler fra tredjepart' },
    { lang => 'DE', content => 'Plugins von Drittanbietern' },
    { lang => 'EN', content => '3rd party plugins' },
    { lang => 'ES', content => 'Complementos de terceros' },
    { lang => 'FI', content => 'Valmistajien laajennukset' },
    { lang => 'FR', content => 'Plugins tiers' },
    { lang => 'IT', content => 'Plugin di terzi' },
    { lang => 'NL', content => 'Plug-ins van derden' },
    { lang => 'NO', content => 'Tredjeparts plugin-moduler' },
    { lang => 'PL', content => 'Pozostałe dodatki innych firm' },
    { lang => 'RU', content => 'Другие подключаемые модули сторонних изготовителей' },
    { lang => 'SV', content => 'Tillägg från tredje part' },
];


print CGI->new->header('text/plain') if $WEB;

my $ua = LWP::UserAgent->new(
    timeout => 15,
);

$ua->agent('Mozilla/5.0, buildrepo');

my $skipUpdate;

my $repository = {};
foreach my $repo ( REPOS, OTHER ) {
    my $resp = $ua->get($repo);

    my $xml = eval { XMLin($resp->decoded_content,
        SuppressEmpty => 1,
        KeyAttr    => [],
        ForceArray => [ 'applet', 'wallpaper', 'sound', 'plugin', 'patch' ],
    ) };

    if ( $@ ) {
        print $@;
        $skipUpdate = 1;
        last;
    }
    else {
        foreach ( keys %$xml ) {
            if ( /details/ ) {
                $repository->{$_}->{title} = TITLE;
                next;
            }

            my ($key) = keys %{$xml->{$_}};
            $repository->{$_} ||= {
                $key => []
            };
            push @{$repository->{$_}->{$key}}, @{$xml->{$_}->{$key}};
        }

    }
}

if (!$skipUpdate) {
    # write XML to temporary file, replace old copy only if needed, to optimize caching
    XMLout($repository,
        OutputFile => $TEMPFILE,
        RootName   => 'extensions',
        KeyAttr    => [ 'name' ],
    );

    if ( `diff $TEMPFILE $REPOSFILE` ) {
        rename $TEMPFILE, $REPOSFILE;
    }

    unlink $TEMPFILE;
}

if ($WEB) {
#    print Dumper($repository);
    print "thanks";
}

foreach my $version (NIGHTLY_VERSIONS) {
    # server download list
    $repository = fetchNightly($version);

    # print Dumper($repository);
    if ($repository) {
        XMLout($repository,
            OutputFile => $TEMPFILE,
            RootName   => 'servers',
            KeyAttr    => ['os'],
        );

        my $serversFile = sprintf('%s%s/servers.xml', BASE_DIR, $version);
        if ( ! -f $serversFile || `diff $TEMPFILE $serversFile` ) {
            rename $TEMPFILE, $serversFile;
        }

        unlink $TEMPFILE;
    }
}


# the following code is used for server nightlies check
sub fetchNightly {
    my ( $version ) = @_;

    # we only need major revision
    my $major = $version;
    $major =~ s/(\d+\.\d+).*/$1/;

    my $list;

    my $ua = LWP::UserAgent->new(
        agent   => 'SqueezeNetwork ',
        timeout => 30,
    );

    my $req = HTTP::Request->new( GET => SERVERS_URL . $major );

    my $res;
    $res = $ua->request($req);

    if ( $res && $res->is_success ) {
        my $revision = 0;

        foreach (split /\n/, $res->content) {

            if (my ($uri) = /href="(.*?(?:LogitechMediaServer|Squeezebox|squeezecenter).*?)"/i) {
                $uri =~ s{^\./}{};

                my $os;

                if ($uri =~ /\.exe$/)            { $os = 'win'; }
                elsif ($uri =~ /\.msi$/)         { $os = 'whs'; }
                elsif ($uri =~ /\.pkg$/)         { $os = 'osx'; }
                elsif ($uri =~ /amd64\.deb$/)    { $os = 'debamd64'; }
                elsif ($uri =~ /arm\.deb$/)      { $os = 'debarm'; }
                elsif ($uri =~ /i386\.deb$/)     { $os = 'debi386'; }
                elsif ($uri =~ /all\.deb$/)      { $os = 'deb'; }
                elsif ($uri =~ /\.rpm$/)         { $os = 'rpm'; }
                elsif ($uri =~ /sparc-readynas/) { $os = 'readynas'; }
                elsif ($uri =~ /i386-readynas/)  { $os = 'readynaspro'; }
                elsif ($uri =~ /arm-readynas/)   { $os = 'readynasarm'; }
                elsif ($uri =~ /noCPAN/)         { $os = 'nocpan'; }

                my ($v, $r) = $uri =~ /($major\.\d).*(\d{10})/;

                $revision = $revision > $r ? $revision : $r;

                $list->{$os} = {
                    version => $v,
                    revision => $r,
                    url => BASE_URL_SERVER . $uri,
                } if $os && $v && $r;
            }
        }

        if ($revision) {
            $list->{default} = {
                version => $version,
                revision => $revision,
                url => SERVERS_URL . $major,
            };
        }
    }

    return $list;
}

1;