package Pcore::HTTP::Server::Request;

use Pcore -class, -const;
use Pcore::HTTP::Status;
use Pcore::Util::List qw[pairs];

has _server => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::Server'], required => 1 );
has _h      => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'],   required => 1 );
has env => ( is => 'ro', isa => HashRef, required => 1 );

has _keepalive_timeout => ( is => 'lazy', isa => PositiveOrZeroInt, init_arg => undef );
has has_body => ( is => 'lazy', isa => Bool, init_arg => undef );

has _response_status => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

const our $HTTP_SERVER_RESPONSE_STARTED  => 1;    # headers written
const our $HTTP_SERVER_RESPONSE_FINISHED => 2;

P->init_demolish(__PACKAGE__);

sub DEMOLISH ( $self, $global ) {
    if ( !$global && $self->{_response_status} != $HTTP_SERVER_RESPONSE_FINISHED ) {

        # request is destroyed without ->finish call, possible unhandled error in AE callback
        $self->{_server}->return_xxx( $self->{_h}, 500 );
    }

    return;
}

sub _build__keepalive_timeout($self) {
    my $keepalive_timeout = $self->{_server}->{keepalive_timeout};

    if ($keepalive_timeout) {
        my $env = $self->{env};

        if ( $env->{SERVER_PROTOCOL} eq 'HTTP/1.1' ) {
            $keepalive_timeout = 0 if $env->{HTTP_CONNECTION} && $env->{HTTP_CONNECTION} =~ /\bclose\b/smi;
        }
        elsif ( $env->{SERVER_PROTOCOL} eq 'HTTP/1.0' ) {
            $keepalive_timeout = 0 if !$env->{HTTP_CONNECTION} || $env->{HTTP_CONNECTION} !~ /\bkeep-?alive\b/smi;
        }
        else {
            $keepalive_timeout = 0;
        }
    }

    return $keepalive_timeout;
}

sub _build_has_body ($self) {
    my $env = $self->{env};

    if ( $env->{TRANSFER_ENCODING} && $env->{TRANSFER_ENCODING} =~ /\bchunked\b/smi ) {
        return 1;
    }
    elsif ( $env->{CONTENT_LENGTH} ) {
        return 1;
    }

    return 0;
}

# TODO convert headers to Camel-Case
# TODO encode body
# TODO serialize body related to body ref type and content type
sub write ( $self, @ ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    die q[Unable to write, HTTP response already finished] if $self->{_response_status} == $HTTP_SERVER_RESPONSE_FINISHED;

    my $body;

    if ( !$self->{_response_status} ) {

        # compose headers
        # https://tools.ietf.org/html/rfc7230#section-3.2
        my $headers = do {
            if ( !ref $_[1] ) {
                "HTTP/1.1 $_[1] " . Pcore::HTTP::Status->get_reason( $_[1] ) . $CRLF;
            }
            else {
                "HTTP/1.1 $_[1]->[0] $_[1]->[1]$CRLF";
            }
        };

        $headers .= "Server:$self->{_server}->{server_tokens}$CRLF" if $self->{server_tokens};

        # always use chunked transfer
        $headers .= "Transfer-Encoding:chunked$CRLF";

        if ( $self->_keepalive_timeout ) {
            $headers .= "Connection:keep-alive$CRLF";
        }
        else {
            $headers .= "Connection:close$CRLF";
        }

        # TODO convert headers to Camel-Case
        $headers .= join( $CRLF, map {"$_->[0]:$_->[1]"} pairs $_[2]->@* ) . $CRLF if $_[2] && $_[2]->@*;

        $headers .= $CRLF;

        $self->{_h}->push_write($headers);

        \$body = \$_[3] if $_[3];

        $self->{_response_status} = $HTTP_SERVER_RESPONSE_STARTED;
    }
    else {
        \$body = \$_[1];
    }

    if ($body) {
        my $body_ref = ref $body;

        if ( !$body_ref ) {
            $self->{_h}->push_write( sprintf( '%x', bytes::length $body ) . $CRLF . $body . $CRLF );
        }
        elsif ( $body_ref eq 'SCALAR' ) {
            $self->{_h}->push_write( sprintf( '%x', bytes::length $body->$* ) . $CRLF . $body->$* . $CRLF );
        }
        elsif ( $body_ref eq 'ARRAY' ) {
            my $buf = join q[], $body->@*;

            $self->{_h}->push_write( sprintf( '%x', bytes::length $buf ) . $CRLF . $buf . $CRLF );
        }
        else {

            # TODO add support for other body types
            die q[Body type isn't supported];
        }
    }

    return $self;
}

sub finish ( $self, $trailing_headers = undef ) {
    if ( $self->{_response_status} == $HTTP_SERVER_RESPONSE_FINISHED ) {
        die q[Unable to finish HTTP response, already finished];
    }
    else {
        my $buf;

        my $keepalive_timeout = $self->_keepalive_timeout;

        if ( !$self->{_response_status} ) {

            # return 204 No Content - The server successfully processed the request and is not returning any content
            state $return_204 = "HTTP/1.1 204 @{[Pcore::HTTP::Status->get_reason( 204 )]}${CRLF}Content-Length:0$CRLF" . ( $self->{server_tokens} ? "Server:$self->{_server}->{server_tokens}$CRLF" : q[] );

            $buf = $return_204;

            if ($keepalive_timeout) {
                $buf .= "Connection:keep-alive$CRLF";
            }
            else {
                $buf .= "Connection:close$CRLF";
            }
        }
        else {

            # write last chunk
            $buf = "0$CRLF";

            # write trailing headers
            # https://tools.ietf.org/html/rfc7230#section-3.2
            $buf .= ( join $CRLF, map {"$_->[0]:$_->[1]"} pairs $trailing_headers->@* ) . $CRLF if $trailing_headers && $trailing_headers->@*;
        }

        # close response
        $buf .= $CRLF;

        $self->{_response_status} = $HTTP_SERVER_RESPONSE_FINISHED;

        $self->{_h}->push_write($buf);

        if ( $self->has_body || !$keepalive_timeout ) {
            $self->{_h}->destroy;
        }
        else {

            # keepalive
            $self->{_server}->wait_headers( $self->{_h} );
        }

        undef $self->{_h};
    }

    return;
}

# -----------------------------------------------------------------

# TODO control read timeout, return status 408 - Request timeout
# TODO control max body size, return 413 - Request Entity Too Large
sub _read_body ( $self, $h, $env, $chunked, $content_length ) {
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

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 195                  | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 195                  | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_read_body' declared but not used   |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Server::Request

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
