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

has _buff => (
  is => 'rw',
  isa => 'Undef | Data::Stream',
  lazy => 1,
  default => sub {},
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
  unless ($self->_buff && $self->_buff->has_next) {
    $res = $self->on_next->($self, @_);
    $self->_buff($res)
      unless $self->_no_wrap;
  }
  my $return = $self->_no_wrap ? $res : $self->_buff->next;
  return $return;
}

sub has_next {
  my $self = shift;
  my $res;
  eval {
    $res = $self->_has_next_in_buffer()    ||
           $self->_has_next_in_generator();
    1;
  } or do {
    croak sprintf('Problem calling on_has_next(): %s', $@ // 'zombie error');
  };
  return int $res;
}

sub _has_next_in_buffer    { my $self = shift; defined($self->_buff) && $self->_buff->has_next }
sub _has_next_in_generator { my $self = shift; $self->on_has_next->($self, @_) }

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

sub grep {
  my ($self, $callback, $max_lookahead) = @_;
  my $next;
  my $initialized = 0;
  $max_lookahead //= 0;
  Data::Stream->new({
    on_has_next => sub {
      my $ix = 0;
      $initialized = 1;
      undef $next;
      while ($self->has_next) {
        if ($max_lookahead > 0) {
          $ix > $max_lookahead
            and do {
              carp sprintf 'Max lookahead steps cnt reached. Bailing out';
              return 0;
            };
        }
        $next = $self->next;
        $callback->($next) and last;
        undef $next;
        $ix++;
      }
      return defined $next;
    },
    on_next => sub {
      my $self = shift;
      $initialized or $self->has_next;
      $self->yield($next);
    },
    is_finite => $self->is_finite,
    _no_wrap => $self->_no_wrap,
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
  push @acc, $self->next while ($self->has_next && $ix++ < $slice_size);
  return \@acc;
}

sub continue {
  my ($this, $ext) = @_;
  my %ext = %$ext;
  my $on_next = delete $ext{on_next}
    or croak '`on_next` should be defined on stream continuation';
  Data::Stream->new({
    on_next => sub {
      my $self = shift;
      $self->yield($on_next->($self, $this->next));
    },
    on_has_next => delete $ext->{on_has_next} // $this->on_has_next,
    is_finite   => delete $ext->{is_finite}   // $this->is_finite,
    _no_wrap    => delete $ext->{is_finite}   // $this->_no_wrap,
    %ext,
  });
}

# Private methods

sub yield {
  my $self = shift;
  my $val = shift;
  my $val_is_stream = $val && ref($val) eq 'Data::Stream' && $val->isa('Data::Stream');
  if ($self->_no_wrap || $val_is_stream) {
    return $val;
  } else {
    return Data::Stream->singular($val);
  }
}

# Class methods

sub empty {
  Data::Stream->new({
    is_finite   => 1,
    _no_wrap    => 1,
  });
}

sub singular {
  my ($class, $val) = @_;
  my $resolved = 0;
  Data::Stream->new({
    on_has_next => sub { not $resolved },
    on_next     => sub { $resolved = 1; shift->yield($val) },
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
    on_next     => sub { shift->yield($list[$ix++]) },
    is_finite   => 1,
    _no_wrap    => 1,
  });
}

sub infinity {
  my $class = shift;
  Data::Stream->new({
    on_has_next => sub { 1 },
    on_next     => sub {},
    _is_finite  => 0,
    _no_wrap    => 1,
  });
}

1;
