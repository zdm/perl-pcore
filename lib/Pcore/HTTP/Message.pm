package Pcore::HTTP::Message;

use Pcore -class;
use Pcore::HTTP::Message::Headers;

has status => ( is => 'ro', isa => PositiveInt, writer => 'set_status', default => 200 );
has headers => ( is => 'lazy', isa => InstanceOf ['Pcore::HTTP::Message::Headers'], init_arg => undef );
has body => ( is => 'ro', isa => Ref, writer => 'set_body', predicate => 1, init_arg => undef );
has path => ( is => 'ro', isa => Str, writer => 'set_path', predicate => 1, init_arg => undef );

has content_length => ( is => 'rwp', isa => PositiveOrZeroInt, default => 0, init_arg => undef );

has buf_size => ( is => 'ro', isa => PositiveOrZeroInt, default => 0 );    # write body to fh if body length > this value, 0 - always store in memory, 1 - always store to file

no Pcore;

sub BUILD {
    my $self = shift;
    my $args = shift;

    $self->headers->add( $args->{headers} ) if $args->{headers};

    $self->set_body( $args->{body} ) if $args->{body};

    return;
}

sub _build_headers ($self) {
    return Pcore::HTTP::Message::Headers->new;
}

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

# TODO
# body chunked if body is FH or FilePath, and size > $self->buf_size;
# body is multipart if has content parts with different content-types;
# universal response coderef;
sub body_to_http ($self) {
    return $self->body;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Message

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut
