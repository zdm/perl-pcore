#!/usr/bin/env perl

package main v0.1.0;

use Pcore;

our $THREADS = 30;
our $REQS    = 100;

# set use_fork => 0 to use threads instead of forks
run( use_fork => 1, init => \&init, parent => \&parent, child => \&child );

sub init {
    return;
}

sub parent {
    say q[PARENT: ] . P->sys->pid;

    return;
}

sub child {
    say q[CHILD: ] . P->sys->pid;

    try {
        for ( 1 .. $REQS ) {
        }
    }
    catch {
        my $e = shift;

        $e->send_log;

        exit;
    };

    return;
}

sub run {
    my %args = (
        use_fork => undef,
        init     => undef,
        parent   => undef,
        child    => undef,
        @_,
    );

    $args{init}->() if $args{init};

    if ( $args{use_fork} ) {    # use forks
        for ( 1 .. $THREADS ) {
            if ( !fork ) {      # child
                $args{child}->() if $args{child};
                exit;
            }
        }

        $args{parent}->() if $args{parent};

        waitpid -1, 0;          ## no critic qw[InputOutput::RequireCheckedSyscalls]
    }
    else {                      # use threads
        for ( 1 .. $THREADS ) {
            threads->create( $args{child} ) if $args{child};
        }

        $args{parent}->() if $args{parent};

        # wait for all threads has finished
        while ( threads->list(threads::running) ) {
            sleep 1;
        }

        # detach all finished threads
        for my $thr ( threads->list(threads::joinable) ) {
            $thr->detach;
        }
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=cut
