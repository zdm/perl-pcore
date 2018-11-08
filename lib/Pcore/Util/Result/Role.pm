package Pcore::Util::Result::Role;

use Pcore -role, -const;
use Pcore::Util::Scalar qw[is_ref is_plain_arrayref is_plain_hashref];
use overload
  bool     => sub { substr( $_[0]->{status}, 0, 1 ) == 2 },
  '0+'     => sub { $_[0]->{status} },
  q[""]    => sub {"$_[0]->{status} $_[0]->{reason}"},
  fallback => 1;

has status => ();
has reason => ();

sub IS_PCORE_RESULT ($self) { return 1 }

sub BUILDARGS ( $self, $args ) { return $args }

around BUILDARGS => sub ( $orig, $self, $args ) {
    $args->{status} //= 0;

    if ( is_plain_arrayref $args->{status} ) {
        if ( is_plain_hashref $args->{status}->[1] ) {
            $args->{reason} //= Pcore::Util::Result::resolve_reason( $args->{status}->[0], $args->{status}->[1] );
        }
        else {
            $args->{reason} //= $args->{status}->[1] // Pcore::Util::Result::resolve_reason( $args->{status}->[0], $args->{status}->[2] );
        }

        $args->{status} = $args->{status}->[0];
    }
    elsif ( !defined $args->{reason} ) {
        $args->{reason} = Pcore::Util::Result::resolve_reason( $args->{status} );
    }

    return $self->$orig($args);
};

# $status, $reason;
# $status, $status_reason;
# $status, $reason, $status_reason;
sub set_status ( $self, $status, @ ) {
    if ( is_plain_arrayref $status ) {
        $self->{status} = $status->[0];

        if ( is_plain_arrayref $_[2] ) {

            # $status_reason = $_[2];
        }

        my $reason;

        # elsif () {

        # }

        $self->{reason} = $reason // $status->[1] // Pcore::Util::Result::resolve_reason( $status->[0] );
    }
    else {
        $self->{status} = $status;

        if ( is_plain_hashref $_[2] ) {
            $self->{reason} = Pcore::Util::Result::resolve_reason( $status, $_[2] );
        }
        else {
            $self->{reason} = $_[2] // Pcore::Util::Result::resolve_reason( $status, $_[3] );
        }
    }

    return;
}

# STATUS METHODS
sub is_info ($self) { return substr( $_[0]->{status}, 0, 1 ) == 1 }

sub is_success ($self) { return substr( $_[0]->{status}, 0, 1 ) == 2 }

sub is_redirect ($self) { return substr( $_[0]->{status}, 0, 1 ) == 3 }

sub is_error ($self) { return substr( $_[0]->{status}, 0, 1 ) >= 4 }

sub is_client_error ($self) { return substr( $_[0]->{status}, 0, 1 ) == 4 }

sub is_server_error ($self) { return substr( $_[0]->{status}, 0, 1 ) >= 5 }

# SERIALIZE
*TO_JSON = *TO_CBOR = sub ($self) { return { $_[0]->%* } };

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::Result::Role

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
