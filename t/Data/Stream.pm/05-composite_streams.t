#!/usr/local/bin/perl

use strict;
use warnings;

use Test::More;

use Data::Stream;

{
  my $i = 0;

  my $stream = Data::Stream->new({
    on_has_next => sub { $i < 10 },
    on_next => sub {
      my $j = 1;
      $i++;
      shift->yield(Data::Stream->new({
        on_has_next => sub { $j <= 10 },
        on_next => sub { shift->yield($i * ($j++)) },
      }))
    },
    is_finite => 1,
  });

  is_deeply $stream->to_list, [map { my $i = $_; map { $_ * $i} 1..10  } 1..10]
}

done_testing;
