package Pcore::HTTP::Server::Writer;

use Pcore -class;
use Pcore::Util::List qw[pairs];

has server => ( is => 'ro', isa => InstanceOf ['Pcore::HTTP::Server'], required => 1, weak_ref => 1 );
has h      => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'],   required => 1, weak_ref => 1 );
has keep_alive => ( is => 'ro', isa => PositiveOrZeroInt, required => 1 );
has buf_size   => ( is => 'ro', isa => PositiveOrZeroInt, default  => 65_536 );

has buf => ( is => 'ro', isa => Str, default => q[], init_arg => undef );

# TODO finish request on destroy, if not destoroyed yet;
# TODO on exception - do not write last junk, just close socket;

# sub DEMOLISH ( $self, $global ) {
#     $self->close if !$global;
#
#     return;
# }

sub write ( $self, $data ) {    ## no critic qw[Subroutines::ProhibitBuiltinHomonyms]
    $self->{buf} .= ref $data ? $data->$* : $data;

    if ( length $self->{buf} >= $self->{buf_size} ) {
        $self->{server}->_write_buf( $self->{h}, \( sprintf( '%x', length $self->{buf} ) . $CRLF . $self->{buf} . $CRLF ) );

        $self->{buf} = q[];
    }

    return;
}

sub close ( $self, $trailing_headers = undef ) {    ## no critic qw[NamingConventions::ProhibitAmbiguousNames Subroutines::ProhibitBuiltinHomonyms]
    my $buf = q[];

    # add last buffer
    $buf = sprintf( '%x', length $self->{buf} ) . $CRLF . $self->{buf} . $CRLF if length $self->{buf};

    # add last chunk
    $buf .= "0$CRLF";

    # add trailing headers
    $buf .= ( join $CRLF, map {"$_->[0]:$_->[1]"} pairs $trailing_headers->@* ) . $CRLF if $trailing_headers && $trailing_headers->@*;

    $buf .= $CRLF;

    # write buffer
    $self->{server}->_write_buf( $self->{h}, \$buf );

    # funish request
    $self->{server}->_finish_request( $self->{h}, $self->{keep_alive} );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::HTTP::Server::Writer

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
