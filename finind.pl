#!/usr/bin/perl -w
#
use strict;
use feature ':5.10';
use utf8;
use open qw(:std :utf8);
use DDP { multiline => 0, use_prototypes => 0, };
use Term::ANSIColor qw(:constants);
$Term::ANSIColor::AUTORESET = 1;

use DenisYurashkuFindIndex;

$|++;

my $fi = DenisYurashkuFindIndex->new;

my @arr = (5,6,8,14,38,40,123,156,158,213,355,356,400,500);
p(\@arr);
my $x = 157;
say "x= $x";
my $res = $fi->find($x,\@arr);
p($res);

$x = 211;
say "x= $x";
$res = $fi->find($x,\@arr);
p($res);

$x = 500;
say "x= $x";
$res = $fi->find($x,\@arr);
p($res);

$x = 158;
say "x= $x";
$res = $fi->find($x,\@arr);
p($res);

$x = 1;
say "x= $x";
$res = $fi->find($x,\@arr);
p($res);

$x = 1158;
say "x= $x";
$res = $fi->find($x,\@arr);
p($res);

exit;
