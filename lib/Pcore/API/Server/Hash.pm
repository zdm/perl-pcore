package Pcore::API::Server::Hash;

use Pcore -class;
use Crypt::ScryptKDF qw[];

with qw[Pcore::Util::PM::RPC::Worker];

has scrypt_N   => ( is => 'ro', isa => PositiveInt, default => 16_384 );
has scrypt_r   => ( is => 'ro', isa => PositiveInt, default => 8 );
has scrypt_p   => ( is => 'ro', isa => PositiveInt, default => 1 );
has scrypt_len => ( is => 'ro', isa => PositiveInt, default => 32 );

# TODO try to use Argon2 instead of Scrypt:
# https://github.com/Leont/crypt-argon2
# https://github.com/skinkade/p6-crypt-argon2

sub create_scrypt ( $self, $cb, $args ) {
    my $salt = P->random->bytes(32);

    my $hash = Crypt::ScryptKDF::scrypt_hash( P->text->encode_utf8( $args->[0] ), $salt, $self->{scrypt_N}, $self->{scrypt_r}, $self->{scrypt_p}, $self->{scrypt_len} );

    $cb->($hash);

    return;
}

sub verify_scrypt ( $self, $cb, $args ) {
    $cb->( Crypt::ScryptKDF::scrypt_hash_verify( P->text->encode_utf8( $args->[0] ), $args->[1] ) ? 1 : 0 );

    return;
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::API::Server::Hash - RPC hash generator

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
