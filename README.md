# Data::Enumerable::Lazy

## About

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

```
  [enumerable.has_next] -> [_buffer.has_next] -> yes -> return true
                                              -> no -> result = [enumerable.on_has_next] -> return result

  [enumerable.next] -> [_buffer.has_next] -> yes -> return [_buffer.next]
                                          -> no -> result = [enumerable.next] -> [enumerable.set_buffer(result)] -> return result

```

A buffer is also an enumerable. This feature allows one to nest enumerables
as many times as needed.

## Examples

#### A basic range

This example implements a range generator from $from until $to. In order to
generate this range we define 2 callbacks: `on_has_next()` and `on_next()`.
The first one is used as point of truth whether the sequence has any more
non-iterated elements, and the 2nd one is here to return the next element in
the sequence and the one that changes the state of the internal sequence
iterator.

```perl
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
```

`on_has_next()` makes sure the current value does not exceed $to value, and
`on_next()` yields the next value of the sequence. Note the yield method.
An enumerable developer is expected to use this method in order to return
the next step value. This method does some internal bookkeeping and smart
caching.

Usage:

```perl
  # We initialize a new range generator from 0 to 10 including.
  my $range = basic_range(0, 10);
  # We check if the sequence has elements in it's tail.
  while ($range->has_next) {
    # In this very line the state of $range is being changed
    say $range->next;
  }

  is $range->has_next, 0, '$range has been iterated completely'
  is $range->next, undef, 'A fully iterated sequence returns undef on next()'
```

#### Prime numbers

Prime numbers is an infinite sequence of natural numbers. This example
implements a very basic prime number generator.

```perl
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
```

What's remarkable regarding this specific example is that one can not simply
call `to_list()` in order to get all elements of the sequence. The enumerable
will throw an exception claiming it's an infinitive sequence. Therefore, we
should use `next()` in order to get elements one by one or use another handy
method `take()` which returns first N results.

#### Nested enumerables

In this example we will output a numbers of a multiplication table 10x10.
What's interesting in this example is that there are 2 sequences: primary and
secondary. Primary `on_next()` returns secondary sequence, which generates the
result of multiplication of 2 numbers.

```perl
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
```

Another feature which is demonstrated here is the batched result generation.
Let's iterate the sequence step by step and see what happens inside.

```perl
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
```

#### DBI paginator example

As mentioned earlier, lazy enumerables are useful when the number of the
elements in the sequence is not known in advance. So far, we were looking at
some synthetic examples, but the majority of us are not being paid for prime
number generators. Hands on some real life example. Say, we have a table and
we want to iterate over all entries in the table, and we want the data to be
retrieved in batches by 10 elements in order to reduce the number of queries.
We don't want to compute the number of steps in advance, as the number might
be inaccurate: let's assume we're paginating over some new tweets and the new
entries might be created on the flight.

```perl
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
```

In this example a tweet consumer is abstracted from any DBI bookkeeping and
consumes tweet entries one by one without any prior knowledge about the table
size and might work on a rapidly growing dataset.

In order to reduce the number of queries, we query the data in batches by 10
elements max.

#### Redis queue consumer

```perl
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
```

In this example the client is blocked until there is an element available in
the queue, but it's hidden away from the clients who consume the data item by
item.

#### Kafka example

Kafka consumer wrapper is another example of a lazy calculation application.
Lazy enumerables are very naturally co-operated with streaming data, like
Kafka. In this example we're fetching batches of messages from Kafka topic,
grep out corrupted ones and proceed with the mesages.

```perl
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
```

## Author

Oleg S <me@whitebox.io>
