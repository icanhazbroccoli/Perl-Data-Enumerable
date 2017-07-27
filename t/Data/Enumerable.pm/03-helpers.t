#!/usr/local/bin/perl

use strict;
use warnings;

use Test::More;
use Data::Enumerable;

{
  my $stream = Data::Enumerable->empty;
  is_deeply $stream->to_list, [];
  is $stream->is_finite, 1;
}

{
  my $stream = Data::Enumerable->singular(42);
  is $stream->is_finite, 1;
  is_deeply $stream->to_list, [42];
}

{
  my $stream = Data::Enumerable->singular(0);
  is $stream->has_next, 1;
  is $stream->next, 0;
  is $stream->has_next, 0;
}

{
  my $stream = Data::Enumerable->from_list(1..8);
  is $stream->is_finite, 1;
  is_deeply $stream->to_list, [1..8];
}

done_testing();
