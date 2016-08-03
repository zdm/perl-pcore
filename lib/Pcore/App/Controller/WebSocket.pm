package Pcore::App::Controller::WebSocket;

use Pcore -role;
use Pcore::HTTP::WebSocket;

with qw[Pcore::App::Controller];

sub run ($self) {
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
