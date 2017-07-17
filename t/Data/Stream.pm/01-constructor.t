#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Data::Stream;

{
  my $i = 0;
  my $stream = Data::Stream->new({
    on_next => sub { $i++ },
    on_has_next => sub { 1 },
    retry_strategy => 'linear',
    retry_interval => 500,
  });
  
}

done_testing();
