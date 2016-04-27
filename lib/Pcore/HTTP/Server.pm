package Pcore::HTTP::Server;

use Pcore -class;
use Pcore::AE::Handle;
use AnyEvent::Socket qw[];
use Pcore::Util::List qw[pairs];
use Pcore::HTTP::Status;
use Socket qw[IPPROTO_TCP TCP_NODELAY];
use Pcore::HTTP::Server::Reader;
use Pcore::HTTP::Server::Writer;

has listen => ( is => 'ro', isa => Str,     required => 1 );
has app    => ( is => 'ro', isa => CodeRef, required => 1 );

has backlog      => ( is => 'ro', isa => PositiveOrZeroInt, default => 0 );
has tcp_no_delay => ( is => 'ro', isa => Bool,              default => 0 );
has keep_alive   => ( is => 'ro', isa => PositiveOrZeroInt, default => 4 );
has server_signature => ( is => 'ro', isa => Maybe [Str], default => "Pcore-HTTP-Server/$Pcore::VERSION" );

has _listen_uri => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::URI'], init_arg => undef );
has _cv => ( is => 'lazy', isa => Object, default => sub {AE::cv}, init_arg => undef );
has _listen_socket => ( is => 'lazy', isa => Object, init_arg => undef );

sub BUILD ( $self, $args ) {
    $self->_listen_socket;

    return;
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
    say 'HTTP server listen on ' . $self->_listen_uri->to_string;

    return $self->backlog;
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
        'psgix.input.buffered'  => 0,
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
                $self->_return_xxx( 400, $error );
            }
            else {
                $self->_cv->begin;

                $env->@{ keys $psgi_env->%* } = values $psgi_env->%*;

                $self->_run_app( $h, $env );
            }

            return;
        }
    );

    return;
}

# TODO content length - https://www.w3.org/Protocols/rfc2616/rfc2616-sec4.html#sec4.4
sub _run_app ( $self, $h, $env ) {

    # create psgi.input reader
    my $psgi_input;

    if ( $env->{CONTENT_LENGTH} ) {
        $psgi_input = bless {
            server         => $self,
            h              => $h,
            chunked        => 0,
            content_length => $env->{CONTENT_LENGTH},
            has_data       => 1,
          },
          'Pcore::HTTP::Server::Reader';
    }
    elsif ( $env->{TRANSFER_ENCODING} && $env->{TRANSFER_ENCODING} =~ /\bchunked\b/smio ) {
        $psgi_input = bless {
            server         => $self,
            h              => $h,
            chunked        => 1,
            content_length => 0,
            has_data       => 1,
          },
          'Pcore::HTTP::Server::Reader';
    }
    else {
        $psgi_input = bless {
            server         => $self,
            h              => $h,
            chunked        => 0,
            content_length => 0,
            has_data       => 0,
          },
          'Pcore::HTTP::Server::Reader';
    }

    $env->{'psgi.input'} = $psgi_input;

    # evaluate application
    my $res = eval { $self->app->($env) };

    # detect keep-alive
    my $keep_alive = $self->keep_alive;

    if ($keep_alive) {
        if ( $env->{SERVER_PROTOCOL} eq 'HTTP/1.1' ) {
            $keep_alive = 0 if $env->{HTTP_CONNECTION} && $env->{HTTP_CONNECTION} =~ /\bclose\b/smio;
        }
        elsif ( $env->{SERVER_PROTOCOL} eq 'HTTP/1.0' ) {
            $keep_alive = 0 if !$env->{HTTP_CONNECTION} || $env->{HTTP_CONNECTION} !~ /\bkeep-?alive\b/smio;
        }
        else {
            $keep_alive = 0;
        }
    }

    # processing first psgi app response
    if ($@) {
        $self->_return_xxx(500);
    }
    elsif ( ref $res eq 'ARRAY' ) {
        $self->_write_psgi_response( $h, $res, $keep_alive );

        $self->_finish_request( $h, $keep_alive, $psgi_input );
    }
    elsif ( ref $res eq 'CODE' ) {
        eval {
            $res->(
                sub ($res) {
                    $self->_write_psgi_response( $h, $res, $keep_alive );

                    if ( defined wantarray && !$res->[2] ) {
                        return bless {
                            server     => $self,
                            h          => $h,
                            keep_alive => $keep_alive,
                            psgi_input => $psgi_input,
                          },
                          'Pcore::HTTP::Server::Writer';
                    }
                    else {
                        $self->_finish_request( $h, $keep_alive, $psgi_input );
                    }

                    return;
                }
            );
        };

        $self->_return_xxx(500) if $@;
    }
    else {
        $self->_return_xxx(500);
    }

    return;
}

sub _return_xxx ( $self, $h, $status, $reason = undef ) {
    $self->_write_psgi_response( $h, [$status], 0 );

    $self->_finish_request( $h, 0, undef );

    return;
}

sub _finish_request ( $self, $h, $keep_alive, $psgi_input ) {
    $self->_cv->end;

    if ( !$keep_alive ) {
        $h->destroy;
    }
    elsif ( $psgi_input->{has_data} ) {
        $h->destroy;
    }
    else {
        my $destroy = sub ( $h, @ ) {
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

    return;
}

# TODO add support for different body types, body can be FileHandle or CodeRef or ScalarRef, etc ...
sub _write_psgi_response ( $self, $h, $res, $keep_alive ) {
    my $reason = $Pcore::HTTP::Status::STATUS_REASON->{ $res->[0] } // 'Unknown reason';

    my $headers = "HTTP/1.1 $res->[0] $reason";

    $headers .= $CRLF . 'Transfer-Encoding: chunked';

    $headers .= $CRLF . 'Server: ' . $self->{server_signature} if $self->{server_signature};

    if ($keep_alive) {
        $headers .= $CRLF . 'Connection: Keep-Alive';
    }
    else {
        $headers .= $CRLF . 'Connection: close';
    }

    $headers .= $CRLF . join map { $_->key . q[: ] . $_->value } pairs $res->[1]->@* if $res->[1] && $res->[1]->@*;

    $headers .= $CRLF x 2;

    if ( $res->[2] ) {
        if ( ref $res->[2] eq 'ARRAY' ) {
            my $body = join q[], $res->[2]->@*;

            $h->push_write( $headers . sprintf( '%x', length $body ) . $CRLF . $body . $CRLF . 0 . $CRLF . $CRLF );
        }
        else {
            die q[Body type isn't supported];
        }
    }
    else {

        $h->push_write($headers);
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
## |    3 | 101                  | References::ProhibitDoubleSigils - Double-sigil dereference                                                    |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 114                  | Subroutines::ProhibitExcessComplexity - Subroutine "_run_app" with high complexity score (21)                  |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 180                  | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 220                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 274                  | ValuesAndExpressions::ProhibitMismatchedOperators - Mismatched operator                                        |
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
