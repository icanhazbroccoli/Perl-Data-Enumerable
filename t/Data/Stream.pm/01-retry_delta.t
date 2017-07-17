#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Data::Stream;

{
  my $i = 0;
  my $now = time;
  my $stream = Data::Stream->new({
    on_next => sub { $i++ },
    on_has_next => sub { 1 },
    on_fail => 'retry',
    retry_strategy => 'linear',
    backlog_strategy => 'fifo',
    retry_interval => 500,
  });
  my $item = {
    failed_at => Time::HiRes::time * 1_000,
    failed_cnt => 1,
  };
  my $retry_in = $stream->_retry_in_delta($item);
  ok $retry_in > 0;
  ok $retry_in < 500;
}

{
  my $i = 0;
  my $now = time;
  my $stream = Data::Stream->new({
    on_next => sub { $i++ },
    on_has_next => sub { 1 },
    on_fail => 'retry',
    retry_strategy => 'linear',
    backlog_strategy => 'immediate',
    retry_interval => 500,
  });
  my $item = {
    failed_at => Time::HiRes::time * 1_000,
    failed_cnt => 1,
  };
  my $retry_in = $stream->_retry_in_delta($item);
  is $retry_in, 0;
}

done_testing();
