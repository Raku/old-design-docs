=encoding utf8

=head1 TITLE

Synopsis 17: Concurrency 

=head1 AUTHORS

    Jonathan Worthington <jnthn@jnthn.net>
    Elizabeth Mattijsen <liz@dijkmat.nl>

=head1 VERSION

    Created: 3 Nov 2013

    Last Modified: 16 Apr 2014
    Version: 16

This synopsis is based around the concurrency primitives and tools currently
being implemented in Rakudo on MoarVM and the JVM.  It covers both things
that are already implemented today, in addition to things expected to be
implemented in the near future (where "near" means O(months)).

=head1 Design Philosophy

=head2 Focus on composability

Perl 6 generally prefers constructs that compose well, enabling large problems
to be solved by putting together solutions for lots of smaller problems. This
also helps make it easier to extend and refactor code.

Many common language features related to parallel and asynchronous programming
lack composability. For example:

=over

=item *

Locks do not compose, since two independently correct operations using
locks may deadlock when performed together.

=item *

Callback-centric approaches tend to compose badly, with chains of
asynchronous operations typically leading to deeply nested callbacks. This
essentially is just leaving the programmer to do a CPS transform of their own
logical view of the program by hand.

=item *

Directly spawning threads on a per-component basis tends to compose
badly, as when a dozen such components are used together the result is a high
number of threads with no ability to centrally schedule or handle errors.

=back

In Perl 6, concurrency features aimed at typical language users should have
good composability properties, both with themselves and also with other
language features.

=head2 Boundaries between synchronous and asynchronous should be explicit

Asynchrony happens when we initiate an operation, then continue running our
own idea of "next thing" without waiting for the operation to complete. This
differs from synchronous programming, where calling a sub or method causes the
caller to wait for a result for continuing.

The vast majority of programmers are much more comfortable with synchrony, as
in many senses it's the "normal thing". As soon as we have things taking place
asynchronously, there is a need to coordinate the work, and doing so tends to
be domain specific. Therefore, placing the programmer in an asynchronous
situation when they didn't ask for it is likely to lead to confusion and bugs.
We should try to make places where asynchrony happens clear.

It's also worthwhile trying to make it easy to keep asynchronous things flowing
asynchronously. While synchronous code is pull-y (for example, eating its way
through iterable things, blocking for results), asynchronous code is push-y
(results get pushed to things that know what to do next).

Places where we go from synchronous to asynchronous, or from asynchronous to
synchronous, are higher risk areas for bugs and potential bottlenecks. Thus,
Perl 6 should try to provide features that help minimize the need to make such
transitions.

=head2 Implicit parallelism is OK

Parallelism is primarily about taking something we could do serially and using
multiple CPU cores in order to get to a result more quickly. This leads to a
very nice property: a parallel solution to a problem should give the same
answer as a serial solution. 

While under the hood there is asynchrony and the inherent coordination it
requires, on the outside a problem solved using parallel programming is still,
when taken as a whole, a single, synchronous operation.

Elsewhere in the specification, Perl 6 provides several features that allow
the programmer to indicate that parallelizing an operation will produce the
same result as evaluating it serially:

=over

=item *

Hyper operators (L<S03/Hyper operators>) express that parallel operator
application is safe.

=item *

Junctions (L<S09/Junctions>) may auto-thread in parallel.

=item *

Feeds (L<S06/Feed operators>) form pipelines and express that the stages
may be executed in parallel in a producer-consumer style relationship (though
each stage is in itself not parallelized).

=item *

C<hyper> and C<race> list operators (L<S02/The hyper operator>) express
that iteration may be done in parallel; this is a generalization of hyper
operators.

=back

=head2 Make the hard things possible

The easy things should be easy, and able to be built out of primitives that
compose nicely. However, such things have to be built out of what VMs and
operating systems provide: threads, atomic instructions (such as CAS), and
concurrency control constructs such as mutexes and semaphores. Perl 6 is meant
to last for decades, and the coming decades will doubtless bring new ways do
do parallel and asynchronous programming that we do not have today. They will
still, however, almost certainly need to be built out of what is available.

Thus, the primitive things should be provided for those who need to work on
such hard things. Perl 6 should not hide the existence of OS-level threads, or
fail to provide access to lower level concurrency control constructs. However,
they should be clearly documented as I<not> the way to solve the majority of
problems.

=head1 Schedulers

Schedulers lie at the heart of all concurrency in Perl 6. While most users are
unlikely to immediately encounter schedulers when starting to use Perl 6's
concurrency features, many of them are implemented in terms of it. Thus, they
will be described first here to avoid lots of forward references.

A scheduler is something that does the C<Scheduler> role. Its responsibility
is taking code objects representing tasks that need to be performed and making
sure they get run, as well as handling any time-related operations (such as,
"run this code every second").

The current default scheduler is available as C<$*SCHEDULER>. If no such
dynamic variable has been declared, then C<$PROCESS::SCHEDULER> is used. This
defaults to an instance of C<ThreadPoolScheduler>, which maintains a pool of
threads and distributes scheduled work amongst them. Since the scheduler is
dynamically scoped, this means that test scheduler modules can be developed
that poke a C<$*SCHEDULER> into C<EXPORT>, and then provide the test writer
with control over time.

The C<cue> method takes a C<Callable> object and schedules it.

    $*SCHEDULER.cue: { say "Golly, I got scheduled!" }

Various options may be supplied as named arguments.  (All references to time
are taken to be in seconds, which may be fractional.)  You may schedule an
event to fire off after some number of seconds:

    $*SCHEDULER.cue: in=>10, { say "10s later" }

or at a given absolute time, specified as an C<Instant>:

    $*SCHEDULER.cue: at=>$instant, { say "at $instant" }

If a scheduled item dies, the scheduler will catch this exception and pass it
to a C<handle_uncaught> method, a default implementation of which is provided
by the C<Scheduler> role. This by default will report the exception and cause
the entire application to terminate. However, it is possible to replace this:

    $*SCHEDULER.uncaught_handler = sub ($exception) {
        $logger.log_error($exception);
    }

For more fine-grained handling, it is possible to schedule code along with a
code object to be invoked with the thrown exception if it dies:

    $*SCHEDULER.cue:
        { upload_progress($stuff) },
        quit => -> $ex { warn "Could not upload latest progress" }

Use C<:every> to schedule a task to run at a fixed interval, possibly
with a delay before the first scheduling.

    # Every second, from now
    $*SCHEDULER.cue: :every(1), { say "Oh wow, a kangaroo!" };
    
    # Every 0.5s, but don't start for 2s.
    $*SCHEDULER.cue: { say "Kenya believe it?" }, :every(0.5), :in(2);

Since this will cause the given to be executed for the given interval ad
infinitum, there are two ways to make sure the scheduling of the task is
halted at a future time.  The first is provided by specifying the C<:limit>
parameter in the .cue:

    # Every second, from now, but only 42 times
    $*SCHEDULER.cue: :every(1), :limit(42), { say "Oh wow, a kangaroo!" };

The second is by specifying a variable that will be checked at the end of
each interval.  The task will be stopped as soon as it has a True value.
You can do this with the C<:stop> parameter.

    # Every second, from now, until stopped
    my $stop;
    $*SCHEDULER.cue: :every(1), :$stop, { say "Oh wow, a kangaroo!" };
    sleep 10;
    $stop = True;  # task stopped after 10 seconds

Schedulers also provide counts of the number of operations in various states:

    say $*SCHEDULER.loads;

This returns, in order, the number of cues that are not yet runnable due to
delays, the number of cues that are runnable but not yet assigned to a thread,
and the number of cues that are now assigned to a thread (and presumably running).
[Conjecture: perhaps these should be separate methods.]

Schedulers may optionally provide further introspection in order to support
tools such as debuggers.

There is also a C<CurrentThreadScheduler>, which always schedules things on
the current thread. It provides the same methods, just no concurrency, and
any exceptions are thrown immediately. This is mostly useful for forcing
synchrony in places that default to asynchrony.  (Note that C<.loads> can never
return anything but 0 for the currently running cues, since they're waiting
on the current thread to stop scheduling first!)

=head1 Promises

A C<Promise> is a synchronization primitive for an asynchronous piece of work
that will produce a single result (thus keeping the promise) or fail in some
way (thus breaking the promise).

The simplest way to use a C<Promise> is to create one:

    my $promise = Promise.new;

And then later C<keep> it:

    $promise.keep(42);

Or C<break> it:

    $promise.break(X::Some::Problem.new);       # With exception
    $promise.break("I just couldn't do it");    # With message

The current status of a C<Promise> is available through the C<status> method,
which returns an element from the C<PromiseStatus> enumeration.

    enum PromiseStatus (:Planned(0), :Kept(1), :Broken(2));

The result itself can be obtained by calling C<result>. If the C<Promise> was
already kept, the result is immediately returned. If the C<Promise> was broken
then the exception that it was broken with is thrown. If the C<Promise> is not
yet kept or broken, then the caller will block until this happens.

A C<Promise> will boolify to whether the C<Promise> is already kept or broken.
There is also an C<excuse> method for extracting the exception from a C<Broken>
C<Promise> rather than having it thrown.

    if $promise {
        if $promise.status == Kept {
            say "Kept, result = " ~ $promise.result;
        }
        else {
            say "Broken because " ~ $promise.excuse;
        }
    }
    else {
        say "Still working!";
    }

You can also simply use a switch:

    given $promise.status {
        when Planned { say "Still working!" }
        when Kept    { say "Kept, result = ", $promise.result }
        when Broken  { say "Broken because ", $promise.excuse }
    }

There are various convenient "factory" methods on C<Promise>. The most common
is C<start>.

    my $p = Promise.start(&do_hard_calculation);

This creates a C<Promise> that runs the supplied code, and calls C<keep> with
its result. If the code throws an exception, then C<break> is called with the
C<Exception>. Most of the time, however, the above is simply written as:

    my $p = start {
        # code here
    }

Which is implemented by calling C<Promise.start>.

There is also a method to create a C<Promise> that is kept after a number of
seconds, or at a specific time:

    my $kept_in_10s      = Promise.in(10);
    my $kept_in_duration = Promise.in($duration);
    my $kept_at_instant  = Promise.at($instant);

The C<result> is always C<True> and such a C<Promise> can never be broken. It
is mostly useful for combining with other promises.

There are also a couple of C<Promise> combinators. The C<anyof> combinator
creates a C<Promise> that is kept whenever any of the specified C<Promise>s
are kept. If the first promise to produce a result is instead broken, then
the resulting C<Promise> is also broken. The excuse is passed along. When the
C<Promise> is kept, it has a C<True> result.

    my $calc     = start { ... }
    my $timeout  = Promise.in(10);
    my $timecalc = Promise.anyof($calc, $timeout);

There is also an C<allof> combinator, which creates a C<Promise> that will be
kept when all of the specified C<Promise>s are kept, or broken if any of them
are broken.

[Conjecture: there should be infix operators for these resembling the junctionals.]

The C<then> method on a C<Promise> is used to request that a certain piece of
code should be run, receiving the C<Promise> as an argument, when the
C<Promise> is kept or broken. If the C<Promise> is already kept or broken,
the code is scheduled immediately. It is possible to call C<then> more than
once, and each time it returns a C<Promise> representing the completion of
both the original C<Promise> as well as the code specified in C<then>.

    my $feedback_promise = $download_promise.then(-> $res {
        given $res.status {
            when Kept   { say "File $res.result().name() download" }
            when Broken { say "FAIL: $res.excuse()"                 }
        }
    });

[Conjecture: this needs better syntax to separate the "then" policies from the "else"
policies (and from "catch" policies?), and to avoid a bunch of switch boilerplate.
We already know the givens here...]

One risk when working with C<Promise> is that another piece of code will
sneak in and keep or break a C<Promise> it should not.  The notion of
a promise is user-facing.  To instead represent the promise from the
viewpoint of the promiser, the various built-in C<Promise> factory methods
and combinators use C<Promise::Vow> objects to represent that internal
resolve to fulfill the promise.  ("I have vowed to keep my promise
to you.")  The C<vow> method on a C<Promise> returns an object with C<keep>
and C<break> methods. It can only be called once during a C<Promise> object's
lifetime. Since C<keep> and C<break> on the C<Promise> itself just delegate
to C<self.vow.keep(...)> or C<self.vow.break(...)>, obtaining the vow
before letting the C<Promise> escape to the outside world is a way to take
ownership of the right to keep or break it. For example, here is how the
C<Promise.in> factory is implemented:

    method in(Promise:U: $seconds, :$scheduler = $*SCHEDULER) {
        my $p = Promise.new(:$scheduler);
        my $v = $p.vow;
        $scheduler.cue: { $v.keep(True) }, :in($seconds);
        $p;
    }

The C<await> function is used to wait for one or more C<Promise>s to produce a
result.

    my ($a, $b) = await $p1, $p2;

This simply calls C<result> on each of the C<Promise>s, so any exception will
be thrown.

=head1 Channels

A C<Channel> is essentially a concurrent queue. One or more threads can put
values into the C<Channel> using C<send>:

    my $c = Channel.new;
    $c.send($msg);

Meanwhile, others can C<receive> them:

    my $msg = $c.receive;

Channels are ideal for producer/consumer scenarios, and since there can be
many senders and many receivers, they adapt well to scaling certain pipeline
stages out over multiple workers also. [Conjectural: The two feed operators
C<< ==> >> and C<< <== >> are implemented using Channel to connect each of
the stages.]

A C<Channel> may be "forever", but it is possible to close it to further
sends by telling it to C<close>:

    $c.close();

Trying to C<send> any further messages on a closed channel will throw the
C<X::Channel::SendOnDone> exception. Closing a channel has no effect on the
receiving end until all sent values have been received. At that point, any
further calls to receive will throw C<X::Channel::ReceiveOnDone>. The
C<done> method returns a C<Promise> that is kept when a sender has
called C<close> and all sent messages have been received.  Note that multiple
calls to a channel return the same promise, not a new one.

While C<receive> blocks until it can read, C<poll> takes a message from the
channel if one is there or immediately returns C<Nil> if nothing is there.

There is also a C<winner> statement [keywords still negotiable]:

    winner * {
        more $c1 { say "First channel got a value" }
        more $c2 { say "Second channel got a value" }
    }

That will invoke the closure associated with the first channel that
receives a value.

It's possible to add a timer using the keyword C<wait> followed
by the number of seconds to wait (which may be fractional).  As a
degenerate case, in order to avoid blocking at all you may use a
C<wait 0>.  The timeout is always checked last, to guarantee that
the other entries are all tried at least once before timing out.

    my $gotone = winner * {
        more $c1 { say "First channel got a value" }
        more $c2 { say "Second channel got a value" }
        wait 0   { say "Not done yet"; Nil }
    }

The construct as a whole returns the result of whichever block was selected.

It's also possible to process a variadic list of channels together,
using generic code that works over some set of the channels (use C<*>
to represent any of them).  The index and the received value are passed to
the code as named arguments C<$:k> and <$:v> (possibly via priming if
the code is instantiated ahead of time).

    winner * {
        more @channels { say "Channel $:k received, result was: ", $:v }
    }

In this case C<$:k> returns the index of the channel, base 0.
Likewise C<$:v> returns the value.

The C<winner> construct also automatically checks the C<.done> promise
corresponding to the channel, so it can also be used in order
to write a loop to receive from a channel until it is closed:

    gather loop {
        winner $channel {
            more * { take $_ }
            done * { last }
        }
    }
This is such a common pattern that we make a channel in list context behave
that way:

    for @$channel -> $val { ... }
    for $channel.list -> $val { ... }

(Note that this is not a combinator, but a means for transfering data from
the reactive realm to the lazy realm.  Some reasonable amount of buffering
is assumed between the two.)

=head1 Supplies

Channels are good for producer/consumer scenarios, but because each worker
blocks on receive, it is not such an ideal construct for doing fine-grained
processing of asynchronously produced streams of values. Additionally, there
can only be one receiver for each value. Supplies exist to address both
of these issues.

A C<Supply> pushes or pumps values to one or more receivers who have registered
their interest.  There are two types of Supplies: C<live> and C<on demand>.
When tapping into a C<live> supply, the tap will only see values that have
been pumped B<after> the tap has been created.  A tap on an C<on demand>
supply will always see B<all> values that have been / will be pumped into the
supply, regardless of when the tap is created.

Anything that does the C<Supply> role can be tapped (that is, subscribed to)
by calling the C<tap> method on it. This takes up to three callables as
arguments, the optional ones expresses as named arguments:

    $supply.tap: -> $value { say "Got a $value" },
        done => { say "Reached the end" },
        quit => {
            when X::FooBar { die "Major oopsie" };
            default        { warn "Supply shut down early: $_" }
        }

The first, known as C<more>, is invoked whenever a value is produced by the
thing that has been tapped. The optional named parameter C<done> specifies
the code to be invoked when all expected values have been produced and no more
will be. The optional named parameter C<quit> specifies the code to be invoked
if there is an error. This also means there will be no further values.

The simplest Supply is a C<Supply> class, which is punned from the role.
It creates a C<live> supply.  On the "pumping" end, this has corresponding
methods C<more>, C<done>, and C<quit>, which notify all current taps.

    my $s = Supply.new;
    
    my $t1 = $s.tap({ say $_ });
    $s.more(1);                              # 1\n
    $s.more(2);                              # 2\n
    
    my $t2 = $s.tap({ say 2 * $_ },
                    { say "End" });
    $s.more(3);                              # 3\n6\n

The object returned by C<tap> represents the subscription. To stop
subscribing, call C<close> on it.

    $t1.close;
    $s.more(4);                              # 8\n
    $s.done;                                 # End\n

This doesn't introduce any asynchrony directly. However, it is possible for
values to be pumped into a C<Supply> from an asynchronous worker.

The C<Supply> class has various methods that produce more interesting kinds of
C<Supply>.  These default to working asynchronously.

C<Supply.for> takes a (potentially lazy) list of values, and returns an
on demand C<Supply> that, when tapped, will iterate over the values and invoke
the C<more> callable for each of them, and any C<done> callable at the end.
If the iteration at some point produces an exception, then the C<quit>
callable will be invoked to pass along the exception.

C<Supply.interval> produces a live C<Supply> that, when tapped, will produce an
ascending value at a regular time interval.

    Supply.interval(1).tap(&say);     # Once a second, starting now
    Supply.interval(5, 10).tap(&say); # Each 5 seconds, starting in 10 seconds

[TODO: many more of these, including ones for publishing a Channel and a
Promise.]

Supplies are mathematically dual to iterators, and so it is possible to
define the same set of operations on them as are available on lazy lists. The
key difference is that, while C<grep> on a lazy list I<pulls> a value to
process, working synchronously, C<grep> on a Supply has values I<pushed>
through it, and pushes those that match the filter onwards to anything that
taps it.

The following methods are available on a C<Supply>:

=over

=item flat

=item grep

=item map

=item uniq

=item squish

=back

There are some others that will only publish a result or results if C<done> is
reached:

=over

=item elems

=item max

=item min

=item minmax

=item reduce

=item reverse

=item sort

=back

There are some combinators that deal with bringing multiple supplies
together:

=over

=item C<merge>

produces a supply containing the values produced by two
other supplies, and triggering C<done> once both of the supplies have
done so. 

=item C<zip>

produces a supply that pairs together items from two other
supplies, using C<< infix:<,> >> by default or any other user-supplied
function.

=back

[TODO: plenty more of these: combine_latest, while, until...]

These combinators that involve multiple supplies need care in their
implementation, since values may arrive at any point on each, and possibly at
the same time. To help write such combinators, the C<on> meta-combinator is
useful. C<on> taps many supplies, and ensures that only B<one> callback will be
running at a time, freeing the combinator writer of worrying about
synchronization issues. Here is how C<zip> is implemented:

    method zip(Supply $a, Supply $b, &with = &infix:<,>) {
        my @as;
        my @bs;
        on -> $res {
            $a => sub ($val) {
                @as.push($val);
                if @as && @bs {
                    $res.more(with(@as.shift, @bs.shift));
                }
            },
            $b => sub ($val) {
                @bs.push($val);
                if @as && @bs {
                    $res.more(with(@as.shift, @bs.shift));
                }
            }
        }
    }

Conjecture: this is going to end up looking more like:


    method zip(Supply $a, Supply $b, &with = &infix:<,>) {
        my @as;
        my @bs;
        combine $a, $b -> $out {
            more * {
                ($:k ?? @bs !! @as).push($_);
                if @as && @bs {
                    $out.more(with(@as.shift, @bs.shift));
                }
            }
        }
    }

or even:

    method zip(*@in, :&with = &infix:<,>) {
        my @streams = [] xx @in;
        combine @in -> $out {
            more * {
                @streams[$:k].push($_);
                if all @streams».elems > 0 {
                    $out.more(with(|@streams));
                }
            }
        }
    }

(As with the reaction routines for C<winner>, in C<combine> the
reaction routines C<$:k> is passed as the position of the matching
entry from the list supplied to C<combine>, and C<$:v> is the actual
supply object that was passed in that position and that is being
tapped for its value.)

Thus there is never any race or other thread-safely problems with
mutating the C<@as> and C<@bs>. The default behaviour, if a callable is
specified along with the supply, is to use it for C<more> and provide
a default C<done> and C<quit>. The default C<done> triggers C<done>
on the result supply, which is the correct semantics for C<zip>. On
the other hand, C<merge> wants different semantics, and so must
provide a C<done>. This can be implemented as follows:

    method merge(Supply $a, Supply $b) {
        my $done = 0;
        on -> $res {
            $a => {
                more => sub ($val) { $res.more($val) },
                done => {
                    $res.done() if ++$done == 2;
                }
            },
            $b => {
                more => sub ($val) { $res.more($val) },
                done => {
                    $res.done() if ++$done == 2;
                }
            }
        }
    }

or conjecturally:

    method merge(*@ins) {
        my $done = 0;
        combine @ins -> $out {
            more * { $out.more($_) }
            done * { $out.done() if ++$done == +@ins; }
        }
    }

A C<quit> handler can be provided in a similar way, although the default - convey the
failure to the result supply - is normally what is wanted. The exception
is writing combinators related to error handling.

=head1 The Event Loop

There is no event loop.  Previous versions of this synopsis mentioned an event
loop that would be underlying all concurrency.  In this version, this is not
the case.

Instead, most system level events, be they POSIX signals, or specific OS events
such as file updates, will be exposed as a C<Supply>.  For instance,
$*POSIX is a Supply in which POSIX signals received by the running
process, will appear as C<POSIX::Signal> objects to taps.  On
non-POSIX systems, a similar Supply will exist to handle system events.

=head2 Threads

VM-level threads, which typically correspond to OS-level threads, are exposed
through the C<Thread> class. Whatever underlies it, a C<Thread> should always
be backed by something that is capable of being scheduled on a CPU core (that
is, it may I<not> be a "green thread" or similar). Most users will not need to
work with C<Thread>s directly. However, those building their own schedulers
may well need to do so, and there may be other exceptional circumstances that
demand such low-level control.

The easiest way to start a thread is with the C<start> method, which takes a
C<Callable> and runs it on a new thread:

    my $thread = Thread.start({
        say "Gosh, I'm in a thread!";
    });

It is also possible to create a thread object, and set it running later:

    my $thread = Thread.new(code => {
        say "A thread, you say?";
    });
    # later...
    $thread.run();

Both approaches result in C<$thread> containing a C<Thread> object. At some
point, C<finish> should be called on the thread, from the thread that started
it. This blocks until the thread has completed.

    say "Certainly before the thread is started";
    my $thread = Thread.start({ say "In the thread" });
    say "This could come before or after the thread's output";
    $thread.finish();
    say "Certainly after all the above output";

As an alternative to C<finish>, it is possible to create a thread whose lifetime
is bounded by that of the overall application. Such threads are automatically
terminated when the application exits. In a scenario where the initial thread
creates an application lifetime thread and no others, then the exit of the
initial thread will cause termination of the overall program. Such a thread is
created by either:

    my $thread = Thread.new(:code({ ... }), :app_lifetime);

Or just, by using the C<start> method:

    my $thread = Thread.start({ ... }, :app_lifetime);

The property can be introspected:

    say $thread.app_lifetime; # True/False

Each thread also has a unique ID, which can be obtained by the C<id> property.

    say $thread.id;

This should be treated as an opaque number. It can not be assumed to map to
any particular operating system's idea of thread ID, for example. For that,
use something that lets you get at OS-level identifiers (such as calling an OS
API using NativeCall).

A thread may also be given a name.

    my $thread = Thread.start({ ... }, :name<Background CPU Eater>);

This can be useful for understanding its usage. Uniqueness is not enforced;
indeed, the default is "<anon>".

A thread stringifies to something of the form:

    Thread<id>(name)

For example:

    Thread<1234>(<anon>)

The currently executing thread is available through C<$*THREAD>. This is even
available in the initial thread of the program, in this case by falling back
to C<$PROCESS::THREAD>, which is the initial thread of the process.

Finally, the C<yield> method can be called on C<Thread> (not on any particular
thread) to hint to the OS that the thread has nothing useful to do for the
moment, and so another thread should run instead.

=head2 Atomic Compare and Swap

The Atomic Compare and Swap (CAS) primitive is directly supported by most
modern hardware. It has been shown that it can be used to build a whole range
of concurrency control mechanisms (such as mutexes and semaphores). It can
also be used to implement lock-free data structures. It is decidedly a
primitive, and not truly composable due to risk of livelock. However, since so
much can be built out of it, Perl 6 provides it directly.

A Perl 6 implementation of CAS would look something like this:

    sub cas($ref is rw, $expected, $new) {
        my $seen = $ref;
        if $ref === $expected {
            $ref = $new;
        }
        return $seen;
    }

Except that it happens atomically. For example, a crappy non-reentrant
mutex could be implemented as:

    class CrappyMutex {
        has $!locked = 0;
        
        method lock() {
            loop {
                return if cas($!locked, 0, 1) == 0;
            }
        }
        
        method unlock() {
            $!locked = 0;
        }
    }

Another common use of CAS is in providing lock-free data structures. Any data
structure can be made lock-free as long as you're willing to never mutate it,
but build a fresh one each time. To support this, there is another C<&cas>
candidate that takes a scalar and a block. It calls the block with the seen
initial value. The block returns the new, updated value. If nothing
else updated the value in the meantime, the reference will be updated. If
the CAS fails because another update got in first, the block will be run
again, passing in the latest value.

So, atomically incrementing a variable is done thusly:

    cas $a, { $_.succ };    # $a++

or more generally for all assignment meta-operators:

    cas $a, { $_ * 5 };     # $a *= 5

Another  example, implementing a top-5 news headlines list to be accessed and
updated without ever locking, as:

    class TopHeadlines {
        has $!headlines = [];   # Scalar holding array, as CAS needs
        
        method headlines() {
            $!headlines
        }
        
        method add_headline($headline) {
            cas($!headlines, -> @current {
                my @new = $headline, @current;
                @new.pop while @new.elems > 5;
                @new
            });
        }
    }

It's the programmer's duty to ensure that the original data structure is never
mutated and that the block has no side-effects (since it may be run any number
of times).

=head1 Low-level primitives

Perl6 offers high-level concurrency methods, but in extreme cases, like if you
need to implement a fundamentally different mechanism, these primitives are
available.

=head2 Locks

Locks are unpleasant to work with, and users are pushed towards higher level
synchronization primitives. However, those need to be implemented via lower
level constructs for efficiency. As such, a simple lock mechanism - as close to
what the execution environment offers as possible - is provided by the C<Lock>
class. Note that it is erroneous to rely on the exact representation of an
instance of this type (for example, don't assume it can be mixed into). Put
another way, treat C<Lock> like a native type.

A C<Lock> is instantiated with C<new>:

    $!lock = Lock.new;

The best way to use it is:

    $!lock.protect: {
        # code to run with the lock held
    }

This acquires the lock, runs the code passed, and then releases the lock. It
ensures the lock will be released even if an exception is thrown. It is also
possible to do:

    {
        $!lock.lock();
        # do stuff
        LEAVE $!lock.unlock()
    }

When using the C<lock> and C<unlock> methods, the programmer must ensure that
the lock is unlocked. C<Lock> is reentrant. Naturally, it's easy to
introduce deadlocks. Again, this is a last resort, intended for those who are
building first resorts.

=head2 Semaphore

The C<Semaphore> class implements traditional semaphores that can be initiated
with a fixed number of permits and offers the operations C<acquire> to block
on a positive number of permits to become available and then reduce that number
by one, C<tryacquire> to try to acquire a permit, but return C<False> instead
of blocking if there are no permits available yet. The last operation is
C<release>, which will increase the number of permits by one.

The initial number of permits may be negative, positive or 0.

Some implementations allow for race-free acquisition and release of multiple
permits at once, but this primitive does not offer that capability.

=for vim:set expandtab sw=4:
