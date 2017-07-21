#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Data::Stream;

my @tests = (
  {
    given    => [1, 2, 3, undef, 4, undef, 5, undef, 6, 7],
    grep_sub => sub { defined shift },
    expected => [1, 2, 3, 4, 5, 6, 7],
    descr    => 'Filters out undefs',
  },
  {
    given    => [1 .. 5],
    grep_sub => sub { shift > 3 },
    expected => [4, 5],
    descr    => 'Greater than N',
  },
  {
    given    => [1..5],
    grep_sub => sub { 0 },
    expected => [],
    descr    => 'Returns an empty list',
  },
);

{
  foreach my $test (@tests) {
    my ($given, $grep_sub, $expected, $descr) = @$test{qw(given grep_sub expected descr)};
    my $stream = Data::Stream->from_list(@{ $given })->grep($grep_sub);

    is_deeply $stream->to_list, $expected, $descr;
  }
}

done_testing;
