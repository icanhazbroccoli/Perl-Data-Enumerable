#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Data::Enumerable;

{
  my $enum = Data::Enumerable->empty();
  is_deeply $enum->to_list, [], 'An empty enum resolves in an empty list';
}

done_testing;
