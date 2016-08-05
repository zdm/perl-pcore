package Pcore::HTTP::WebSocket::Server;

use Pcore -role;

with qw[Pcore::HTTP::WebSocket::Base];

requires qw[websocket_can_accept];

sub websocket_on_accept ( $self, $req ) {
    my $req = $self->req;

    my $env = $req->{env};

    # this is websocket connect request
    if ( $req->is_websocket_connect_request ) {

        # websocket version is not specified or not supported
        return $req->return_xxx( [ 400, q[Unsupported WebSocket version] ] ) if !$env->{HTTP_SEC_WEBSOCKET_VERSION} || $env->{HTTP_SEC_WEBSOCKET_VERSION} ne $Pcore::HTTP::WebSocket::Base::WS_VERSION;

        # websocket key is not specified
        return $req->return_xxx( [ 400, q[WebSocket key is required] ] ) if !$env->{HTTP_SEC_WEBSOCKET_KEY};

        # check websocket subprotocol
        my $subprotocol = $self->subprotocol;

        if ( $env->{HTTP_SEC_WEBSOCKET_PROTOCOL} ) {
            return $req->return_xxx( [ 400, qq[Unsupported WebSocket subprotocol] ] ) if !$subprotocol || $env->{HTTP_SEC_WEBSOCKET_PROTOCOL} !~ /\b$subprotocol\b/smi;
        }
        elsif ($subprotocol) {
            return $req->return_xxx( [ 400, qq[WebSocket subprotocol should be "$subprotocol"] ] );
        }

        my $can_accept = $self->websocket_can_accept($env);

        # websocket connect request can't be accepted
        return $req->return_xxx(400) if !$can_accept;

        # check and set extension
        if ( $env->{HTTP_SEC_WEBSOCKET_EXTENSIONS} ) {
            $self->{ext_permessage_deflate} = 1 if $env->{HTTP_SEC_WEBSOCKET_EXTENSIONS} =~ /\bpermessage-deflate\b/smi;
        }

        # crealte supported extensions list
        my @extensions;
        push @extensions, 'permessage-deflate' if $self->ext_permessage_deflate;

        # create response headers
        my @headers = (    #
            'Sec-WebSocket-Accept:' . $self->get_challenge( $env->{HTTP_SEC_WEBSOCKET_KEY} ),
            ( $subprotocol ? "Sec-WebSocket-Protocol:$subprotocol" : () ),
            ( @extensions ? 'Sec-WebSocket-Extensions:' . join q[, ], @extensions : () ),
        );

        # add custom headers
        push @headers, $can_accept->@* if ref $can_accept;

        # accept websocket connection
        my $h = $req->accept_websocket( \@headers );

        # TODO create websocket object and store in HTTP server cache, using refaddr as key
        $req->{_server}->{_websocket_cache}->{ refaddr $self} = $self;

        $ws->listen;

        return;
    }

    # this is NOT websocket connect request
    else {
        return $req->return_xxx(400);
    }
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 27                   | ValuesAndExpressions::ProhibitInterpolationOfLiterals - Useless interpolation of literal string                |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 88                   | Documentation::RequirePackageMatchesPodName - Pod NAME on line 92 does not match the package declaration       |
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
