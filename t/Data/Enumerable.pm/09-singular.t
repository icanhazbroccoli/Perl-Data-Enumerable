#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Data::Enumerable;

{
  my $enum = Data::Enumerable->singular(42);
  my $list = $enum->to_list;
  ok scalar @$list == 1, 'A single element list';
  is $list->[0], 42, 'Returns the same elemeent';
}

done_testing;
