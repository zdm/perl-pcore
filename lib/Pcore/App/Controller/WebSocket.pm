package Pcore::App::Controller::WebSocket;

use Pcore -role;
use Pcore::Util::Scalar qw[refaddr];
use Pcore::HTTP::WebSocket;
use Digest::SHA1 qw[];

requires qw[run];

# ' WebSocket-Origin '     => ' http : // 127.0.0.1 : 80 / ',
# ' WebSocket-Location '   => ' ws   : // 127.0.0.1 : 80 / websocket /',

# $buf .= 'Sec-WebSocket-Accept:' . P->data->to_b64( Digest::SHA1::sha1( ( $self->env->{HTTP_SEC_WEBSOCKET_KEY} || q[] ) . $WS_GUID ), q[] ) . $CRLF;

around run => sub ( $orig, $self ) {
    my $req = $self->req;

    my $env = $req->{env};

    if ( $env->{HTTP_UPGRADE} =~ /websocket/smi && $env->{HTTP_CONNECTION} =~ /\bupgrade\b/smi ) {

        # websocket version is not specified or not supported
        return $req->return_xxx(400) if !$env->{HTTP_SEC_WEBSOCKET_VERSION} || $env->{HTTP_SEC_WEBSOCKET_VERSION} ne $Pcore::HTTP::WebSocket::WS_VERSION;

        # websocket key is not specified
        return $req->return_xxx(400) if !$env->{HTTP_SEC_WEBSOCKET_KEY};

        # TODO check websocket subprotocol
        # $env->{HTTP_SEC_WEBSOCKET_PROTOCOL}

        my $can_connect = $self->ws_on_connect($env);

        return $req->return_xxx(400) if !$can_connect;

        # HTTP_SEC_WEBSOCKET_EXTENSIONS -> permessage-deflate
        # HTTP_SEC_WEBSOCKET_KEY
        # HTTP_SEC_WEBSOCKET_VERSION -> 13

        # TODO create websocket object and store in HTTP server cache, using refaddr as key
        my $ws = $self;

        $self->{_server}->{_websocket_cache}->{ refaddr $ws} = $ws;

        $ws->listen;
    }
    else {

        # this is not websocket connect request, fallback to original controller run method
        $self->$orig;
    }

    return;
};

sub ws_on_connect ( $self, $env ) {

    # TODO check other params, return 1 or 0

    return 1;
}

sub run1 ($self) {
    my $ws = Pcore::HTTP::WebSocket->new(
        {   h       => $self->req->accept_websocket,
            on_text => sub ($data_ref) {
                $self->on_text($data_ref);

                return;
            },
            on_bin => sub ($data_ref) {
                $self->on_bin($data_ref);

                return;
            },
            on_close => sub ($status) {
                $self->on_close($status);

                return;
            }
        }
    )->listen;

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::Controller::WebSocket

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
