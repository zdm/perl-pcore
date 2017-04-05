package Pcore::Websocket::Protocol::pcore;

use Pcore -class, -result;

has protocol => ( is => 'ro', isa => Str, default => 'pcore', init_arg => undef );

has on_rpc_call => ( is => 'ro', isa => CodeRef );

has _listeners => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has _callbacks => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

with qw[Pcore::WebSocket::Handle];

sub listen_event ( $self, $keys ) {
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
    return;
}

sub on_binary ( $self, $data_ref ) {
    return;
}

sub on_pong ( $self, $data_ref ) {
    return;
}

sub _on_rpc_call ($self) {
    if ( $self->{on_rpc_call} ) {
        $self->{on_rpc_call}->();
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
## |    3 | 49                   | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_on_rpc_call' declared but not used |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Websocket::Protocol::pcore

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
