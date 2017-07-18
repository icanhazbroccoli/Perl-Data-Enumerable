#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Data::Stream;

{
  my $ix = 0;
  my $stream = Data::Stream->new({
    on_has_next => sub { $ix < 10 },
    on_next => sub { shift->yield($ix++) },
    is_finite => 1,
    _no_wrap => 0,
  });
  diag Data::Dumper::Dumper($stream->to_list);
  is_deeply $stream->to_list, [0..9];
}

done_testing;
