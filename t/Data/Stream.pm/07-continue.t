#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Data::Stream;

{
  my $stream = Data::Stream->from_list(0..9)->continue({
    on_next => sub {
      my ($self, $i) = @_;
      $self->yield($i * $i);
    },
    is_finite => 1,
    _signature => 'nums',
  });

  is_deeply $stream->to_list, [map {$_ * $_} 0..9];
}

done_testing;
