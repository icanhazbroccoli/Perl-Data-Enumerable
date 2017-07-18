#!/usr/local/bin/perl

use strict;
use warnings;

use Test::More;
use Data::Stream;

{
  my $stream = Data::Stream->empty;
  is_deeply $stream->to_list, [];
  is $stream->is_finite, 1;
}

{
  my $stream = Data::Stream->singular(42);
  is $stream->is_finite, 1;
  is_deeply $stream->to_list, [42];
}

{
  my $stream = Data::Stream->from_list(1..8);
  is $stream->is_finite, 1;
  is_deeply $stream->to_list, [1..8];
}

done_testing();
