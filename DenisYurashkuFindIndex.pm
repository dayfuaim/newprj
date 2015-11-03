#!/usr/bin/perl -w
#
package DenisYurashkuFindIndex;
use strict;
use utf8;

sub new {
	my $invocant = shift;
	my $class = ref($invocant) || $invocant;
	my $self = {};
	bless($self, $class);
	$self->{STEPS} = 0;
	return $self
}

sub find {
	my $self = shift;
	my $x = shift; # Number to find index for
	my $arr = shift; # Ref to array of numbers where to find the index
	my $max = $#$arr;
	my $dmin = 1048576;
	$self->{STEPS} = 1;
	return [0, $self->{STEPS}] if ($x<=$arr->[0]); # Before 0 (or 0) of ARRAY
	$self->{STEPS}++;
	return [$max, $self->{STEPS}] if ($x>=$arr->[$max]); # Farther than (or exactly at) LEN() of ARRAY
	foreach my $i (0..$max) {
		my $min_temp = abs($x - $arr->[$i]);
		$self->{STEPS}++;
		if ($min_temp>=$dmin) {
			return [$i-1, $self->{STEPS}]
		} else {
			$dmin = $min_temp
		}
	}
}

sub find1 {
	my $self = shift;
	my $x = shift; # Number to find index for
	my $arr = shift; # Ref to array of numbers where to find the index
	my $max = $#$arr;
	my $i = 0;
	$self->{STEPS} = 1;
	return [0, $self->{STEPS}] if ($x<=$arr->[0]); # Before 0 (or 0) of ARRAY
	$self->{STEPS}++;
	return [$max, $self->{STEPS}] if ($x>=$arr->[$max]); # Farther than (or exactly at) LEN() of ARRAY
	my @arr1 = sort { $a->[1] <=> $b->[1] || $a->[0] <=> $b->[0] } map { [$i++, abs($x-$_)] } @$arr;
	return [$arr1[0]->[0],$self->{STEPS}]
}

1;
