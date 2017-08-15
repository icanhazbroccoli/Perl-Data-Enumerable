package Data::Enumerable::Lazy;

use 5.18.2;

use strict;
use warnings;

=pod

=head1 Data::Enumerable::Lazy

=head2 About

This package is a lazy enumerable implementation for Perl5. Also known as:
(sequence) generator, stream. This library is handy for an infinitive
sequence representation (in this case a developer has to implement 2
callbacks: a quick next-element-existance check and the generator function
itself. It is also a convinient solution whenever the number of the iterations
in not known in advance (see examples section).

This package implements lazy enumerables as a mix of a generic sequence and an
iterator with a state at the same state. Every sequence has a state. The state
is defined by the internal iterator position.

Enumerables use internal buffers in order to transparently support batched step
resolution. It doesn't stop enumerables from resolving sequence elements one by
one.

  [enumerable.has_next] -> [_buffer.has_next] -> yes -> return true
                                              -> no -> result = [enumerable.on_has_next] -> return result

  [enumerable.next] -> [_buffer.has_next] -> yes -> return [_buffer.next]
                                          -> no -> result = [enumerable.next] -> [enumerable.set_buffer(result)] -> return result

A buffer is also an enumerable. This feature allows one to nest enumerables
as many times as needed.

=head1 Examples

=head4 A basic range

This example implements a range generator from $from until $to. In order to
generate this range we define 2 callbacks: C<on_has_next()> and C<on_next()>.
The first one is used as point of truth whether the sequence has any more
non-iterated elements, and the 2nd one is here to return the next element in
the sequence and the one that changes the state of the internal sequence
iterator.

  sub basic_range {
    my ($from, $to) = @_;
    $from <= $to or die '$from should be less or equal $to';
    my $current = $from;
    Data::Enumerable::Lazy->new({
      on_has_next => sub {
        return $current <= $to;
      },
      on_next => sub {
        my ($self) = @_;
        return $self->yield($current++);
      },
    });
  }

on_has_next() makes sure the current value does not exceed $to value, and
on_next() yields the next value of the sequence. Note the yield method.
An enumerable developer is expected to use this method in order to return
the next step value. This method does some internal bookkeeping and smart
caching.

Usage:

# We initialize a new range generator from 0 to 10 including.
  my $range = basic_range(0, 10);
# We check if the sequence has elements in it's tail.
  while ($range->has_next) {
    # In this very line the state of $range is being changed
    say $range->next;
  }

  is $range->has_next, 0, '$range has been iterated completely'
  is $range->next, undef, 'A fully iterated sequence returns undef on next()'

=head4 Prime numbers

Prime numbers is an infinite sequence of natural numbers. This example
implements a very basic prime number generator.

  my $prime_num_stream = Data::Enumerable::Lazy->new({
    # This is an infinite sequence
    on_has_next => sub { 1 },
    on_next => sub {
      my $self = shift;
      # We save the result of the previous step
      my $next = $self->{_prev_} // 1;
      LOOKUP: while (1) {
        $next++;
        # Check all numbers from 2 to sqrt(N)
        foreach (2..floor(sqrt($next))) {
          ($next % $_ == 0) and next LOOKUP;
        }
        last LOOKUP;
      }
      # Save the result in order to use it in the next step
      $self->{_prev_} = $next;
      # Return the result
      $self->yield($next);
    },
  });

What's remarkable regarding this specific example is that one can not simply
call C<to_list()> in order to get all elements of the sequence. The enumerable
will throw an exception claiming it's an infinitive sequence. Therefore, we
should use C<next()> in order to get elements one by one or use another handy
method C<take()> which returns first N results.

=head4 Nested enumerables

In this example we will output a numbers of a multiplication table 10x10.
What's interesting in this example is that there are 2 sequences: primary and
secondary. Primary C<on_next()> returns secondary sequence, which generates the
result of multiplication of 2 numbers.

  # A new stream based on a range from 1 to 10
  my $mult_table = Data::Enumerable::Lazy->from_list(1..10)->continue({
    on_has_next => sub {
      my ($self, $i) = @_;
      # The primary stream returns another sequence, based on range
      $self->yield(Data::Enumerable::Lazy->from_list(1..10)->continue({
        on_next => sub {
          # $_[0] is a substream self
          # $_[1] is a next substream sequence element
          $_[0]->yield( $_[1] * $i )
        },
      }));
    },
  });

Another feature which is demonstrated here is the batched result generation.
Let's iterate the sequence step by step and see what happens inside.

  $mult_table->has_next; # returns true based on the primary range, _buffer is
                         # empty
  $mult_table->next;     # returns 1, the secondary sequence is now stored as
                         # the primary enumerable buffer and 1 is being served
                         # from this buffer
  $mult_table->has_next; # returns true, resolved by the state of the buffer
  $mult_table->next;     # returns 2, moves buffer iterator forward, the
                         # primary sequence on_next() is _not_ being called
                         # this time
  $mult_table->next for (3..10); # The last iteration completes the buffer
                         # iteration cycle
  $mult_table->has_next; # returns true, but now it calls the primary
                         # on_has_next()
  $mult_table->next;     # returns 2 as the first element in the next
                         # secondary sequence (which is 1 again) multiplied by
                         # the 2nd element of the primary sequence (which is 2)
  $mult_table->to_list;  # Generates the tail of the sesquence:
                         # [4, 6, ..., 80, 90, 100]
  $mult_table->has_next; # returns false as the buffer is empty now and the
                         # primary sequence on_has_next() says there is nothing
                         # more to iterate over.

=head4 DBI paginator example

As mentioned earlier, lazy enumerables are useful when the number of the
elements in the sequence is not known in advance. So far, we were looking at
some synthetic examples, but the majority of us are not being paid for prime
number generators. Hands on some real life example. Say, we have a table and
we want to iterate over all entries in the table, and we want the data to be
retrieved in batches by 10 elements in order to reduce the number of queries.
We don't want to compute the number of steps in advance, as the number might
be inaccurate: let's assume we're paginating over some new tweets and the new
entries might be created on the flight.

  use DBI;
  my $dbh = setup_dbh(); # Some config

  my $last_id = -1;
  my $limit = 10;
  my $offset = 0;
  my $tweet_enum = Data::Enumerable::Lazy->new({
    on_has_next => sub {
      my $sth = $dbh->prepare('SELECT count(1) from Tweets where id > ?');
      $sth->execute($last_id);
      my ($cnt) = $sth->fetchrow_array;
      return int($cnt) > 0;
    },
    on_next => sub {
      my ($self) = @_;
      my $sth = $dbh->prepare('SELECT * from Tweets ORDER BY id LIMIT ? OFFSET ?');
      $sth->execute($lmit, $offset);
      $offset += $limit;
      my @tweets = $sth->fetchrow_array;
      $last_id = $tweets[-1]->{id};
      $self->yield(Data::Enumerable::Lazy->from_list(@tweets));
    },
    is_finite => 1,
  });

  while ($tweet_enum->has_next) {
    my $tweet = $tweet_enum->next;
    # do something with this tweet
  }

In this example a tweet consumer is abstracted from any DBI bookkeeping and
consumes tweet entries one by one without any prior knowledge about the table
size and might work on a rapidly growing dataset.

In order to reduce the number of queries, we query the data in batches by 10
elements max.

=head4 Redis queue consumer

  use Redis;

  my $redis = Redis->new;
  my $queue_enum = Data::Enumerable::Lazy->new({
    on_has_next => sub { 1 },
    on_next => sub {
      # Blocking right POP
      $redis->brpop();
    },
  });

  while (my $queue_item = $queue_enum->next) {
    # do something with the queue item
  }

In this example the client is blocked until there is an element available in
the queue, but it's hidden away from the clients who consume the data item by
item.

=head4 Kafka example

Kafka consumer wrapper is another example of a lazy calculation application.
Lazy enumerables are very naturally co-operated with streaming data, like
Kafka. In this example we're fetching batches of messages from Kafka topic,
grep out corrupted ones and proceed with the mesages.

  use Kafka qw($DEFAULT_MAX_BYTES);
  use Kafka::Connection;
  use Kafka::Consumer;

  my $kafka_consumer = Kafka::Consumer->new(
    Connection => Kafka::Connection->new( host => 'localhost', ),
  );

  my $partition = 0;
  my $offset = 0;
  my $kafka_enum = Data::Enumerable::Lazy->new({
    on_has_next => sub { 1 },
    on_next => sub {
      my ($self) = @_;
      # Fetch messages in batch
      my $messages = $kafka_consumer->fetch({
        'topic',
        $partition,
        $offset,
        $DEFAULT_MAX_BYTES
      });
      if ($messages) {
        # Note the grep function applied: we're filtering away corrupted messages
        $self->yield(Data::Enumerable::Lazy->from_list(@$messages))->grep(sub { $_[0]->valid });
      } else {
        # If there are no more messages, we return an empty enum, this is
        # another handy use-case for nested enums.
        $self->yield(Data::Enumerable::Lazy->empty);
      }
    },
  });

  while (my $message = $kafka_enum->next) {
    # handle the message
  }

=cut

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

=head1 Instance methods

=head2 next()

Function C<next()> is the primary interface for accessing elements of an
enumerable. It will do some internal checks and if there is no elements to be
served from an intermediate buffer, it will resolve the next step by calling
C<on_next()> callback.
Enumerables are composable: one enumerable might be based on another
enumeration. E.g.: a sequence of natural number squares is based on the
sequence of natural numbers themselves. In other words, a sequence is defined
as a tuple of another sequence and a function which would be lazily applied to
every element of this sequence.

C<next()> accepts 0 or more arguments, which would be passed to C<on_next()>
callback.

C<next()> is expected to do the heavy-lifting job in opposite to C<has_next()>,
which is supposed to be cheap and fast. This statement flips upside down
whenever C<grep()> is applied to a stream. See C<grep()> for more details.

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

=head2 has_next()

C<has_next()> is the primary entry point to get an information about the state
of an enumetable. If the method returned false, there are no more elements to be
consumed. I.e. the sequence has been iterated completely. Normally it means
the end of an iteration cycle.

Enumerables use internal buffers in order to support batched C<on_next()>
resolutions. If there are some elements left in the buffer, C<on_next()>
won't call C<on_has_next()> callback immediately. If the buffer has been
iterated completely, C<on_has_next()> would be called.

C<on_next()> should be fast on resolving the state of an enumerable as it's going
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

=head2 to_list()

This function transforms a lazy enumerable to a list. Only finite enumerables
can be transformed to a list, so the method checks if an enumetable is created
with C<is_finite=1> flag. An exception would be thrown otherwise.

=cut

sub to_list {
  my ($self) = @_;
  croak 'Only finite enumerables might be converted to list. Use is_finite=1'
    unless $self->is_finite;
  my @acc;
  push @acc, $self->next while $self->has_next;
  return \@acc;
}

=head2 map($callback)

Creates a new enumerable by applying a user-defined function to the original
enumerable. Works the same way as perl map {} function but it's lazy.

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

=head2 reduce($acc, $callback)

Resolves the enumerable and returns the resulting state of the accumulator $acc
provided as the 1st argument. C<$callback> should always return the new state of
C<$acc>.

C<reduce()> is defined for finite enumerables only.

=cut

sub reduce {
  my ($self, $acc, $callback) = @_;
  croak 'Only finite enumerables might be reduced. Use is_finite=1'
    unless $self->is_finite;
  ($acc = $callback->($self, $acc, $self->next)) while $self->has_next;
  return $acc;
}

=head2 grep($callback, $max_lookahead)

C<grep()> is a function which returns a new enumerable by applying a
user-defined filter function.

C<grep()> might be applied to both finite and infinite enumerables. In case of
an infinitive enumerable there is an additional argument specifying max number
of lookahead steps. If an element satisfying the condition could not be found in
C<max_lookahead> steps, an enumerable is considered to be completely iterated
and C<has_next()> will return false.

C<grep()> returns a new enumerable with quite special properties: C<has_next()>
will perform a look ahead and call the original enumerable C<next()> method
in order to find an element for which the user-defined function will return
true. C<next()>, on the other side, returns the value that was pre-fetched
by C<has_next()>.

=cut

sub grep {
  my ($self, $callback, $max_lookahead) = @_;
  my $next;
  my $initialized = 0;
  $max_lookahead //= 0;
  $max_lookahead = 0
    if $self->is_finite;
  my $prev_has_next;
  Data::Enumerable::Lazy->new({
    on_has_next => sub {
      defined $prev_has_next
        and return $prev_has_next;
      my $ix = 0;
      $initialized = 1;
      undef $next;
      while ($self->has_next) {
        if ($max_lookahead > 0) {
          $ix > $max_lookahead
            and do {
              carp sprintf 'Max lookahead steps cnt reached. Bailing out';
              return $prev_has_next = 0;
            };
        }
        $next = $self->next;
        $callback->($next) and last;
        undef $next;
        $ix++;
      }
      return $prev_has_next = (defined $next);
    },
    on_next => sub {
      my $self = shift;
      $initialized or $self->has_next;
      undef $prev_has_next;
      $self->yield($next);
    },
    is_finite => $self->is_finite,
    _no_wrap => $self->_no_wrap,
  });
}

=head2 resolve()

Resolves an enumerable completely. Applicable for finite enumerables only.
The method returns nothing.

=cut

sub resolve {
  my ($self) = @_;
  croak 'Only finite enumerables might be resolved. Use is_finite=1'
    unless $self->is_finite;
  $self->next() while $self->has_next;
}

=head2 take($N_elements)

Resolves first $N_elements and returns the resulting list. If there are
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

=head2 take_while($callback, $max_lookahead)

Iterates over an enumerable until $callback returns false or $max_lookahead
number of lookahead steps has been made.

$callback takes 2 arguments: $self and a candidate element. This is a lookahead
method so the heavylifting job would be done during C<on_next()> method call
whereas C<next()> simply returns a pre-cached value.

C<$max_lookahead> is an integer, defaults to 0 meaning no limit.

=cut

sub take_while {
  my ($self, $callback, $max_lookahead) = @_;
  $max_lookahead //= 0;
  my $next_el;
  my $prev_has_next;
  my $initialized = 0;
  Data::Enumerable::Lazy->new({
    on_has_next => sub {
      $initialized = 1;
      defined $prev_has_next
        and return $prev_has_next;
      my $lookahead = 0;
      while ($self->has_next) {
        $next_el = $self->next;
        $lookahead++;
        return $prev_has_next = 0 if $max_lookahead > 0 && $lookahead > $max_lookahead;
        return $prev_has_next = 1 if $callback->($self, $next_el);
      }
      return $prev_has_next = 0;
    },
    on_next => sub {
      $initialized or $self->has_next();
      undef $prev_has_next;
      shift->yield($next_el);
    },
    is_finite => $self->is_finite,
  });
}

=head2 continue($ext = %{ on_next => sub {}, ... })

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
    _no_wrap    => delete $ext->{_no_wrap}    // 0,
    %ext,
  });
}

=head2 yield($result)

This method is supposed to be called from C<on_next> callback only. This is
the only valid result for an Enumerable to return the next step result.
Effectively, it ensures the returned result conforms to the required interface
and is wrapped in a lazy wrapper if needed.

=cut

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

=head1 Class methods

=head2 empty()

Returns an empty enumerable. Effectively it means an equivalent of an empty
array. C<has_next()> will return false and C<next()> will return undef. Useful
whenever a C<on_next()> step wants to return an empty resultset.

=cut

sub empty {
  Data::Enumerable::Lazy->new({
    is_finite   => 1,
    _no_wrap    => 1,
  });
}

=head2 singular($val)

Returns an enumerable with a single element $val. Actively used as an internal
data container.

=cut

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

=head2 from_list(@list)

Returns a new enumerable instantiated from a list. The easiest way to
initialize an enumerable. In fact, all elements are already resolved
so this method sets C<is_finite=1> by default.

=cut

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

=head2 cycle()

Creates an infinitive enumerable by cycling the original list. E.g. if the
original list is [1, 2, 3], C<cycle()> will generate an infinitive sequences
like: 1, 2, 3, 1, 2, 3, 1, ...

=cut

sub cycle {
  my $class = shift;
  my @list = @_;
  my $ix = 0;
  my $max_ix = scalar(@list) - 1;
  Data::Enumerable::Lazy->new({
    on_has_next => sub { 1 },
    on_next     => sub {
      $ix = $ix > $max_ix ? 0 : $ix;
      shift->yield($list[$ix++])
    },
    is_finite   => 0,
    _no_wrap    => 1,
  });
}

=head2 infinity()

Returns a new infinite enumerable. C<has_next()> always returns true whereas
C<next()> returns undef all the time. Useful as an extension basis for infinite
sequences.

=cut

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

__END__
