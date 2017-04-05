package Pcore::RPC::Connection;

use Pcore -class;
use Pcore::Util::Scalar qw[refaddr];
use Pcore::Util::Data qw[to_cbor from_json from_cbor];

has ws_protocol           => ( is => 'ro', isa => Str,  default => 'pcore', init_arg => undef );
has ws_permessage_deflate => ( is => 'ro', isa => Bool, default => 0,       init_arg => undef );
has ws_max_message_size => ( is => 'ro', isa => PositiveInt, default => 1_024 * 1_024 * 100, init_arg => undef );    # 100 Mb
has ws_autopong => ( is => 'ro', isa => PositiveOrZeroInt, default => 0, init_arg => undef );                        # auto pong timeout in seconds

with qw[Pcore::HTTP::WebSocket::Server];

has ws_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

sub run ( $self, $req ) {
    $req->return_xxx(400);

    return;
}

sub ws_on_accept ( $self, $ws, $req, $accept, $decline ) {
    $accept->();

    return;
}

sub ws_on_connect ( $self, $ws ) {
    $self->{ws_cache}->{ refaddr $ws} = $ws;

    return;
}

sub ws_on_disconnect ( $self, $ws, $status, $reason ) {
    delete $self->{ws_cache}->{ refaddr $ws};

    return;
}

sub ws_on_text ( $self, $ws, $data_ref ) {
    my $data = from_json $data_ref->$*;

    if ( $data->{type} eq 'listen' ) {
        for my $key ( $data->{data}->@* ) {
            my $listener = P->listen_event(
                $key,
                sub ( $key, $data = undef ) {
                    $ws->send_text(
                        P->data->to_json(
                            {   type => 'event',
                                data => {
                                    key  => $key,
                                    data => $data,
                                },
                            }
                        )->$*
                    );

                    return;
                }
            );

            push $ws->{event_listeners}->@*, $listener;
        }
    }
    elsif ( $data->{type} eq 'event' ) {
        P->fire_event( $data->{data}->{key}, $data->{data}->{data} );
    }

    return;
}

sub ws_on_binary ( $self, $ws, $data_ref ) {
    return;
}

sub ws_on_pong ( $self, $ws, $data_ref = undef ) {
    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::RPC::Connection

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
