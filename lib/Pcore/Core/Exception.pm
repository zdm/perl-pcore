package Pcore::Core::Exception;

use Pcore -export => {    #
    DEFAULT => [qw[croak cluck try catch]],
};
use Carp qw[];
use Pcore::Core::Exception::Object qw[:CONST];

our $IGNORE_ERRORS = 1;    # do not write errors to error log channel by default

sub CORE_INIT {

    # needed to properly destruct TEMP_DIR
    $SIG->{INT} = AE::signal INT => \&SIGINT;

    # needed to properly destruct TEMP_DIR
    $SIG->{TERM} = AE::signal TERM => \&SIGTERM;

    $SIG{__DIE__} = \&SIGDIE;    ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    $SIG{__WARN__} = \&SIGWARN;  ## no critic qw[Variables::RequireLocalizedPunctuationVars]

    *CORE::GLOBAL::die = \&GLOBAL_DIE;

    *CORE::GLOBAL::warn = \&GLOBAL_WARN;

    # we don't need stacktrace from Error::TypeTiny exceptions
    $Error::TypeTiny::StackTrace = 0;

    {
        no warnings qw[redefine];

        *Carp::longmess = *Carp::shortmess = sub {
            if ( defined $_[0] ) {
                return $_[0];
            }
            else {
                return q[];
            }
        };
    }

    return;
}

sub SIGINT {
    exit;
}

sub SIGTERM {
    exit;
}

# SIGNALS
# http://perldoc.perl.org/perlvar.html#%25SIG
# The routine indicated by $SIG{__DIE__} is called when a fatal exception is about to be thrown. The error message is passed as the first argument. When a __DIE__ hook routine returns, the exception processing continues as it would have in the absence of the hook, unless the hook routine itself exits via a goto &sub , a loop exit, or a die(). The __DIE__ handler is explicitly disabled during the call, so that you can die from a __DIE__ handler. Similarly for __WARN__.
# die in BEGIN generates parsing error, no matter in eval or not;
# compile-time errors / warnings belongs to namespace, from which compilation was requested;
sub SIGDIE {
    my $e = Pcore::Core::Exception::Object->new( $_[0], level => $ERROR, skip_frames => 1, trace => 1 );

    CORE::die $_[0] unless defined $e;    # fallback to standart behavior if exception wasn't created for some reasons

    if ( !defined $^S || $^S ) {          # ERROR, catched in eval
        $e->send_log( level => 'ERROR' ) unless $IGNORE_ERRORS;

        return CORE::die $e;              # terminate standart die behavior
    }
    else {                                # FATAL
        $e->send_log( level => 'FATAL', force => 1 );

        exit $e->exit_code;
    }
}

sub SIGWARN {
    my $e = Pcore::Core::Exception::Object->new( $_[0], level => $WARN, skip_frames => 1, trace => 1 );

    # fallback to standart behavior if exception wasn't created for some reasons
    unless ( defined $e ) {
        CORE::warn $_[0];

        return;
    }

    $e->send_log( level => 'WARN' );

    return;    # terminate standart warn behavior
}

# HOOKS
sub GLOBAL_DIE {
    my $msg = defined $_[0] ? $_[0] : defined $@ ? $@ : 'Died';

    my $e = Pcore::Core::Exception::Object->new( $msg, level => $ERROR, skip_frames => 1, trace => 1, from_hook => 1 );

    if ( defined $e ) {
        return CORE::die $e;
    }
    else {
        return CORE::die $msg;
    }
}

sub GLOBAL_WARN {
    my $msg = defined $_[0] ? $_[0] : defined $@ ? $@ : q[Warning: something's wrong];

    my $e = Pcore::Core::Exception::Object->new( $msg, level => $WARN, skip_frames => 1, trace => 1, from_hook => 1 );

    if ( defined $e ) {
        return CORE::warn $e;
    }
    else {
        return CORE::warn $msg;
    }
}

# die without trace
sub croak {
    my $msg = defined $_[0] ? $_[0] : defined $@ ? $@ : 'Died';

    my $e = Pcore::Core::Exception::Object->new( $msg, level => $ERROR, skip_frames => 1, trace => 0, from_hook => 1 );

    if ( defined $e ) {
        return CORE::die $e;
    }
    else {
        return CORE::die $msg;
    }
}

# warn with trace
sub cluck {
    my $msg = defined $_[0] ? $_[0] : defined $@ ? $@ : q[Warning: something's wrong];

    my $e = Pcore::Core::Exception::Object->new( $msg, level => $WARN, skip_frames => 1, trace => 1, from_hook => 1 );

    if ( defined $e ) {
        return CORE::warn $e;
    }
    else {
        return CORE::warn $msg;
    }
}

# propagate
sub propagate {
    my $msg = defined $_[0] ? $_[0] : defined $@ ? $@ : 'PROPAGATED';

    return Pcore::Core::Exception::Object->new( $msg, level => $ERROR, skip_frames => 1, trace => 1, propagated => 1 )->propagate;
}

# TRY
sub try : prototype(&@) {
    my ( $try, @code_refs ) = @_;

    my $wantarray = wantarray;
    my $catch;
    foreach my $code_ref (@code_refs) {
        my $ref = ref $code_ref;

        if ( $ref eq 'Pcore::Core::ExceptionCatch' ) {
            die 'Invalid usage, only one catch block allowed' if $catch;

            $catch = ${$code_ref};
        }
        else {
            die "Unknown code ref type given '${ref}'. Check your usage & try again";
        }
    }

    P->class->set_subname( '::try' => $try );
    P->class->set_subname( '::catch' => $catch ) if $catch;

    # eval
    my $prev_error = $@;
    my @res;
    my $failed = not eval {
        local $SIG{__DIE__} = \&SIGDIE;

        $@ = $prev_error;    ## no critic qw[Variables::RequireLocalizedPunctuationVars] make previous $@ accesible inside eval, eval clean $@ before start

        if ($wantarray) {
            @res = $try->();
        }
        elsif ( defined $wantarray ) {
            $res[0] = $try->();
        }
        else {
            $try->();
        }

        return 1;
    };

    my $e = $@;

    # error handling
    if ($failed) {
        if ($catch) {
            if ($wantarray) {
                @res = $catch->($e);
            }
            elsif ( defined $wantarray ) {
                $res[0] = $catch->($e);
            }
            else {
                $catch->($e);
            }
        }

        if ( $e->is_propagated ) {
            $@ = q[];    ## no critic qw[Variables::RequireLocalizedPunctuationVars], clear $@ because handled propagated exception treat as not error

            $e->propagate unless $e->_stop_propagate;
        }
    }

    return $wantarray ? @res : $res[0];
}

sub catch : prototype(&@) {
    my $code = shift;

    return ( bless( \$code, 'Pcore::Core::ExceptionCatch' ), @_ );
}

1;
__END__
=pod

=encoding utf8

=head1 Pcore::Core::Exception

Pharaoh::Core::Sig - signals management for Pharaoh::Core.

This package is part of Pharaoh::Core.

=head1 EXPORTS

=head2 CORE::GLOBAL::exit

Common exit() family functions behaviour:

=over

=item * threads->exit() and CORE::exit() is unhandled in threads and perform exit according to threads->set_thread_exit_only;

=item * CORE::exit() is unhandled;

=back

=head1 SIGNALS

=head2 SIGDIE

Standart $SIG{__DIE__} exceptions handler. Use following code to redefined callback:

    local $SIG{__DIE__};        # Redefine handler locally, no callback defined, $SIG{__DIE__} will be ignored
    local $SIG{__DIE__} = sub { # Ditto with callback defined
            ...do something...
        };

=over

=item * C<$SIG{__DIE__}> called from eval block produce ERROR log with stack trace and returns;

=item * C<$SIG{__DIE__}> called from NOT eval block produce FATAL log with stack trace and exit from process / thread;

=item * C<__ALRM__> exception from eval ignored;

=item * C<__ALRM__> exception from NOT eval block produce FATAL exception;

=item * C<__EXIT__> exception is ignored totally and can be processed in your code. See CORE::GLOBAL::exit for example;

=item * Calling die() in $SIG{__DIE__} will overwrite $@ and exit $SIG{__DIE__} immidiately;

=item * Overriding die will only catch actual calls to die, not run-time errors;

=back

=head2 SIGWARN

Standart $SIG{__WARN__} handler. Produce standart log event on WARN level with stack backtace. To avoid call use following in your code:

    local $SIG{__WARN__} = sub { };    # Redefine callback locally
    local $SIG{__WARN__} = undef;      # Restore standart behaviour in current block

=head2 SIGALRM

Standart $SIG{ALRM} handler. Produce C<__ALRM__> exception. To redefine callback use following in your code:

    local $SIG{ALRM} = sub { };    # Redefine callback locally

or use this alarm - safe code:

    my $orig_alarm = 0;
    eval{
        $orig_alarm = alarm 5;    # Store previous alarm() timer internally
        ...some code here...
    };
    alarm $orig_alarm;            # Restore previous timer

    if($@ =~ /^__ALRM__/){
        ...do something on alarm...
    }

NOTES

=over

=item * If $SIG{ALRM} not defined - process will killed on alarm. SIG{__DIE__} don't handle alarm exception;

=item * Alarm - safe code must restore previous alarm timer at the end of execution. We can't control bad written code in other modules, so be ready that you alarm timers will not work if you use not alarm - safe modules;

=item * alarm() works on MSWin and in threads as expected;

=item * You must remove alarm timer immidiately after end of eval block (not in block), because if evaluated code will die - eval block will be broken and your alarm will not be removed;

=item * alarm() call on MSWin didn't return amount of time remaining for previous timer. So chained timers on MSWin NOT WORKED.

=back

=cut
