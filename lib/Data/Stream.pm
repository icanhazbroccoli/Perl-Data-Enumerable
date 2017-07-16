package Data::Stream;

use strict;
use warnings;

use Moose;
use Moose::Util::TypeConstraints;
use Carp;

has on_next => (
  is => 'ro',
  isa => 'CodeRef',
  lazy => 1,
  default => sub { sub { Data::Stream::empty() } },
);

has on_has_next => (
  is => 'ro',
  isa => 'CodeRef',
  lazy => 1,
  default => sub { sub { shift->_buff->has_next() } },
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
  is => 'ro',
  isa => 'Data::Stream',
  lazy => 1,
  default => sub { Data::Stream::empty() },
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

sub next {
  my $self = shift;
  my $res;
  my $has_next = $self->has_next;
  my $has_backlog = scalar(@{ $self->_backlog }) > 0;
  return empty
    unless $has_next or $has_backlog;
  if ($has_backlog) {
    my $retry_item_ix = ($self->backlog_strategy eq 'lifo') ? scalar(@{ $self->_backlog }) - 1 : 0;
    my $retry_item = $self->_backlog->[ $retry_item_ix ];
    my $ready_to_retry = $self->_should_retry($retry_item);
    #TODO
  }
  eval {
    $res = $self->on_next(@_);
    1;
  } or do {
    croak sprintf('Problem calling on_next(): %s', $@ // 'zombie error');
  };
  return $res;
}

sub has_next {
  my $self = shift;
  my $res;
  eval {
    $res = scalar(@{ $self->_backlog }) > 0 or $self->on_has_next(@_);
    1;
  } or do {
    croak sprintf('Problem calling on_has_next(): %s', $@ // 'zombie error');
  };
  return $res;
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
      $self->_yield($key, $on_next);
    },
    on_has_next => delete $ext->{on_has_next} // $self->on_has_next,
    is_finite   => delete $ext->{is_finite}   // $self->is_finite,
    _no_wrap    => delete $ext->{is_finite}   // $self->_no_wrap,
  });
}

# Private methods

sub _should_retry {
  my ($self, $item) = @_;
  return 0
    unless $item;
  return 1
    if $self->retry_strategy eq 'immediate';
  my $retry_at = $item->{failed_at} + 
}

sub _yield {
  my $self = shift;
  my $val = shift;
  # if (scalar @_) {
  #   # unresolved
  #   my $callback = shift;
  #   eval {
  #     $val = $callback->($self, $val, @_);
  #     1;
  #   } or do {
  #     my $error = sprintf('Failed to resolve the stream step: %s', $@ // 'zombie error');
  #     $val = $self->_fail({
  #       error => $error,
  #       key => $val,
  #       extra => [ $callback, );
  #   }
  # }
  my $val_is_stream = $val && ref($val) eq 'HASH' && $val->isa('Data::Stream');
  if ($self->_no_wrap || $val_is_stream) {
    return $val;
  } else {
    return Data::Stream::singular($_[1]);
  }
}

sub _fail {
  my ($self, $failed_item) = @_;
  my $error = $failed_item->{error} // 'Undefined error while resolving the stream step';
  my $key = $failed_item->{key};
  if ($self->on_fail eq 'retry') {
    if ($key) {
      $failed_item->{last_failed} = time;
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
    on_has_next => sub { 0 },
    is_finite   => 1,
  });
}

sub singular {
  my ($class, $val) = @_;
  my $resolved = 0;
  Data::Stream->new({
    on_has_next => sub { not $resolved },
    on_next     => sub { $val },
    is_finite   => 1,
    _no_wrap    => 1,
  });
}

sub from_list {
  my $class = shift;
  my @list = @_;
  my $ix = 0;
  Data::Stream->new({
    on_has_next => sub { $ix < scalar(@list) },
    on_next     => sub { $list[$ix++] },
    is_finite   => 1,
    _no_wrap    => 1,
  });
}

1;
