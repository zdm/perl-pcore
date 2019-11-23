package Pcore::HTTP::Server;

use Pcore -class, -const, -res;
use Pcore::Lib::Scalar qw[is_uri weaken is_ref is_plain_arrayref is_plain_scalarref];
use Pcore::Lib::Text qw[encode_utf8];
use Pcore::Lib::List qw[pairs];
use AnyEvent::Socket qw[];
use Pcore::HTTP::Server::Request;

# listen:
# - /socket/path
# - abstract-socket-name
# - //0.0.0.0:80
# - //127.0.0.1:80

has on_request => ( required => 1 );    # CodeRef->($req)
has listen     => ();

has backlog      => 0;
has so_no_delay  => 1;
has so_keepalive => 1;

has server_tokens         => qq[Pcore-HTTP-Server/$Pcore::VERSION];
has keepalive_timeout     => 60;                                      # 0 - disable keepalive
has client_header_timeout => 60;                                      # undef - do not use
has client_body_timeout   => 60;                                      # undef - do not use
has client_max_body_size  => 0;                                       # 0 - do not check

has _listen_socket => ( init_arg => undef );

# TODO implement shutdown and graceful shutdown

sub BUILD ( $self, $args ) {

    # parse listen
    $self->{listen} = P->uri( $self->{listen}, base => 'tcp:', listen => 1 ) if !is_uri $self->{listen};

    $self->{_listen_socket} = &AnyEvent::Socket::tcp_server(          ## no critic qw[Subroutines::ProhibitAmpersandSigils]
        $self->{listen}->connect,
        sub {
            Coro::async_pool sub { return $self->_on_accept(@_) }, @_;

            return;
        },
        sub {
            return $self->_on_prepare(@_);
        }
    );

    chmod( oct 777, $self->{listen}->{path} ) || die $! if !defined $self->{listen}->{host} && substr( $self->{listen}->{path}, 0, 2 ) ne "/\x00";

    return;
}

sub _on_prepare ( $self, $fh, $host, $port ) {
    return $self->{backlog} // 0;
}

sub _on_accept ( $self, $fh, $host, $port ) {
    my $h = P->handle(
        $fh,
        so_no_delay  => $self->{so_no_delay},
        so_keepalive => $self->{so_keepalive},
    );

    # read HTTP headers
  READ_HEADERS:
    my $env = $h->read_http_req_headers( timeout => $self->{client_header_timeout} );

    # HTTP headers read error
    if ( !$env ) {
        if ( $h->is_timeout ) {
            $self->return_xxx( $h, 408 );
        }
        else {
            $self->return_xxx( $h, 400 );
        }

        return;
    }

    # read HTTP body
    # https://www.w3.org/Protocols/rfc2616/rfc2616-sec4.html#sec4.4
    # Transfer-Encoding has priority before Content-Length

    my $data;

    # chunked body
    if ( $env->{TRANSFER_ENCODING} && $env->{TRANSFER_ENCODING} =~ /\bchunked\b/smi ) {
        my $payload_too_large;

        my $on_read_len = do {
            if ( $self->{client_max_body_size} ) {
                sub ( $len, $total_bytes ) {
                    if ( $total_bytes > $self->{client_max_body_size} ) {
                        $payload_too_large = 1;

                        return;
                    }
                    else {
                        return 1;
                    }
                };
            }
            else {
                undef;
            }
        };

        $data = $h->read_http_chunked_data( timeout => $self->{client_body_timeout}, on_read_len => $on_read_len );

        # HTTP body read error
        if ( !$data ) {

            # payload too large
            if ($payload_too_large) {
                return $self->return_xxx( $h, 413 );
            }

            # timeout
            elsif ( $h->is_timeout ) {
                return $self->return_xxx( $h, 408 );
            }

            # read error
            else {
                return $self->return_xxx( $h, 400 );
            }
        }

        $env->{CONTENT_LENGTH} = length $data->$*;
    }

    # fixed body length
    elsif ( $env->{CONTENT_LENGTH} ) {

        # payload too large
        return $self->return_xxx( $h, 413 ) if $self->{client_max_body_size} && $self->{client_max_body_size} > $env->{CONTENT_LENGTH};

        $data = $h->read_chunk( $env->{CONTENT_LENGTH}, timeout => $self->{client_body_timeout} );

        # HTTP body read error
        if ( !$data ) {

            # timeout
            if ( $h->is_timeout ) {
                return $self->return_xxx( $h, 408 );
            }

            # read error
            else {
                return $self->return_xxx( $h, 400 );
            }
        }
    }

    my $keepalive = do {
        if ( !$self->{keepalive_timeout} ) {
            0;
        }
        else {
            if ( $env->{SERVER_PROTOCOL} eq 'HTTP/1.1' ) {
                $env->{HTTP_CONNECTION} && $env->{HTTP_CONNECTION} =~ /\bclose\b/smi ? 0 : 1;
            }
            elsif ( $env->{SERVER_PROTOCOL} eq 'HTTP/1.0' ) {
                !$env->{HTTP_CONNECTION} || $env->{HTTP_CONNECTION} !~ /\bkeep-?alive\b/smi ? 0 : 1;
            }
            else {
                1;
            }
        }
    };

    # create request object
    my $req = bless {
        _server          => $self,
        _h               => $h,
        env              => $env,
        data             => $data,
        keepalive        => $keepalive,
        _response_status => 0,
      },
      'Pcore::HTTP::Server::Request';

    # evaluate "on_request" callback
    my @res = eval { $self->{on_request}->($req) };

    weaken $req;

    if ($@) {
        $@->sendlog;

        return;
    }

    # request is not finished
    elsif ( defined $req ) {
        my $cv = $req->{_cb} = P->cv;

        # keep-alive
        goto READ_HEADERS if !$cv->recv && $keepalive;
    }
    else {

        # compose headers
        # https://tools.ietf.org/html/rfc7230#section-3.2
        my ( $headers, $body );

        $headers = do {
            my $status = 0+ $res[0];
            my $reason = P->result->resolve_reason($status);

            "HTTP/1.1 $status $reason\r\n";
        };

        $headers .= "Server:$self->{server_tokens}\r\n" if $self->{server_tokens};

        # keepalive
        $headers .= 'Connection:' . ( $keepalive ? 'keep-alive' : 'close' ) . "\r\n";

        # add custom headers
        $headers .= join( "\r\n", map {"$_->[0]:$_->[1]"} pairs $res[1]->@* ) . "\r\n" if $res[1] && $res[1]->@*;

        if ( @res > 2 ) {
            for ( my $i = 2; $i <= $#res; $i++ ) {
                if ( !is_ref $res[$i] ) {
                    $body .= encode_utf8 $res[$i];
                }
                elsif ( is_plain_scalarref $res[$i] ) {
                    $body .= encode_utf8 $res[$i]->$*;
                }
                elsif ( is_plain_arrayref $res[$i] ) {
                    $body .= join $EMPTY, map { encode_utf8 $_ } $res[$i]->@*;
                }
                else {
                    die q[Body type isn't supported];
                }
            }

            if ( defined $body ) {
                $headers .= "Content-Length:@{[ length $body ]}\r\n";
            }
            else {
                $headers .= "Content-Length:0\r\n";
            }
        }
        else {
            $headers .= "Content-Length:0\r\n";
        }

        $h->write( $headers . "\r\n" . ( $body // $EMPTY ) );
    }

    return;
}

sub return_xxx ( $self, $h, $status, $close_connection = 1 ) {

    # handle closed, do nothing
    return if !$h;

    $status = 0+ $status;

    my $reason = P->result->resolve_reason($status);

    my $buf = "HTTP/1.1 $status $reason\r\nContent-Length:0\r\n";

    $buf .= 'Connection:' . ( $close_connection ? 'close' : 'keep-alive' ) . "\r\n";

    $buf .= "Server:$self->{server_tokens}\r\n" if $self->{server_tokens};

    $h->write("$buf\r\n");

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 59                   | Subroutines::ProhibitExcessComplexity - Subroutine "_on_accept" with high complexity score (47)                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    2 | 225                  | ControlStructures::ProhibitCStyleForLoops - C-style "for" loop used                                            |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Server

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
