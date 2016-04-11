package Pcore::HTTP::Response;

use Pcore -class;

extends qw[Pcore::HTTP::Message];
with qw[Pcore::HTTP::Status];

has url => ( is => 'ro', isa => Str | Object, writer => 'set_url' );
has version => ( is => 'ro', isa => Num, writer => 'set_version', init_arg => undef );

has redirect => ( is => 'lazy', isa => ArrayRef, default => sub { [] }, init_arg => undef );

# TO_PSGI
sub to_psgi ($self) {
    if ( $self->has_body && ref $self->body eq 'CODE' ) {
        return $self->body;
    }
    else {
        return [ $self->status, $self->headers->to_psgi, $self->_body_to_psgi ];
    }
}

# TODO
sub _body_to_psgi ($self) {
    return [];
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Response

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
