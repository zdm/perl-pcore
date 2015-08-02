package Pcore::AnyEvent::Handle::Cache;

use Pcore;
use AnyEvent::Handle qw[];
use Pcore::AnyEvent::Proxy;
use Socket;
use IO::Socket::Socks;
use AnyEvent::Socket;

no Pcore;

# changing this is evil, default 4, unused cached connection will be automatically closed after this timeout
our $PERSISTENT_TIMEOUT = 4;

# changing this is evil, default 4, max. parallel connections to the same host
our $MAX_PER_HOST = 1000;
our $ACTIVE       = 0;

my %KA_CACHE;    # indexed by uri host currently, points to [$handle...] array
my %CO_SLOT;     # number of open connections, and wait queue, per host

# socks constants
my $SOCKS_READ_WATCHER  = 1;
my $SOCKS_WRITE_WATCHER = 2;

sub get_connection {

    my $prepare_handle = sub {
        my ($hdl) = $state{handle};

        $hdl->on_error(
            sub {
                _error( \%state, $on_finish, $args->{res}, $ae_error, $_[2] );
            }
        );
        $hdl->on_eof(
            sub {
                _error( \%state, $on_finish, $args->{res}, $ae_error, 'Unexpected end-of-file' );
            }
        );

        $hdl->timeout_reset;

        $hdl->timeout( $args->{timeout} );
    };

    # connected to proxy (or origin server)
    # called only when new connection established, not for cached connections
    my $connect_cb = sub {
        my $fh = shift or return _error( \%state, $on_finish, $args->{res}, $ae_error, qq[$!] );

        return unless delete $state{connect_guard};

        # get handle
        $state{handle} = AnyEvent::Handle->new(
            %{ $args->{handle_params} },
            fh       => $fh,
            peername => $url->host,
            tls_ctx  => $args->{tls_ctx}
        );

        $prepare_handle->();

        # now handle proxy-CONNECT method
        if ( $connect->{proxy} eq 'https' ) {
            $state{handle}->push_write( q[CONNECT ] . $url->host . q[:] . $url_port . q[ HTTP/1.0] . $CRLF . $connect->{https_auth} . $CRLF );

            $state{handle}->push_read(
                line => $QR_NLNL,
                sub {
                    # proxy response processing
                    if ( my $parsed_headers = _parse_headers( $_[1] . $CRLF ) ) {
                        if ( $parsed_headers->[2] == 200 ) {
                            $handle_actual_request->();
                        }
                        else {
                            return _error( \%state, $on_finish, $args->{res}, $parsed_headers->[2], $parsed_headers->[3] );
                        }
                    }
                    else {
                        return _error( \%state, $on_finish, $args->{res}, 599, q[Invalid proxy connect response] );
                    }
                }
            );
        }
        else {
            $handle_actual_request->();
        }
    };

    _get_slot(
        $url->host,
        sub {
            $state{slot_guard} = shift;

            return unless $state{connect_guard};

            # try to use an existing keepalive connection, but only if we, ourselves, plan
            # on a keepalive request (in theory, this should be a separate config option).
            if ( $persistent && $KA_CACHE{$ka_key} ) {
                $was_persistent = 1;

                $state{handle} = _ka_fetch($ka_key);

                $state{handle}->destroyed and die q[AnyEvent::HTTP: unexpectedly got a destructed handle (1), please report.];

                $prepare_handle->();

                $state{handle}->destroyed and die q[AnyEvent::HTTP: unexpectedly got a destructed handle (2), please report.];

                $handle_actual_request->();

            }
            else {
                my $tcp_connect = $args->{tcp_connect} || \&AnyEvent::Socket::tcp_connect;

                # establish TCP connection
                $state{connect_guard} = $tcp_connect->( $connect->{host}, $connect->{port}, $connect_cb, $args->{on_prepare} || sub { $args->{timeout} } );
            }
        }
    );

    return defined wantarray && AnyEvent::Util::guard { _destroy_state( \%state ) };
}

# wait queue/slots
sub _slot_schedule {
    my $host = shift;

    $CO_SLOT{$host}[0] //= 0;

    while ( $CO_SLOT{$host}[0] < $MAX_PER_HOST ) {
        if ( my $cb = shift $CO_SLOT{$host}[1]->@* ) {

            # somebody wants that slot
            ++$CO_SLOT{$host}[0];
            ++$ACTIVE;

            $cb->(
                AnyEvent::Util::guard {
                    --$ACTIVE;
                    --$CO_SLOT{$host}[0];
                    _slot_schedule($host);
                }
            );
        }
        else {
            # nobody wants the slot, maybe we can forget about it
            delete $CO_SLOT{$host} unless $CO_SLOT{$host}[0];

            last;
        }
    }

    return;
}

# wait for a free slot on host, call callback
sub _get_slot {
    push $CO_SLOT{ $_[0] }[1]->@*, $_[1];

    _slot_schedule( $_[0] );

    return;
}

# keepalive/persistent connection cache
# fetch a connection from the keepalive cache
sub _ka_fetch {
    my $ka_key = shift;

    my $hdl = pop $KA_CACHE{$ka_key}->@*;    # currently we reuse the MOST RECENTLY USED connection

    delete $KA_CACHE{$ka_key} unless $KA_CACHE{$ka_key}->@*;

    return $hdl;
}

sub _ka_store {
    my ( $ka_key, $hdl ) = @_;

    my $kaa = $KA_CACHE{$ka_key} ||= [];

    my $destroy = sub {
        my @ka = grep { $_ != $hdl } $KA_CACHE{$ka_key}->@*;

        $hdl->destroy;

        @ka ? $KA_CACHE{$ka_key} = \@ka : delete $KA_CACHE{$ka_key};

        return;
    };

    # on error etc., destroy
    $hdl->on_error($destroy);

    $hdl->on_eof($destroy);

    $hdl->on_read($destroy);

    $hdl->timeout($PERSISTENT_TIMEOUT);

    push $kaa->@*, $hdl;

    while ( $kaa->@* > $MAX_PER_HOST ) {
        shift $kaa->@*;
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
## │    3 │ 179                  │ Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_ka_store' declared but not used    │
## └──────┴──────────────────────┴────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AnyEvent::Handle::Cache

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
