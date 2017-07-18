package Data::Stream;

use strict;
use warnings;

use Moose;
use Moose::Util::TypeConstraints;
use Carp;
use Time::HiRes qw(usleep time);
use Data::Dumper qw(Dumper);

has on_next => (
  is => 'ro',
  isa => 'CodeRef',
  lazy => 1,
  default => sub {  },
);

has on_has_next => (
  is => 'ro',
  isa => 'CodeRef',
  lazy => 1,
  default => sub { sub { 0 } },
);

has is_finite => (
  is => 'ro',
  isa => 'Bool',
  lazy => 1,
  default => sub { 0 },
);

has on_fail => (
  is => 'ro',
  isa => enum([qw(retry die ignore)]),
  lazy => 1,
  default => sub { 'die' },
);

has retry_interval => (
  is => 'ro',
  isa => 'Int',
  lazy => 1,
  default => sub { 1_000 },
);

has max_attempts => (
  is => 'ro',
  isa => 'Int',
  lazy => 1,
  default => sub { 10 },
);

has backlog_strategy => (
  is => 'ro',
  isa => enum([qw(fifo lifo immediate)]),
  lazy => 1,
  default => sub { 'fifo' },
);

has retry_strategy => (
  is => 'ro',
  isa => enum([qw(basic linear progressive)]),
  lazy => 1,
  default => sub { 'basic' },
);

has _buff => (
  is => 'rw',
  isa => 'Undef | Data::Stream',
  lazy => 1,
  default => sub {},
);

has _backlog => (
  is => 'ro',
  isa => 'ArrayRef',
  lazy => 1,
  default => sub { [] },
);

has _no_wrap => (
  is => 'ro',
  isa => 'Bool',
  lazy => 1,
  default => sub { 0 },
);

has _signature => (
  is => 'ro',
  isa => 'Str | Undef',
  lazy => 1,
  default => sub { '' },
);

sub next {
  my $self = shift;
  my $res;
  my $has_next = $self->has_next;
  my $has_backlog = scalar(@{ $self->_backlog }) > 0;
  warn sprintf('has_next: %i, has_backlog: %i, signature: %s', $has_next, $has_backlog, $self->_signature // '');
  return empty()
    unless $has_next or $has_backlog;
  if ($has_backlog) {
    my $retry_item_ix = ($self->backlog_strategy eq 'lifo') ? scalar(@{ $self->_backlog }) - 1 : 0;
    my $retry_item = $self->_backlog->[ $retry_item_ix ];
    my $retry_delta = $self->_retry_in_delta($retry_item);
    if ($retry_delta <= 0) {
      eval {
        $res = $self->_retry($retry_item);
        1;
      } or do {
        return $self->_fail($retry_item, $@ // 'zombie error');
      };
      $self->_buff($res)
        unless $self->_no_wrap;
    }
  } else {
    unless ($self->_buff && $self->_buff->has_next) {
      eval {
        defined $res or carp sprintf('Res is undefined %s %i', $self->_signature, $self->has_next);
        $res = $self->on_next->($self, @_);
        defined $res or confess sprintf('Res is undefined %s %i', $self->_signature, $self->has_next);
        1;
      } or do {
        if ($self->on_fail eq 'ignore') {
          return $self->next();
        } elsif ($self->on_fail eq 'retry') {
          return $self->_fail({
            failed_cnt => 1,
            key => shift,
            args => \@_,
          }, $@ // 'zombie error');
        }
        croak sprintf('Problem calling on_next(): %s', $@ // 'zombie error');
      };
      $self->_buff($res)
        unless $self->_no_wrap;
    }
  }
  warn Dumper(["value: ", $res, $self->_buff, $self->_buff ? $self->_buff->has_next : -1]);
  my $return = $self->_no_wrap ? $res : $self->_buff->next;
  carp Dumper([ "return", $return ]);
  return $return;
}

sub has_next {
  my $self = shift;
  my $res;
  eval {
    $res =  (scalar(@{ $self->_backlog }) > 0)       ||
            ($self->_buff && $self->_buff->has_next) ||
            $self->on_has_next->($self, @_);
    1;
  } or do {
    croak sprintf('Problem calling on_has_next(): %s', $@ // 'zombie error');
  };
  return int $res;
}

sub to_list {
  my ($self) = @_;
  croak 'The stream is defined as infinite. Provide `is_finite` = 1 to make it convertable to list'
    unless $self->is_finite;
  my @acc;
  push @acc, $self->next while $self->has_next;
  return \@acc;
}

sub map {
  my ($self, $callback) = @_;
  Data::Stream->new({
    on_has_next => $self->on_has_next,
    on_next     => sub { shift; $callback->($self, @_) },
    is_finite   => $self->is_finite,
    _no_wrap    => $self->_no_wrap,
  });
}

sub resolve {
  my ($self) = @_;
  $self->next() while $self->has_next;
}

sub take {
  my ($self, $slice_size) = @_;
  my $ix = 0;
  my @acc;
  push @acc, $self->next while ($self->has_next && $ix < $slice_size);
  return \@acc;
}

sub continue {
  my ($self, $ext) = @_;
  my %ext = %$ext;
  my $on_next = delete $ext{on_next}
    or croak '`on_next` should be defined on stream continuation';
  Data::Stream->new({
    on_next => sub {
      my ($self, $key) = @_;
      $self->yield($key, $on_next);
    },
    on_has_next => delete $ext->{on_has_next} // $self->on_has_next,
    is_finite   => delete $ext->{is_finite}   // $self->is_finite,
    _no_wrap    => delete $ext->{is_finite}   // $self->_no_wrap,
  });
}

# Private methods

sub _retry_in_delta {
  my ($self, $item) = @_;

  my $delta = $self->retry_interval;
  if ($self->backlog_strategy eq 'immediate') {
    return 0;
  } elsif ($self->backlog_strategy eq 'linear') {
    $delta *= $item->{failed_cnt};
  } elsif ($self->backlog_strategy eq 'progressive') {
    $delta *= 2 ** $item->{failed_cnt};
  }
  my $retry_at = $item->{failed_at} + $delta;
  return int($retry_at - time * 1_000);
}

sub yield {
  my $self = shift;
  my $val = shift;
  if (scalar @_) {
    # unresolved
    my $callback = shift;
    ref($callback) eq 'CODE'
      or croak 'The 2nd argument of yield should be a callback';
    eval {
      $val = $callback->($self, $val, @_);
      1;
    } or do {
      my $error = sprintf('Failed to resolve the stream step: %s', $@ // 'zombie error');
      return $self->_fail({
        error => $error,
        key => $val,
        args => [ $callback ]
      });
    }
  }
  my $val_is_stream = $val && ref($val) eq 'HASH' && $val->isa('Data::Stream');
  if ($self->_no_wrap || $val_is_stream) {
    if ($self->_signature eq 'singular') {
      carp sprintf('Returning value: %i', $val);
    }
    carp sprintf('Returning a plain value: %i', $val);
    return $val;
  } else {
    defined $val or confess 'should not happen';
    carp sprintf('Wrapping a plain value: %s', Dumper($val));
    return Data::Stream->singular($val);
  }
}

sub _fail {
  my ($self, $failed_item, $error) = @_;
  $error //= $failed_item->{error} // 'Undefined error while resolving the stream step';
  my $key = $failed_item->{key};
  if ($self->on_fail eq 'retry') {
    if ($key) {
      $failed_item->{last_failed} = int(time * 1_000);
      $failed_item->{failed_cnt}++;
      push @{ $self->_backlog }, $failed_item;
    } else {
      carp 'Step key is undefined, the operation will not be retried';
    }
  } elsif ($self->on_fail eq 'die') {
    croak $error;
  }
  $self->next();
}

# Class methods

sub empty {
  Data::Stream->new({
    is_finite   => 1,
    _no_wrap    => 1,
    _signature  => 'empty',
  });
}

sub singular {
  my ($class, $val) = @_;
  my $resolved = 0;
  carp sprintf('Initialized a new singular: %i', $val);
  Data::Stream->new({
    on_has_next => sub { not $resolved },
    on_next     => sub { $resolved = 1; carp(sprintf("!!! return value: %i", $val)); shift->yield($val) },
    is_finite   => 1,
    _no_wrap    => 1,
    _signature  => 'singular',
  });
}

sub from_list {
  my $class = shift;
  my @list = @_;
  my $ix = 0;
  Data::Stream->new({
    on_has_next => sub { $ix < scalar(@list) },
    on_next     => sub { shift->yield($list[$ix++]) },
    is_finite   => 1,
    _no_wrap    => 1,
  });
}

1;
