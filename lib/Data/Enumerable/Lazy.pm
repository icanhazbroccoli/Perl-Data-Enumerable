package Data::Enumerable::Lazy;

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
  isa => 'Undef | Data::Enumerable::Lazy',
  lazy => 1,
  default => sub {},
);

has _no_wrap => (
  is => 'ro',
  isa => 'Bool',
  lazy => 1,
  default => sub { 0 },
);

=item next/0

Function next() is the primary interface for accessing elements of an
enumerable. It will do some internal checks and if there is no elements to be
served from an intermediate buffer, it will resolve the next step by calling
on_next() callback.
Enumerables are composable: one enumerable might be based on another
enumeration. E.g.: a sequence of natural number squares is based on the
sequence of natural numbers themselves. In other words, a sequence is defined
as a tuple of another sequence and a function which would be lazily applied to
every element of this sequence.

next() accepts 0 or more arguments, which would be passed to on_next() callback.

next() is expected to do the heavy-lifting job in opposite to has_next(), which
is supposed to be cheap and fast. This statement flips upside down whenever
grep() is applied to a stream. See grep() for more details.

=cut

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

=item has_next()

has_next() is the primary entry point to get an information about the state of
an enumetable. If the method returned false, there are no more elements to be
consumed. I.e. the sequence has been iterated completely. Normally it means 
the end of an iteration cycle.

Enumerables use internal buffers in order to support batched on_next()
resolutions. If there are some elements left in the buffer, on_next()
won't call on_has_next() callback immediately. If the buffer has been
iterated completely, on_has_next() would be called.

on_next() should be fast on resolving the state of an enumerable as it's going
to be used for a condition state check.

=cut

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

sub _has_next_in_buffer {
  my $self = shift;
  defined($self->_buff) && $self->_buff->has_next;
}
sub _has_next_in_generator {
  my $self = shift;
  $self->on_has_next->($self, @_);
}

=item to_list()

This function transforms a lazy enumerable to a list. Only finite enumerables
can be transformed to a list, so the method checks if an enumetable is created
with is_finite=1 flag. An exception would be thrown otherwise.

=cut

sub to_list {
  my ($self) = @_;
  croak 'Only finite enumerables might be converted to list. Use is_finite=1'
    unless $self->is_finite;
  my @acc;
  push @acc, $self->next while $self->has_next;
  return \@acc;
}

=item map()

Creates a new enumerable by applying a user-defined function to the original
enumerable.

=cut

sub map {
  my ($self, $callback) = @_;
  Data::Enumerable::Lazy->new({
    on_has_next => $self->on_has_next,
    on_next     => sub { shift; $callback->($self, @_) },
    is_finite   => $self->is_finite,
    _no_wrap    => $self->_no_wrap,
  });
}

=item grep()

grep() is a function which returns a new enumerable by applying a user-defined
filter function.

grep() might be applied to both finite and infinite enumerables. In case of an
infinitive enumerable there is an additional argument specifying max number of
lookahead steps. If an element satisfying the condition could not be found in
max_lookahead steps, an enumerable is considered to be completely iterated and
has_next() will return false.

grep() returns a new enumerable with quite special properties: has_next()
will perform a look ahead and call the original enumerable next() method
in order to find an element for which the user-defined function will return
true. next(), on the other side, returns the value that was pre-fetched
by has_next().

=cut

sub grep {
  my ($self, $callback, $max_lookahead) = @_;
  my $next;
  my $initialized = 0;
  $max_lookahead //= 0;
  $max_lookahead = 0
    if $self->is_finite;
  Data::Enumerable::Lazy->new({
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

=item resolve()

Resolves an enumerable completely. Applicable for finite enumerables only.
The method returns nothing.

=cut

sub resolve {
  my ($self) = @_;
  croak 'Only finite enumerables might be resolved. Use is_finite=1'
    unless $self->is_finite;
  $self->next() while $self->has_next;
}

=item take()

Resolves first N elements and returns the resulting list. If there are
fewer than N elements in the enumerable, the entire enumerable would be
returned as a list.

=cut

sub take {
  my ($self, $slice_size) = @_;
  my $ix = 0;
  my @acc;
  push @acc, $self->next while ($self->has_next && $ix++ < $slice_size);
  return \@acc;
}

sub take_while {
  my ($self, $callback, $max_lookahead) = @_;
  $max_lookahead //= 0;
  my $next_el;
  Data::Enumerable::Lazy->new({
    on_has_next => sub {
      my $lookahead = 0;
      my $has_next = 0;
      while ($self->has_next) {
        $next_el = $self->next;
        $lookahead++;
        return 0 if $max_lookahead > 0 && $lookahead > $max_lookahead;
        return 1 if $callback->($self, $next_el);
      }
      return 0;
    },
    on_next => sub { shift->yield($next_el) },
    is_finite => $self->is_finite,
  });
}

=item continue()

Creates a new enumerable by extending the existing one. on_next is
the only manfatory argument. on_has_next might be overriden if some
custom logic comes into play.

is_finite is inherited from the parent enumerable by default. All additional
attributes would be transparently passed to the constuctor.

=cut

sub continue {
  my ($this, $ext) = @_;
  my %ext = %$ext;
  my $on_next = delete $ext{on_next}
    or croak '`on_next` should be defined on stream continuation';
  Data::Enumerable::Lazy->new({
    on_next => sub {
      my $self = shift;
      $self->yield($on_next->($self, $this->next));
    },
    on_has_next => delete $ext->{on_has_next} // $this->on_has_next,
    is_finite   => delete $ext->{is_finite}   // $this->is_finite,
    _no_wrap    => delete $ext->{_no_wrap}    // $this->_no_wrap,
    %ext,
  });
}

# Private methods

sub yield {
  my $self = shift;
  my $val = shift;
  my $val_is_stream = $val && ref($val) eq 'Data::Enumerable::Lazy' &&
    $val->isa('Data::Enumerable::Lazy');
  if ($self->_no_wrap || $val_is_stream) {
    return $val;
  } else {
    return Data::Enumerable::Lazy->singular($val);
  }
}

# Class methods

sub empty {
  Data::Enumerable::Lazy->new({
    is_finite   => 1,
    _no_wrap    => 1,
  });
}

sub singular {
  my ($class, $val) = @_;
  my $resolved = 0;
  Data::Enumerable::Lazy->new({
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
  Data::Enumerable::Lazy->new({
    on_has_next => sub { $ix < scalar(@list) },
    on_next     => sub { shift->yield($list[$ix++]) },
    is_finite   => 1,
    _no_wrap    => 1,
  });
}

sub infinity {
  my $class = shift;
  Data::Enumerable::Lazy->new({
    on_has_next => sub { 1 },
    on_next     => sub {},
    _is_finite  => 0,
    _no_wrap    => 1,
  });
}

1;
