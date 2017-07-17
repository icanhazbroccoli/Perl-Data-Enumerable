#!/usr/bin/perl
use strict;
use warnings;

use Test::More;

use Data::Stream;

{
  my $i = 0;
  my $stream = Data::Stream->new({
    on_has_next => sub { $i < 10 },
    on_next => sub { shift->_yield($i++) },
    is_finite => 1,
  });
  is_deeply $stream->to_list, [0..9];
}

done_testing;
