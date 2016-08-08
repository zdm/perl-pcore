package Pcore::HTTP::WebSocket::Server;

use Pcore -role;
use Pcore::Util::Scalar qw[refaddr];

requires qw[run websocket_on_accept websocket_on_close];

# this parameter should be less, than nginx "proxy_read_timeout" in nginx
has websocket_autoping => ( is => 'ro', isa => PositiveOrZeroInt, default => 30 );    # 0 - do not ping on timeout

around run => sub ( $orig, $self ) {
    my $req = $self->req;

    # this is websocket connect request
    if ( $req->is_websocket_connect_request ) {
        my $env = $req->{env};

        # websocket version is not specified or not supported
        return $req->return_xxx( [ 400, q[Unsupported WebSocket version] ] ) if !$env->{HTTP_SEC_WEBSOCKET_VERSION} || $env->{HTTP_SEC_WEBSOCKET_VERSION} ne $Pcore::HTTP::WebSocket::Protocol::WEBSOCKET_VERSION;

        # websocket key is not specified
        return $req->return_xxx( [ 400, q[WebSocket key is required] ] ) if !$env->{HTTP_SEC_WEBSOCKET_KEY};

        # check websocket subprotocol
        my $websocket_protocol = $self->websocket_protocol;

        if ( $env->{HTTP_SEC_WEBSOCKET_PROTOCOL} ) {
            return $req->return_xxx( [ 400, qq[Unsupported WebSocket protocol] ] ) if !$websocket_protocol || $env->{HTTP_SEC_WEBSOCKET_PROTOCOL} !~ /\b$websocket_protocol\b/smi;
        }
        elsif ($websocket_protocol) {
            return $req->return_xxx( [ 400, qq[WebSocket subprotocol should be "$websocket_protocol"] ] );
        }

        my ( $websocket_accept, $accept_headers ) = $self->websocket_on_accept;

        # websocket connect request can't be accepted
        return $req->return_xxx( $accept_headers // 400 ) if !$websocket_accept;

        # check and set extension
        if ( $env->{HTTP_SEC_WEBSOCKET_EXTENSIONS} ) {

            # set ext_permessage_deflate, only if enabled locally
            $self->{websocket_permessage_deflate} = $self->{websocket_permessage_deflate} && $env->{HTTP_SEC_WEBSOCKET_EXTENSIONS} =~ /\bpermessage-deflate\b/smi ? 1 : 0;
        }

        # create response headers
        my @headers = (    #
            'Sec-WebSocket-Accept' => $self->websocket_challenge( $env->{HTTP_SEC_WEBSOCKET_KEY} ),
            ( $websocket_protocol                   ? ( 'Sec-WebSocket-Protocol'   => $websocket_protocol )  : () ),
            ( $self->{websocket_permessage_deflate} ? ( 'Sec-WebSocket-Extensions' => 'permessage-deflate' ) : () ),
        );

        # add custom headers
        push @headers, $accept_headers->@* if $accept_headers;

        # accept websocket connection
        $self->{_websocket_h} = $req->accept_websocket( \@headers );

        # store websocket object in HTTP server cache, using refaddr as key
        $req->{_server}->{_websocket_cache}->{ refaddr $self} = $self;

        # init autoping
        $self->websocket_start_autoping( $self->{websocket_autoping} ) if $self->{websocket_autoping};

        $self->websocket_listen;

        return;
    }

    # this is NOT websocket connect request
    else {
        return $self->$orig;
    }
};

around websocket_on_close => sub ( $orig, $self, $status, $reason ) {
    undef $self->req->{_server}->{_websocket_cache}->{ refaddr $self};

    $self->$orig( $status, $reason );

    return;
};

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 28                   | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 98                   | Documentation::RequirePackageMatchesPodName - Pod NAME on line 102 does not match the package declaration      |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME



=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
