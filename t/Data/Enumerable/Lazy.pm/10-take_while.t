#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Data::Enumerable::Lazy;

{
  my $enum = Data::Enumerable::Lazy->from_list(0..10)->take_while(sub { $_[1] <= 5 });

  is_deeply $enum->to_list, [0..5], 'Takes first elements that satisfy the requirement';
}

{
  my $enum = Data::Enumerable::Lazy->from_list(0, 0, 0, 0, 0, 1)->take_while(sub { $_[1] > 0 }, 5);
  is $enum->has_next, 0, 'the first matching element is way too far';
}

{
  my $enum = Data::Enumerable::Lazy->from_list(0, 0, 0, 0, 42)->take_while(sub { $_[1] > 0 }, 5);
  is $enum->has_next, 1, 'the first matching element is at the max_lookahead pos';
  is $enum->next, 42, 'the first satisfying element matches';
}
done_testing;
