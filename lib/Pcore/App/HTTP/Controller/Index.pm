package Pcore::App::HTTP::Controller::Index;

use Pcore -role;

with qw[Pcore::App::HTTP::Controller];

around run => sub ( $orig, $self ) {
    if ( $self->path_tail->is_file ) {
        return $self->return_static;
    }
    else {
        return $self->$orig;
    }
};

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::HTTP::Controller::Index

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
