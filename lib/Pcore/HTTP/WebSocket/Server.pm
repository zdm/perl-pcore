package Pcore::HTTP::WebSocket::Server;

use Pcore -role;
use Pcore::HTTP::WebSocket::Util qw[:CONST];
use Pcore::Util::Scalar qw[refaddr];

requires qw[run websocket_can_accept websocket_on_close];

around run => sub ( $orig, $self ) {
    my $req = $self->req;

    # this is websocket connect request
    if ( $req->is_websocket_connect_request ) {
        my $env = $req->{env};

        # websocket version is not specified or not supported
        return $req->return_xxx( [ 400, q[Unsupported WebSocket version] ] ) if !$env->{HTTP_SEC_WEBSOCKET_VERSION} || $env->{HTTP_SEC_WEBSOCKET_VERSION} ne $WEBSOCKET_VERSION;

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

        my $websocket_can_accept = $self->websocket_can_accept;

        # websocket connect request can't be accepted
        return $req->return_xxx(400) if !$websocket_can_accept;

        # check and set extension
        if ( $env->{HTTP_SEC_WEBSOCKET_EXTENSIONS} ) {

            # set ext_permessage_deflate, only if enabled locally
            $self->{websocket_ext_permessage_deflate} = $self->{websocket_ext_permessage_deflate} && $env->{HTTP_SEC_WEBSOCKET_EXTENSIONS} =~ /\bpermessage-deflate\b/smi ? 1 : 0;
        }

        # create response headers
        my @headers = (    #
            'Sec-WebSocket-Accept' => Pcore::HTTP::WebSocket::Util::get_challenge( $env->{HTTP_SEC_WEBSOCKET_KEY} ),
            ( $websocket_protocol                       ? ( 'Sec-WebSocket-Protocol'   => $websocket_protocol )  : () ),
            ( $self->{websocket_ext_permessage_deflate} ? ( 'Sec-WebSocket-Extensions' => 'permessage-deflate' ) : () ),
        );

        # add custom headers
        push @headers, $websocket_can_accept->@* if ref $websocket_can_accept;

        # accept websocket connection
        $self->{websocket_h} = $req->accept_websocket( \@headers );

        # store websocket object in HTTP server cache, using refaddr as key
        $req->{_server}->{_websocket_cache}->{ refaddr $self} = $self;

        $self->websocket_listen;

        return;
    }

    # this is NOT websocket connect request
    else {
        return $self->$orig;
    }
};

around websocket_on_close => sub ( $orig, $self, $status ) {
    undef $self->req->{_server}->{_websocket_cache}->{ refaddr $self};

    $self->$orig($status);

    return;
};

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 26                   | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 93                   | Documentation::RequirePackageMatchesPodName - Pod NAME on line 97 does not match the package declaration       |
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
