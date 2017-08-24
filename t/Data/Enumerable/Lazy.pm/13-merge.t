#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use Data::Enumerable::Lazy;

{
  my ($i1, $i2) = (1, 1);
  my @streams = (
    Data::Enumerable::Lazy->new({
        on_has_next => sub { $i1 < 10 },
        on_next     => sub { shift->yield($i1 *= 2) },
        is_finite   => 1,
      }),
    Data::Enumerable::Lazy->new({
        on_has_next => sub { $i2 < 10 },
        on_next     => sub { shift->yield($i2 *= 3) },
        is_finite   => 1,
      }),
  );
  my $merged_stream = Data::Enumerable::Lazy->merge(@streams);
  is_deeply $merged_stream->to_list, [2, 3, 4, 9, 8, 27, 16];
}

done_testing;
