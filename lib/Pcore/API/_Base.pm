package Pcore::API::_Base;

use Pcore -class, -res;
use Pcore::Lib::Scalar qw[weaken];
use Coro::Signal;

has max_threads => 0;

has _threads => 0;
has _queue   => ();
has _signal  => sub { Coro::Signal->new };

sub DESTROY ($self) {
    if ( ${^GLOBAL_PHASE} ne 'DESTRUCT' ) {

        # finish threads
        $self->{_signal}->broadcast;

        # finish tasks
        while ( my $task = shift $self->{_queue}->@* ) {
            $task->[1]->( res 500 ) if $task->[1];
        }
    }

    return;
}

sub _create_request ( $self, $req, $cb = undef ) {

    # threads are limited
    if ( $self->{max_threads} ) {
        if ( defined wantarray ) {
            my $cv = P->cv;

            push $self->{_queue}->@*, [ $req, $cv ];

            $self->_run_thread;

            my $res = $cv->recv;

            return $cb ? $cb->($res) : $res;
        }
        else {
            push $self->{_queue}->@*, [ $req, $cb ];

            $self->_run_thread;

            return;
        }
    }

    # threads are not limited
    else {

        # blocking mode
        if ( defined wantarray ) {
            my $res = $self->_do_request($req);

            return $cb ? $cb->($res) : $res;
        }

        # not blocking mode
        else {
            Coro::async {
                my $res = $self->_do_request($req);

                $cb->($res) if $cb;

                return;
            };

            return;
        }
    }
}

sub _run_thread ($self) {
    if ( $self->{_signal}->awaited ) {
        $self->{_signal}->send;
    }
    elsif ( $self->{_threads} < $self->{max_threads} ) {
        weaken $self;

        $self->{_threads}++;

        Coro::async {
            while () {
                return if !defined $self;

                if ( my $task = shift $self->{_queue}->@* ) {
                    my $res = $self->_do_request( $task->[0] );

                    $task->[1]->($res) if $task->[1];

                    next;
                }

                $self->{_signal}->wait;
            }

            return;
        };
    }

    return;
}

sub _do_request ( $self, $req ) {
    ...;
}

# sub test ( $self, $id, $cb = undef ) {
#     return $self->_create_request(
#         [$id],
#         sub ($res) {
#             say 'process cb';

#             return $cb ? $cb->($res) : $res;
#         }
#     );
# }

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 28                   | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_create_request' declared but not   |
## |      |                      | used                                                                                                           |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 109                  | ControlStructures::ProhibitYadaOperator - yada operator (...) used                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::_Base

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
