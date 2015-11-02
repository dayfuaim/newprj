#!/usr/bin/perl -w
#
use strict;
use feature ':5.10';
use utf8;
use open qw(:std :utf8);
use DDP;
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

use Time::HiRes qw(gettimeofday tv_interval);

use AnyEvent;
use AnyEvent::HTTP;
my $cv = AnyEvent->condvar;

$|++;
my @u = @ARGV;
unless (scalar @u) {
	die RED "Give some URLs to my STDIN."
}

my $time_in = [ gettimeofday ];
my @r;
my $cnt = 0;
foreach my $url (@u) {
	say "GET $url";
	my $guard;
	$guard = http_get($url,
	    sub {
	        undef $guard;
            my ($body, $hdr) = @_;
            $cnt++;
            if ($hdr->{Status} =~ /^2/) {
            	print GREEN "$url: "
            } else {
            	print RED "$url: "
            }
            say $hdr->{Status};
            push @r => [$url, tv_interval($time_in)];
	        $cv->send() if $cnt==scalar @u
	    }
	)
}
$cv->recv;

@r = sort { $b->[1] <=> $a->[1] } @r;

p(@r);

say GREEN "Yeah!";
exit;
