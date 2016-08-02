package Pcore::App::Controller::WebSocket;

use Pcore -role;

with qw[Pcore::App::Controller];

sub run ($self) {
    my $h = $self->req->accept_websocket;

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
