package Pcore::App::HTTP::Controller::Static;

use Pcore -role;

with qw[Pcore::App::HTTP::Controller];

sub run ($self) {
    return $self->return_static;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::HTTP::Controller::Static

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
