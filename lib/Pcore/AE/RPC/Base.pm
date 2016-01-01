package Pcore::AE::RPC::Base;

use Pcore -role;
use Pcore::AE::Handle;

has pkg => ( is => 'ro', isa => Str, required => 1 );

has in  => ( is => 'ro', isa => Object, init_arg => undef );
has out => ( is => 'ro', isa => Object, init_arg => undef );

sub start_listen ( $self, $cb ) {
    $self->in->on_read(
        sub ($h) {
            $h->unshift_read(
                chunk => 4,
                sub ( $h, $data ) {
                    my $len = unpack 'L>', $data;

                    $h->unshift_read(
                        chunk => $len,
                        sub ( $h, $data ) {
                            $cb->( P->data->from_cbor($data) );

                            return;
                        }
                    );

                    return;
                }
            );

            return;
        }
    );

    return;
}

sub write_data ( $self, $data ) {
    $data = P->data->to_cbor($data);

    $self->out->push_write( pack( 'L>', bytes::length $data->$* ) . $data->$* );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::AE::RPC::Base

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
