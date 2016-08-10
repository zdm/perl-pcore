package Pcore::HTTP::Server;

use Pcore -class;
use Pcore::AE::Handle;
use AnyEvent::Socket qw[];
use Pcore::HTTP::Status;
use Pcore::HTTP::Server::Request;
use Socket qw[IPPROTO_TCP TCP_NODELAY];

has listen => ( is => 'ro', isa => Str, required => 1 );
has app => ( is => 'ro', isa => CodeRef | ConsumerOf ['Pcore::HTTP::Server::Router'], required => 1 );

has backlog => ( is => 'ro', isa => Maybe [PositiveOrZeroInt], default => 0 );
has tcp_no_delay => ( is => 'ro', isa => Bool, default => 0 );

has server_tokens => ( is => 'ro', isa => Maybe [Str], default => "Pcore-HTTP-Server/$Pcore::VERSION" );
has keepalive_timeout     => ( is => 'ro', isa => PositiveOrZeroInt, default => 60 );    # 0 - disable keepalive
has client_header_timeout => ( is => 'ro', isa => PositiveInt,       default => 60 );
has client_body_timeout   => ( is => 'ro', isa => PositiveInt,       default => 60 );

has _listen_uri => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::URI'], init_arg => undef );
has _listen_socket => ( is => 'lazy', isa => Object, init_arg => undef );

# TODO implement shutdown and graceful shutdown

sub run ($self) {
    $self->_listen_socket;

    return $self;
}

sub _build__listen_uri ($self) {
    return P->uri( $self->listen, authority => 1, base => 'tcp:' );
}

sub _build__listen_socket ($self) {
    if ( $self->_listen_uri->scheme eq 'unix' ) {
        my $server = AnyEvent::Socket::tcp_server( 'unix/', $self->_listen_uri->path, sub { return $self->_on_accept(@_) }, sub { return $self->_on_prepare(@_) } );

        chmod oct 777, $self->_listen_uri->path or die;

        return $server;
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

            $self->wait_headers($h);

            return;
        }
    );

    return;
}

# TODO implement content length - https://www.w3.org/Protocols/rfc2616/rfc2616-sec4.html#sec4.4
sub _read_body ( $self, $h, $env, $cb ) {
    my ( $chunked, $content_length ) = ( 0, 0 );

    if ( $env->{TRANSFER_ENCODING} && $env->{TRANSFER_ENCODING} =~ /\bchunked\b/smi ) {
        $chunked = 1;
    }
    elsif ( $env->{CONTENT_LENGTH} ) {
        $content_length = $env->{CONTENT_LENGTH};
    }
    else {

        # no body
        $cb->(undef);

        return;
    }

    $h->timeout( $self->{client_body_timeout} );

    $h->on_timeout(
        sub {

            # read body timeout
            $cb->(408);
        }
    );

    $h->read_http_body(
        sub ( $h1, $buf_ref, $total_bytes_readed, $error_message ) {
            if ($error_message) {

                # read body error
                $cb->(400);
            }
            else {
                if ( !$buf_ref ) {
                    $h->timeout(undef);

                    $h->on_timeout(undef);

                    $cb->(undef);
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

sub wait_headers ( $self, $h ) {
    state $destroy = sub ( $h, @ ) {
        $h->destroy;

        return;
    };

    $h->timeout_reset;
    $h->on_error($destroy);
    $h->on_eof(undef);
    $h->on_timeout(undef);

    # set keep-alive timeout or drop timeout
    $h->timeout( $self->{keepalive_timeout} || undef );

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

    $h->on_read(
        sub ($h1) {

            # clear on_read
            $h->on_read(undef);

            # set client header timeout
            $h->timeout( $self->{client_header_timeout} );

            # set client header timeout handler
            $h->on_timeout(
                sub ( $h, @ ) {

                    # client header timeout
                    # return standard error response and destroy handle
                    # 408 - Request Timeout
                    $self->return_xxx( $h, 408 );

                    return;
                }
            );

            $h->read_http_req_headers(
                sub ( $h1, $env, $error ) {
                    if ($error) {

                        # HTTP headers parsing error, request is invalid
                        # return standard error response and destroy handle
                        # 400 - Bad Request
                        $self->return_xxx( $h, 400 );
                    }
                    else {

                        # clear client header timeout
                        $h->timeout(undef);

                        # create env
                        $env->@{ keys $psgi_env->%* } = values $psgi_env->%*;

                        $self->_read_body(
                            $h, $env,
                            sub ($body_error_status) {
                                if ($body_error_status) {

                                    # body read error
                                    $self->return_xxx( $h, $body_error_status );
                                }
                                else {

                                    # create request object
                                    my $req = bless {
                                        _server          => $self,
                                        _h               => $h,
                                        env              => $env,
                                        _response_status => 0,
                                      },
                                      'Pcore::HTTP::Server::Request';

                                    # evaluate application
                                    eval { $self->{app}->($req) };

                                    $@->sendlog if $@;
                                }

                                return;
                            }
                        );
                    }

                    return;
                }
            );

            return;
        }
    );

    return;
}

sub return_xxx ( $self, $h, $status, $use_keepalive = 0 ) {
    my $reason;

    if ( !ref $status ) {
        $reason = Pcore::HTTP::Status->get_reason($status);
    }
    else {
        $reason = $status->[1];

        $status = $status->[0];
    }

    my @headers = (    #
        "HTTP/1.1 $status $reason",
        'Content-Length:0',
        ( $self->{server_tokens} ? "Server:$self->{server_tokens}" : () ),
        ( $use_keepalive         ? 'Connection:keep-alive'         : 'Connection:close' ),
    );

    $h->push_write( join( $CRLF, @headers ) . $CRLF . $CRLF );

    # process handle
    if   ($use_keepalive) { $self->wait_headers($h) }
    else                  { $h->destroy }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 205                  | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 227                  | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 57                   | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
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
