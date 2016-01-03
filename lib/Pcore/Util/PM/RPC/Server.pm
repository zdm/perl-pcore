package Pcore::Util::PM::RPC::Server;

use Pcore -role;

has cv  => ( is => 'ro', isa => InstanceOf ['AnyEvent::CondVar'], required => 1 );
has in  => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'], required => 1 );
has out => ( is => 'ro', isa => InstanceOf ['Pcore::AE::Handle'], required => 1 );
has scan_deps => ( is => 'ro', isa => Bool, required => 1 );

sub BUILD ( $self, $args ) {
    my $deps = {};

    $self->_start_listen(
        sub ($req) {
            my $call_id = $req->[0];

            my $method = $req->[1];

            $self->$method(
                sub ($res = undef) {

                    # make PAR deps snapshot after each call
                    my $new_deps;

                    if ( $self->scan_deps ) {
                        for my $pkg ( grep { !exists $deps->{$_} } keys %INC ) {
                            $new_deps = 1;

                            $deps->{$pkg} = $INC{$pkg};
                        }
                    }

                    my $data = P->data->to_cbor( [ $new_deps ? $deps : undef, $call_id, $res ] );

                    $self->out->push_write( pack( 'L>', bytes::length $data->$* ) . $data->$* );

                    return;
                },
                $req->[2],
            );

            return;
        }
    );

    return;
}

sub _start_listen ( $self, $cb ) {
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

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::Util::PM::RPC::Server

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
