#!/usr/bin/perl

use strict;

use CHI;
use LWP::UserAgent;
use XML::Simple;
use Data::Dumper;

my $includeList = 'include.xml';

my $include = eval { 
	XMLin( $includeList, 
		   ForceArray => 1,
		   KeyAttr    => ['url', 'name', 'filter', 'type', 'output'], 
		  ) 
} || die "$@";

my $cache = CHI->new( driver => 'File', root_dir => 'cache' );

# Invalidate cache after 7 days
my $expires_in = 60*60*24*7;

my $ua = LWP::UserAgent->new(
	timeout => 5,
	ssl_opts => {
		verify_hostname => 0
	}
);

$ua->agent('Mozilla/5.0, buildrepo');

my $out;

for my $url (sort keys %{$include->{'repository'}}) {

	my $filters = $include->{'repository'}->{$url};

	my $maxTarget = delete $filters->{'maxTarget'};

	my $resp = $ua->get($url);
	my $content;

	if (!$resp->is_success) {
		
		warn "error fetching $url - " . $resp->status_line . "\n";

		if ($resp->code == 500) {
			$content = $cache->get($url);
			
			# Invalidate pipeline if cache has expired
			if (!$content)
				die "cache miss...\n";
			}
		}
	} else {
		$content = $resp->content;
		
		# Place $content instead of $resp in cache to minimize diffs
		$cache->set($url, $content, $expires_in);
	}

	if ($content) {
		print "$url\n";

		my $xml = eval { XMLin($content,
							   SuppressEmpty => 1,
							   KeyAttr    => [],
							   ForceArray => [ 'applet', 'wallpaper', 'sound', 'plugin', 'patch' ],
							  ) };

		if ($@) {
			warn "bad xml ($url) $@";
			next;
		}

		for my $content (qw(applet wallpaper sound plugin patch)) {
			my $element = $content."s";
			$element =~ s/patchs/patches/;
			for my $item (@{ $xml->{"${element}"}->{"$content"} || [] }) {

				my $name = $item->{'name'};
				my $maxT = $maxTarget->{$name};
				my $override = "";
				
				if ($maxT && $maxT->{'from'} && $maxT->{'to'} &&
					(!$maxT->{'target'} || !$item->{'target'} || $maxT->{'target'} eq $item->{'target'}) &&
					(!$maxT->{'minTarget'} || !$item->{'minTarget'} || $maxT->{'minTarget'} eq $item->{'minTarget'}) &&
					$maxT->{'from'} eq $item->{'maxTarget'}) {

					$override = "(maxTarget: $item->{maxTarget} -> $maxT->{to})";

					$item->{'maxTarget'} = $maxT->{'to'};
				}

				for my $filter (keys %$filters, 'other') {

					if (($filters->{$filter} && $filters->{$filter}->{$name}) || $filter eq 'other') {

						print "  $content $name => $filter $override\n";

						push @{ $out->{$filter}->{"${element}"}->{"$content"} ||= [] }, $item;
						last;
					}
				}
			}
		}
	}
}

for my $output (keys %{$include->{'output'}}) {

	if ($out->{$output}) {

		$out->{$output}->{'details'} = $include->{'output'}->{$output}->{'details'};

		XMLout($out->{$output}, 
			   OutputFile => $include->{'output'}->{$output}->{'file'},
			   RootName   => 'extensions',
			   KeyAttr    => [ 'name' ],
			   );
	}
}

1;
