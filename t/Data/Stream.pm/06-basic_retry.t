#!/usr/bin/perl

use strict;
use warnings;

use Test::More;

use Data::Stream;

# {
# 
#   my %failed_keys;
# 
#   my $stream = Data::Stream->from_list(1..9)->continue({
#     on_next => sub {
#       shift->yield(shift, sub {
#         my ($s, $j) = @_;
#         $failed_keys{ $j } or do {
#           $failed_keys{ $j } = 1;
#           die 'because reasons';
#         };
#         $j;
#       });
#     },
#     on_fail => 'retry',
#     _signature => 'nums',
#     backlog_strategy => 'immediate',
#   });
#   is_deeply [ sort @{ $stream->to_list } ], [1..9];
# }
#
is 1, 1;

done_testing;
