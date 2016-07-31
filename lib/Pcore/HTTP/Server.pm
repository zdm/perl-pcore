package Pcore::HTTP::Server;

use Pcore -class;
use Pcore::AE::Handle;
use AnyEvent::Socket qw[];
use Pcore::Util::List qw[pairs];
use Pcore::HTTP::Status;
use Socket qw[IPPROTO_TCP TCP_NODELAY];
use Pcore::HTTP::Server::Writer;

has listen => ( is => 'ro', isa => Str, required => 1 );
has app => ( is => 'ro', isa => CodeRef | ConsumerOf ['Pcore::HTTP::Server::Router'], required => 1 );

has backlog => ( is => 'ro', isa => Maybe [PositiveOrZeroInt], default => 0 );
has tcp_no_delay => ( is => 'ro', isa => Bool, default => 0 );
has keep_alive => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );
has server_signature => ( is => 'ro', isa => Maybe [Str], default => "Pcore-HTTP-Server/$Pcore::VERSION" );

has _listen_uri => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::URI'], init_arg => undef );
has _cv => ( is => 'lazy', isa => Object, default => sub {AE::cv}, init_arg => undef );
has _listen_socket => ( is => 'lazy', isa => Object, init_arg => undef );

# TODO content length - https://www.w3.org/Protocols/rfc2616/rfc2616-sec4.html#sec4.4

# TODO implement shutdown and graceful shutdown
# TODO disconnect header on finish request

sub run ($self) {
    $self->_listen_socket;

    return $self;
}

sub _build__listen_uri ($self) {
    return P->uri( $self->listen, authority => 1, base => 'tcp:' );
}

sub _build__listen_socket ($self) {
    if ( $self->_listen_uri->scheme eq 'unix' ) {
        my $guard = AnyEvent::Socket::tcp_server( 'unix/', $self->_listen_uri->path, sub { return $self->_on_accept(@_) }, sub { return $self->_on_prepare(@_) } );

        chmod oct 777, $self->_listen_uri->path or die;

        return $guard;
    }
    else {
        return AnyEvent::Socket::tcp_server( $self->_listen_uri->host || undef, $self->_listen_uri->port, sub { return $self->_on_accept(@_) }, sub { return $self->_on_prepare(@_) } );
    }
}

sub _on_prepare ( $self, $fh, $host, $port ) {
    return $self->backlog // 0;
}

sub _on_accept ( $self, $fh, $host, $port ) {
    Pcore::AE::Handle->new(
        fh         => $fh,
        on_connect => sub ( $h, @ ) {
            setsockopt( $fh, IPPROTO_TCP, TCP_NODELAY, 1 ) or die "setsockopt(TCP_NODELAY) failed:$!" if $self->tcp_no_delay and $self->_listen_uri->scheme eq 'tcp';

            $self->_cv->begin;

            $self->_wait_request($h);

            return;
        }
    );

    return;
}

sub _wait_request ( $self, $h ) {

    # clear keep-alive timeout for cached handle
    $h->timeout;

    state $psgi_env = {
        'psgi.version'      => [ 1, 1 ],
        'psgi.url_scheme'   => 'http',
        'psgi.input'        => undef,
        'psgi.errors'       => undef,
        'psgi.multithread'  => 0,
        'psgi.multiprocess' => 0,
        'psgi.run_once'     => 0,
        'psgi.nonblocking'  => 1,
        'psgi.streaming'    => 1,

        # extensions
        'psgix.io'              => undef,
        'psgix.input.buffered'  => 1,
        'psgix.logger'          => undef,
        'psgix.session'         => undef,
        'psgix.session.options' => undef,
        'psgix.harakiri'        => 0,
        'psgix.harakiri.commit' => 0,
        'psgix.cleanup'         => 0,
    };

    $h->read_http_req_headers(
        sub ( $h1, $env, $error ) {
            if ($error) {
                $self->_return_xxx( $h, 400 );
            }
            else {
                $self->{_cv}->begin;

                $env->@{ keys $psgi_env->%* } = values $psgi_env->%*;

                if ( $env->{TRANSFER_ENCODING} && $env->{TRANSFER_ENCODING} =~ /\bchunked\b/smi ) {
                    $self->_read_body( $h, $env, 1, 0 );
                }
                elsif ( $env->{CONTENT_LENGTH} ) {
                    $self->_read_body( $h, $env, 0, $env->{CONTENT_LENGTH} );
                }
                else {
                    $env->{'psgi.input'} = undef;

                    $self->_run_app( $h, $env );
                }
            }

            return;
        }
    );

    return;
}

# TODO control read timeout, return status 408 - Request timeout
# TODO control max body size, return 413 - Request Entity Too Large
sub _read_body ( $self, $h, $env, $chunked, $content_length ) {
    $h->read_http_body(
        sub ( $h, $buf_ref, $total_bytes_readed, $error_message ) {
            if ($error_message) {
                $self->_return_xxx( $h, 400 );
            }
            else {
                if ( !$buf_ref ) {
                    $self->_run_app( $h, $env );
                }
                else {
                    $env->{'psgi.input'} .= $buf_ref->$*;

                    $env->{CONTENT_LENGTH} = $total_bytes_readed;

                    return 1;
                }
            }

            return;
        },
        chunked  => $chunked,
        length   => $content_length,
        headers  => 0,
        buf_size => 65_536,
    );

    return;
}

sub _run_app ( $self, $h, $env ) {

    # detect keep-alive
    my $keep_alive = $self->keep_alive;

    if ($keep_alive) {
        if ( $env->{SERVER_PROTOCOL} eq 'HTTP/1.1' ) {
            $keep_alive = 0 if $env->{HTTP_CONNECTION} && $env->{HTTP_CONNECTION} =~ /\bclose\b/smi;
        }
        elsif ( $env->{SERVER_PROTOCOL} eq 'HTTP/1.0' ) {
            $keep_alive = 0 if !$env->{HTTP_CONNECTION} || $env->{HTTP_CONNECTION} !~ /\bkeep-?alive\b/smi;
        }
        else {
            $keep_alive = 0;
        }
    }

    # evaluate application
    my $res = eval { $self->{app}->($env) };

    # processing first psgi app response
    if ($@) {
        warn $@;

        $self->_return_xxx( $h, 500 );
    }
    elsif ( ref $res eq 'ARRAY' ) {
        $self->_write_psgi_response( $h, $res, $keep_alive, 0 );

        $self->_finish_request( $h, $keep_alive );
    }
    elsif ( ref $res eq 'CODE' ) {
        my $headers_written;

        eval {
            $res->(
                sub ($res) {
                    $headers_written = 1;

                    if ( defined wantarray && !$res->[2] ) {

                        # write http response headers, body is delayed
                        $self->_write_psgi_response( $h, $res, $keep_alive, 1 );

                        # return writer object
                        return bless {
                            server     => $self,
                            h          => $h,
                            keep_alive => $keep_alive,
                            buf_size   => 65_536,
                          },
                          'Pcore::HTTP::Server::Writer';
                    }
                    else {

                        # write full http response
                        $self->_write_psgi_response( $h, $res, $keep_alive, 0 );

                        $self->_finish_request( $h, $keep_alive );
                    }

                    return;
                }
            );
        };

        if ($@) {
            warn $@;

            if ( !$headers_written ) {
                $self->_return_xxx( $h, 500 );
            }
            else {
                $self->_finish_request( $h, 0 );
            }
        }
    }
    else {
        $self->_return_xxx( $h, 500 );
    }

    return;
}

sub _return_xxx ( $self, $h, $status ) {
    my $reason = Pcore::HTTP::Status->get_reason($status);

    my $body = <<"HTML";
<html><head><title>$status $reason</title></head><body bgcolor="white"><center><h1>

$status $reason

</h1></center></body></html>
HTML

    $self->_write_psgi_response( $h, [ $status, [ 'Content-Type' => 'text/html; charset=utf-8' ], \$body ], 0, 0 );

    $self->_finish_request( $h, 0 );

    return;
}

sub _finish_request ( $self, $h, $keep_alive ) {
    $self->{_cv}->end;

    if ( !$h->destroyed ) {
        if ( !$keep_alive ) {
            $h->destroy;
        }
        else {
            state $destroy = sub ( $h, @ ) {
                $h->destroy;

                return;
            };

            $h->on_error($destroy);
            $h->on_eof($destroy);
            $h->on_read($destroy);
            $h->on_timeout(undef);
            $h->timeout_reset;
            $h->timeout($keep_alive);

            $self->_wait_request($h);
        }
    }

    return;
}

# TODO add support for different body types, body can be FileHandle or CodeRef or ScalarRef, etc ...
# TODO convert headers to CamelCase
sub _write_psgi_response ( $self, $h, $res, $keep_alive, $delayed_body ) {
    return if $h->destroyed;

    # compose headers
    # https://tools.ietf.org/html/rfc7230#section-3.2
    my $headers = do {
        if ( !ref $res->[0] ) {
            "HTTP/1.1 $res->[0] " . Pcore::HTTP::Status->get_reason( $res->[0] );
        }
        else {
            "HTTP/1.1 $res->[0]->[0] $res->[0]->[1]";
        }
    };

    $headers .= $CRLF . 'Server:' . $self->{server_signature} if $self->{server_signature};

    if ($keep_alive) {
        $headers .= $CRLF . 'Connection:Keep-Alive';
    }
    else {
        $headers .= $CRLF . 'Connection:close';
    }

    # TODO convert headers to CamelCase
    $headers .= $CRLF . join $CRLF, map {"$_->[0]:$_->[1]"} pairs $res->[1]->@* if $res->[1] && $res->[1]->@*;

    if ($delayed_body) {
        $self->_write_buf( $h, \( $headers . $CRLF . 'Transfer-Encoding:chunked' . $CRLF . $CRLF ) );
    }
    else {
        if ( $res->[2] ) {
            if ( ref $res->[2] eq 'SCALAR' ) {
                $self->_write_buf( $h, \( $headers . $CRLF . 'Content-Length: ' . length( $res->[2]->$* ) . $CRLF . $CRLF . $res->[2]->$* ) );
            }
            elsif ( ref $res->[2] eq 'ARRAY' ) {
                my $body = join q[], $res->[2]->@*;

                $self->_write_buf( $h, \( $headers . $CRLF . 'Content-Length: ' . length($body) . $CRLF . $CRLF . $body ) );
            }
            else {

                # TODO add support for other body types
                die q[Body type isn't supported];
            }
        }
        else {

            # no body
            $self->_write_buf( $h, \( $headers . $CRLF . $CRLF ) );
        }
    }

    return;
}

sub _write_buf ( $self, $h, $buf_ref ) {
    return if $h->destroyed;

    my $len = syswrite $h->{fh}, $buf_ref->$*;

    # fallback to more slower method in the case of error
    if ( !defined $len ) {
        $h->push_write( $buf_ref->$* );
    }
    elsif ( $len < length $buf_ref->$* ) {
        $h->push_write( substr $buf_ref->$*, $len );
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 107                  | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 131, 293             | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 195                  | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 59                   | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
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
