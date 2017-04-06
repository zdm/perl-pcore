package Pcore::WebSocket::Protocol::pcore;

use Pcore -class, -result, -const;
use Pcore::Util::Data qw[to_cbor from_cbor to_json from_json];
use Pcore::Util::UUID qw[uuid_str];
use Pcore::WebSocket::Protocol::pcore::Request;

has protocol => ( is => 'ro', isa => Str, default => 'pcore', init_arg => undef );

const our $TYPE_TEXT   => 1;
const our $TYPE_BINARY => 2;

# TODO geet default_type from headers
has default_type => ( is => 'ro', isa => Enum [ $TYPE_TEXT, $TYPE_BINARY ], default => $TYPE_TEXT );
has on_rpc_call => ( is => 'ro', isa => CodeRef );

# TODO implement scan_deps protocol, get scan_deps flag from headers
has scandeps => ( is => 'ro', isa => Bool, default => 0 );

has _listeners => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has _callbacks => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

with qw[Pcore::WebSocket::Handle];

const our $MSG_TYPE_LISTEN => 'listen';
const our $MSG_TYPE_EVENT  => 'event';
const our $MSG_TYPE_RPC    => 'rpc';

sub rpc_call ( $self, $method, @ ) {
    my $msg = {
        type   => $MSG_TYPE_RPC,
        method => $method,
    };

    if ( ref $_[-1] eq 'CODE' ) {
        $msg->{data} = [ @_[ 2 .. $#_ - 1 ] ];

        $msg->{tid} = uuid_str();

        $self->{_callbacks}->{ $msg->{tid} } = $_[-1];
    }
    else {
        $msg->{data} = [ @_[ 2 .. $#_ ] ];
    }

    if ( !$self->{default_type} || $self->{default_type} eq $TYPE_TEXT ) {
        $self->send_text( to_json $msg);
    }
    else {
        $self->send_binary( to_cbor $msg);
    }

    return;
}

sub forward_events ( $self, $events ) {
    $self->_set_listeners($events);

    return;
}

sub listen_events ( $self, $events ) {
    my $msg = {
        type   => $MSG_TYPE_LISTEN,
        events => $events,
    };

    if ( !$self->{default_type} || $self->{default_type} eq $TYPE_TEXT ) {
        $self->send_text( to_json $msg);
    }
    else {
        $self->send_binary( to_cbor $msg);
    }

    return;
}

sub fire_event ( $self, $event, $data = undef ) {
    my $msg = {
        type  => $MSG_TYPE_EVENT,
        event => $event,
        data  => $data,
    };

    if ( !$self->{default_type} || $self->{default_type} eq $TYPE_TEXT ) {
        $self->send_text( to_json $msg);
    }
    else {
        $self->send_binary( to_cbor $msg);
    }

    return;
}

sub on_connect ( $self ) {
    return;
}

sub on_disconnect ( $self, $status ) {

    # clear listeners
    $self->{_listeners} = {};

    # call pending callback
    for my $tid ( keys $self->{_callbacks}->%* ) {
        my $cb = delete $self->{_callbacks}->{$tid};

        $cb->( result [ $status->{status}, $status->{reason} ] );
    }

    return;
}

sub on_text ( $self, $data_ref ) {
    my $msg = eval { from_json $data_ref->$* };

    if ($@) {
        return;
    }

    $self->_on_message( $msg, $TYPE_TEXT );

    return;
}

sub on_binary ( $self, $data_ref ) {
    my $msg = eval { from_cbor $data_ref->$* };

    if ($@) {
        return;
    }

    $self->_on_message( $msg, $TYPE_BINARY );

    return;
}

sub on_pong ( $self, $data_ref ) {
    return;
}

sub _set_listeners ( $self, $events ) {
    $events = [$events] if ref $events ne 'ARRAY';

    for my $event ( $events->@* ) {
        next if exists $self->{_listeners}->{$event};

        $self->{_listeners}->{$event} = P->listen_events(
            $event,
            sub ( $event, $data ) {
                $self->fire_event( $event, $data );

                return;
            }
        );
    }

    return;
}

sub _on_message ( $self, $msg, $type ) {
    return if !$msg->{type};

    if ( $msg->{type} eq $MSG_TYPE_LISTEN ) {
        $self->_set_listeners( $msg->{events} );
    }
    elsif ( $msg->{type} eq $MSG_TYPE_EVENT ) {
        P->fire_event( $msg->{event}, $msg->{data} );
    }
    elsif ( $msg->{type} eq $MSG_TYPE_RPC ) {

        # method is specified, this is rpc call
        if ( $msg->{method} ) {
            if ( $self->{on_rpc_call} ) {
                my $req = bless { type => $type }, 'Pcore::WebSocket::Protocol::pcore::Request';

                # callback is required
                if ( $msg->{tid} ) {
                    $req->{_cb} = sub ($res) {
                        my $msg = {
                            type   => $MSG_TYPE_RPC,
                            tid    => $msg->{tid},
                            result => $res,
                        };

                        if ( $type eq $TYPE_TEXT ) {
                            $self->send_text( to_json $msg);
                        }
                        else {
                            $self->send_binary( to_cbor $msg);
                        }

                        return;
                    };
                }

                $self->{on_rpc_call}->( $req, $msg->{method}, $msg->{data} );
            }
        }

        # method is not specified, this is callback, tid is required
        elsif ( $msg->{tid} ) {
            if ( my $cb = delete $self->{_callbacks}->{ $msg->{tid} } ) {

                # convert result to response object
                $cb->( bless $msg->{result}, 'Pcore::Util::Result' );
            }
        }
    }

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::WebSocket::Protocol::pcore

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
