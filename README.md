Data::Enumerable::Lazy(U3s)er Contributed Perl DocumentatDiaotna::Enumerable::Lazy(3)



NNAAMMEE
       Data::Enumerable::Lazy

SSYYNNOOPPSSIISS
       A basic lazy range implementation picking even numbers only:
         my ($from, $to) = (0, 10);
         my $current = $from;
         my $stream = Data::Enumerable::Lazy->new({
           on_has_next => sub { $current <= $to          },
           on_next     => sub { shift->yield($current++) },
         })->grep(sub{ shift % 2 == 0 });
         $stream->_t_o___l_i_s_t_(_); # generates: [0, 2, 4, 6, 8, 10]

   DDEESSCCRRIIPPTTIIOONN
       This library is another one implementation of a lazy generator +
       enumerable for Perl5. It might be handy if the elements of the
       collection are resolved on the flight and the iteration itself should
       be hidden from the end users.

       The enumerables are single-pass composable calculation units. What it
       means: An enumerable is stateful, once it reached the end of the
       sequence, it will not rewind to the beginning unless explicitly
       specified.  Enumerables are composable: one enumerable might be an
       extension of another by applying some additional logic. An enumerable
       resolves elements one-by-one, and the result might be another
       enumerable, which might produce another enumerables etc. In this case
       enumerables become recursive, but for the end user it will still look
       like a flat collection. This is one of the main features of this
       library.

         [enumerable.has_next] -> [_buffer.has_next] -> yes -> return true
                                                     -> no -> result = [enumerable.on_has_next] -> return result

         [enumerable.next] -> [_buffer.has_next] -> yes -> return [_buffer.next]
                                                 -> no -> result = [enumerable.next] -> [enumerable.set_buffer(result)] -> return result

EEXXAAMMPPLLEESS
   AA bbaassiicc rraannggee
       This example implements a range generator from $from until $to. In
       order to generate this range we define 2 callbacks: "on_has_next()" and
       "on_next()".  The first one is used as point of truth whether the
       sequence has any more non-iterated elements, and the 2nd one is here to
       return the next element in the sequence and the one that changes the
       state of the internal sequence iterator.

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

       _o_n___h_a_s___n_e_x_t_(_) makes sure the current value does not exceed $to value,
       and _o_n___n_e_x_t_(_) yields the next value of the sequence. Note the yield
       method.  An enumerable developer is expected to use this method in
       order to return the next step value. This method does some internal
       bookkeeping and smart caching.

       Usage:

       # We initialize a new range generator from 0 to 10 including.
         my $range = basic_range(0, 10); # We check if the sequence has
       elements in it's tail.
         while ($range->has_next) {
           # In this very line the state of $range is being changed
           say $range->next;
         }

         is $range->has_next, 0, '$range has been iterated completely'
         is $range->next, undef, 'A fully iterated sequence returns undef on next()'

   PPrriimmee nnuummbbeerrss
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

       What's remarkable regarding this specific example is that one can not
       simply call "to_list()" in order to get all elements of the sequence.
       The enumerable will throw an exception claiming it's an infinitive
       sequence. Therefore, we should use "next()" in order to get elements
       one by one or use another handy method "take()" which returns first N
       results.

   NNeesstteedd eennuummeerraabblleess
       In this example we will output a numbers of a multiplication table
       10x10.  What's interesting in this example is that there are 2
       sequences: primary and secondary. Primary "on_next()" returns secondary
       sequence, which generates the result of multiplication of 2 numbers.

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

       Another feature which is demonstrated here is the batched result
       generation.  Let's iterate the sequence step by step and see what
       happens inside.

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

   DDBBII ppaaggiinnaattoorr eexxaammppllee
       As mentioned earlier, lazy enumerables are useful when the number of
       the elements in the sequence is not known in advance. So far, we were
       looking at some synthetic examples, but the majority of us are not
       being paid for prime number generators. Hands on some real life
       example. Say, we have a table and we want to iterate over all entries
       in the table, and we want the data to be retrieved in batches by 10
       elements in order to reduce the number of queries.  We don't want to
       compute the number of steps in advance, as the number might be
       inaccurate: let's assume we're paginating over some new tweets and the
       new entries might be created on the flight.

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

       In this example a tweet consumer is abstracted from any DBI bookkeeping
       and consumes tweet entries one by one without any prior knowledge about
       the table size and might work on a rapidly growing dataset.

       In order to reduce the number of queries, we query the data in batches
       by 10 elements max.

   RReeddiiss qquueeuuee ccoonnssuummeerr
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

       In this example the client is blocked until there is an element
       available in the queue, but it's hidden away from the clients who
       consume the data item by item.

   KKaaffkkaa eexxaammppllee
       Kafka consumer wrapper is another example of a lazy calculation
       application.  Lazy enumerables are very naturally co-operated with
       streaming data, like Kafka. In this example we're fetching batches of
       messages from Kafka topic, grep out corrupted ones and proceed with the
       mesages.

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

OOPPTTIIOONNSS
   oonn__nneexxtt(($$sseellff,, $$eelleemmeenntt)) :::: CCooddeeRReeff -->> DDaattaa::::EEnnuummeerraabbllee::::LLaazzyy || AAnnyy
       "on_next" is a code ref, a callback which is being called every time
       the generator is in demand for a new bit of data. Enumerable buffers up
       the result of the previous calculation and if there are no more
       elements left in the buffer, "on_next()" would be called.

       $element is defined when the current collection is a contuniation of
       another enumerable. I.e.:
         my $enum = Data::Enumerable::Lazy->from_list(1, 2, 3);
         my $enum2 = $enum->continue({
           on_next => sub { my ($self, $i) = @_; $self->yield($i * $i) }
         });
         $enum2->to_list; # generates 1, 4, 9 In this case $i would be defined
       and it comes from the original enumerable.

       The function is supposed to return an enumerable, in this case it would
       be kept as the buffer object. If this function method returns any other
       value, it would be wrapped in a "Data::Enumerable::Lazy-"_s_i_n_g_u_l_a_r_(_)>.
       There is a way to prevent an enumerable from wrapping your return value
       in an enum and keeping it in a raw state by providing "_no_wrap=1".

   oonn__hhaass__nneexxtt(($$sseellff)) :::: CCooddeeRReeff -->> BBooooll
       "on_has_next" is a code ref, a callback to be called whenever the
       enumerable is about to resolve "has_next()" method call. Similar to
       "on_next()" call, this one is also triggered whenever an enumerable
       runs out of buffered elements. The function shoiuld return boolean.

       A method that returns 1 all the time is the way to initialize an
       infinite enumerable (see "infinity()"). If it returns 0 no matter what,
       it would be an empty enumerable (see "empty()"). Normally you want to
       stay somewhere in the middle and implement some state check login in
       there.

   iiss__ffiinniittee :::: BBooooll
       A boolean flag indicating whether an enumerable is finite or not. By
       default enumerables are treated as infinite, which means some functions
       will throw an exception, like: "to_list()" or "resolve()".

       Make sure to not mark an enumerable as finite and to call finite-size
       defined methods, in this case it will create an infinite loop on the
       resolution.

   __bbuuffff :::: DDaattaa::::EEnnuummeerraabbllee::::LLaazzyy
       The buffer attribute. Could be modified only if the starting state has
       to be restored. Normally one doesn't modify this attribure by default.

   __nnoo__wwrraapp :::: BBooooll
       A boolean flag indicating whether "yield()" has to wrap the return
       value in another enumerable. True by default.

IINNSSTTAANNCCEE MMEETTHHOODDSS
   _n_e_x_t_(_)
       Function "next()" is the primary interface for accessing elements of an
       enumerable. It will do some internal checks and if there is no elements
       to be served from an intermediate buffer, it will resolve the next step
       by calling "on_next()" callback.  Enumerables are composable: one
       enumerable might be based on another enumeration. E.g.: a sequence of
       natural number squares is based on the sequence of natural numbers
       themselves. In other words, a sequence is defined as a tuple of another
       sequence and a function which would be lazily applied to every element
       of this sequence.

       "next()" accepts 0 or more arguments, which would be passed to
       "on_next()" callback.

       "next()" is expected to do the heavy-lifting job in opposite to
       "has_next()", which is supposed to be cheap and fast. This statement
       flips upside down whenever "grep()" is applied to a stream. See
       "grep()" for more details.

   _h_a_s___n_e_x_t_(_)
       "has_next()" is the primary entry point to get an information about the
       state of an enumetable. If the method returned false, there are no more
       elements to be consumed. I.e. the sequence has been iterated
       completely. Normally it means the end of an iteration cycle.

       Enumerables use internal buffers in order to support batched
       "on_next()" resolutions. If there are some elements left in the buffer,
       "on_next()" won't call "on_has_next()" callback immediately. If the
       buffer has been iterated completely, "on_has_next()" would be called.

       "on_next()" should be fast on resolving the state of an enumerable as
       it's going to be used for a condition state check.

   _t_o___l_i_s_t_(_)
       This function transforms a lazy enumerable to a list. Only finite
       enumerables can be transformed to a list, so the method checks if an
       enumetable is created with "is_finite=1" flag. An exception would be
       thrown otherwise.

   mmaapp(($$ccaallllbbaacckk))
       Creates a new enumerable by applying a user-defined function to the
       original enumerable. Works the same way as perl map {} function but
       it's lazy.

   rreedduuccee(($$aacccc,, $$ccaallllbbaacckk))
       Resolves the enumerable and returns the resulting state of the
       accumulator $acc provided as the 1st argument. $callback should always
       return the new state of $acc.

       "reduce()" is defined for finite enumerables only.

   ggrreepp(($$ccaallllbbaacckk,, $$mmaaxx__llooookkaahheeaadd))
       "grep()" is a function which returns a new enumerable by applying a
       user-defined filter function.

       "grep()" might be applied to both finite and infinite enumerables. In
       case of an infinitive enumerable there is an additional argument
       specifying max number of lookahead steps. If an element satisfying the
       condition could not be found in "max_lookahead" steps, an enumerable is
       considered to be completely iterated and "has_next()" will return
       false.

       "grep()" returns a new enumerable with quite special properties:
       "has_next()" will perform a look ahead and call the original enumerable
       "next()" method in order to find an element for which the user-defined
       function will return true. "next()", on the other side, returns the
       value that was pre-fetched by "has_next()".

   _r_e_s_o_l_v_e_(_)
       Resolves an enumerable completely. Applicable for finite enumerables
       only.  The method returns nothing.

   ttaakkee(($$NN__eelleemmeennttss))
       Resolves first $N_elements and returns the resulting list. If there are
       fewer than N elements in the enumerable, the entire enumerable would be
       returned as a list.

   ttaakkee__wwhhiillee(($$ccaallllbbaacckk))
       This function takes elements until it meets the first one that does not
       satisfy the conditional callback.  The callback takes only 1 argument:
       an element. It should return true if the element should be taken. Once
       it returned false, the stream is over.

   ccoonnttiinnuuee(($$eexxtt == %%{{ oonn__nneexxtt ==>> ssuubb {{}},, ...... }}))
       Creates a new enumerable by extending the existing one. on_next is the
       only manfatory argument. on_has_next might be overriden if some custom
       logic comes into play.

       is_finite is inherited from the parent enumerable by default. All
       additional attributes would be transparently passed to the constuctor.

   yyiieelldd(($$rreessuulltt))
       This method is supposed to be called from "on_next" callback only. This
       is the only valid result for an Enumerable to return the next step
       result.  Effectively, it ensures the returned result conforms to the
       required interface and is wrapped in a lazy wrapper if needed.

CCLLAASSSS MMEETTHHOODDSS
   _e_m_p_t_y_(_)
       Returns an empty enumerable. Effectively it means an equivalent of an
       empty array. "has_next()" will return false and "next()" will return
       undef. Useful whenever a "on_next()" step wants to return an empty
       resultset.

   ssiinngguullaarr(($$vvaall))
       Returns an enumerable with a single element $val. Actively used as an
       internal data container.

   ffrroomm__lliisstt((@@lliisstt))
       Returns a new enumerable instantiated from a list. The easiest way to
       initialize an enumerable. In fact, all elements are already resolved so
       this method sets "is_finite=1" by default.

   _c_y_c_l_e_(_)
       Creates an infinitive enumerable by cycling the original list. E.g. if
       the original list is [1, 2, 3], "cycle()" will generate an infinitive
       sequences like: 1, 2, 3, 1, 2, 3, 1, ...

   _i_n_f_i_n_i_t_y_(_)
       Returns a new infinite enumerable. "has_next()" always returns true
       whereas "next()" returns undef all the time. Useful as an extension
       basis for infinite sequences.

   mmeerrggee(($$ssttrreeaamm11 [[,, $$ssttrreeaamm22 [[,, $$ssttrreeaamm33 [[,, ......]]]]]]))
       This function merges one or more streams together by fan-outing
       "next()" method call among the non-empty streams.  Returns a new
       enumerable instance, which:
         * Has next elements as far as at least one of the streams does.
         * Returns next element py picking it one-by-one from the streams.
         * Is finite if and only if all the streams are finite.  If one of the
       streams is over, it would be taken into account and "next()" will
       continue choosing from non-empty ones.

AAUUTTHHOORR
       Oleg S <me@whitebox.io>

SSEEEE AALLSSOO
   LLiibbrraarryy GGiittHHuubb ppaaggee::
       <https://github.com/icanhazbroccoli/Perl-Data-Enumerable-Lazy>

   AAlltteerrnnaattiivvee iimmpplleemmeennttaattiioonnss::
       <https://metacpan.org/pod/List::Generator>
       <https://metacpan.org/pod/Generator::Object>
       <https://metacpan.org/pod/Iterator>

CCOOPPYYRRIIGGHHTT AANNDD LLIICCEENNSSEE
       Copyright 2017 Oleg S <me@whitebox.io>

       Copying and distribution of this file, with or without modification,
       are permitted in any medium without royalty provided the copyright
       notice and this notice are preserved. This file is offered as-is,
       without any warranty.



perl v5.18.2                      2017-08-24         Data::Enumerable::Lazy(3)
