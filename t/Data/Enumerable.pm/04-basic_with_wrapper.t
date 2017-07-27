#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Data::Enumerable;

{
  my $ix = 0;
  my $stream = Data::Enumerable->new({
    on_has_next => sub { $ix < 10 },
    on_next => sub { shift->yield($ix++) },
    is_finite => 1,
    _no_wrap => 0,
    _signature => 'the_stream',
  });
  is_deeply $stream->to_list, [0..9];
}

done_testing;
