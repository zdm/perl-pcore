package Pcore::Handle::File;

use Pcore -class;
use IO::File;

with qw[Pcore::Core::H::Role::Wrapper];

has '+h_disconnect_on' => ( isa => Enum [ 'BEFORE_FORK', 'REQ_FINISH' ], default => 'BEFORE_FORK' );
has path      => ( is => 'ro', isa => Str,  required => 1 );
has binmode   => ( is => 'ro', isa => Str,  default  => ':raw' );
has autoflush => ( is => 'ro', isa => Bool, default  => 1 );

# H
sub h_connect {
    my $self = shift;

    my $h = IO::File->new( $self->path, '>>', P->file->calc_chmod(q[rw-------]) ) or die q[Unable to open "] . $self->path . q["];

    $h->binmode( $self->binmode );

    $h->autoflush( $self->autoflush );

    return $h;
}

sub h_disconnect {
    my $self = shift;

    $self->h->close;

    return;
}

1;
__END__
=pod

=encoding utf8

=cut
