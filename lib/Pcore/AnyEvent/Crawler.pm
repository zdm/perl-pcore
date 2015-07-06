package Pcore::AnyEvent::Crawler;

use Pcore qw[-class];
use Const::Fast qw[];
use Pcore::AnyEvent::Proxy::Pool;

with qw[Pcore::AnyEvent::Status];

has '+status' => ( isa => Enum [qw[stopped stops running finished]], default => 'stopped' );

has get_request => ( is => 'ro', isa => CodeRef, required => 1 );
has put_request => ( is => 'ro', isa => CodeRef, required => 1 );

has max_threads => ( is => 'ro', isa => PositiveInt, default => 100 );

has ua => ( is => 'lazy', isa => InstanceOf ['Pcore::HTTP::UA'], default => sub { P->ua->new }, init_arg => undef );

# proxy
has proxy_pool => ( is => 'rwp', isa => InstanceOf ['Pcore::AnyEvent::Proxy::Pool'], predicate => 1, init_arg => undef );

has cache => ( is => 'lazy', isa => HashRef, default => sub { {} }, init_arg => undef );
has total_reqs => ( is => 'rwp', isa => Int, default => 0, init_arg => undef );
has total_reqs_by_type => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

has running_threads => ( is => 'rw', isa => PositiveOrZeroInt, default => 0, init_arg => undef );
has running_threads_by_type => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

no Pcore;

# request exit codes
Const::Fast::const our $REQ_DONE   => 1;
Const::Fast::const our $REQ_REPEAT => 3;
Const::Fast::const our $REQ_REJECT => 2;

sub BUILD ( $self, $args ) {
    if ( $args->{proxy_pool} ) {
        if ( ref $args->{proxy_pool} eq 'HASH' ) {
            $self->_set_proxy_pool( Pcore::AnyEvent::Proxy::Pool->new( $args->{proxy_pool} ) );
        }
        else {
            $self->_set_proxy_pool( $args->{proxy_pool} );
        }
    }

    return;
}

sub before_set_status ( $self, $status, $old_status ) {
    if ( $status eq 'stopped' ) {    # остановлен
        return 1 if $old_status eq 'stops';
    }
    elsif ( $status eq 'stops' ) {    # остановливается
        return 1 if $old_status eq 'running';
    }
    elsif ( $status eq 'running' ) {
        return 1 if $old_status eq 'stopped' || $old_status eq 'stops';
    }
    elsif ( $status eq 'finished' ) {
        return 1;
    }

    return 0;
}

sub on_status ( $self, $status, $old_status ) {
    $self->_create_requests if $status eq 'running';

    return;
}

sub run ($self) {
    $self->_set_status('running');

    return;
}

sub stop ($self) {
    $self->_set_status('stops');

    return;
}

sub finish ($self) {
    $self->_set_status('finished');

    return;
}

sub _create_requests ($self) {

    # change status to "stoppped" if all threads was finished
    if ( $self->status eq 'stops' && !$self->running_threads ) {
        $self->_set_status('stopped');

        return;
    }

    # disable new requests if status is not "running"
    return if $self->status ne 'running';

    while ( $self->running_threads < $self->max_threads ) {
        if ( my $req = $self->get_request->($self) ) {
            $req->set_crawler($self);

            $self->_start_request($req);
        }
        else {
            # finish if no more requests to process and all threads are finished
            $self->finish if !$self->running_threads;

            last;
        }
    }

    return;
}

sub _start_request ( $self, $req ) {

    # increment _running threads counter
    $self->running_threads( $self->running_threads + 1 );

    # increment _running threads by type counter
    $self->running_threads_by_type->{ $req->type }++;

    my $responder = sub ($action) {
        $action //= $REQ_DONE;

        # process response content, only if status is not "finished"
        if ( $self->status ne 'finished' && $action eq $REQ_DONE ) {
            eval { $self->put_request->( $self, $req ) };

            $@->send_log if $@;
        }

        # decrement running threads counter
        $self->running_threads( $self->running_threads - 1 );

        # decrement running threads by type counter
        $self->running_threads_by_type->{ $req->type }--;

        # free proxy
        $req->proxy->finish_thread if $req->has_proxy;

        # clear request
        $req->clear;

        if ( $action eq $REQ_REPEAT && $self->status ne 'finished' ) {
            $self->_start_request($req);
        }
        else {
            $self->_create_requests;
        }

        return;
    };

    my $run_request = sub {
        $self->ua->request(
            $req,
            before_finish => sub ($res) {
                if ( $self->status ne 'finished' ) {

                    # increment total reqs done
                    $self->_set_total_reqs( $self->total_reqs + 1 );

                    # increment total reqs by type
                    $self->total_reqs_by_type->{ $req->type }++;

                    $req->set_res($res);

                    eval { $req->process_response( $res, $responder ); };

                    $@->send_log if $@;
                }

                return;
            }
        );

        return;
    };

    # try to get proxy from proxy_pool
    if ( $req->use_proxy != $Pcore::AnyEvent::Crawler::Request::PROXY_NO && $self->has_proxy_pool ) {
        my $get_proxy_args = {};

        $get_proxy_args->{list} = $req->url =~ /\Ahttps:/sm ? 'https' : 'http';

        my $proxy = $self->proxy_pool->get_proxy( $get_proxy_args->%* );

        if ($proxy) {
            $req->set_proxy($proxy);

            $run_request->();
        }
        else {    # proxy isn't available
            if ( $req->use_proxy == $Pcore::AnyEvent::Crawler::Request::PROXY_MAYBE ) {    # don't use proxy
                $run_request->();
            }
            else {                                                                         # wait, while proxy will be available
                my $t;

                my $timer_cb;

                my $set_timer = sub {
                    $t = AnyEvent->timer(
                        after => 1,
                        cb    => $timer_cb,
                    );
                };

                $timer_cb = sub {

                    # skip request it status is "finished"
                    if ( $self->status eq 'finished' ) {
                        undef $t;
                    }
                    elsif ( $proxy = $self->proxy_pool->get_proxy( $get_proxy_args->%* ) ) {
                        undef $t;

                        $req->set_proxy($proxy);

                        $run_request->();
                    }
                    else {
                        $set_timer->();
                    }

                    return;
                };

                $set_timer->();
            }
        }
    }
    else {
        $run_request->();
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## ┌──────┬──────────────────────┬────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
## │ Sev. │ Lines                │ Policy                                                                                                         │
## ╞══════╪══════════════════════╪════════════════════════════════════════════════════════════════════════════════════════════════════════════════╡
## │    3 │ 118                  │ Subroutines::ProhibitExcessComplexity - Subroutine "_start_request" with high complexity score (21)            │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 131, 172             │ ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              │
## ├──────┼──────────────────────┼────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
## │    3 │ 190, 219             │ References::ProhibitDoubleSigils - Double-sigil dereference                                                    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=cut
