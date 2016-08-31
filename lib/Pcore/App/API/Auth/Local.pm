package Pcore::App::API::Auth::Local;

use Pcore -role;
use Pcore::Util::Hash::RandKey;
use Pcore::Util::Data qw[to_b64_url from_b64];

with qw[Pcore::App::API::Auth];

has dbh => ( is => 'ro', isa => ConsumerOf ['Pcore::DBH'], required => 1 );

has _hash_rpc => ( is => 'lazy', isa => InstanceOf ['Pcore::Util::PM::RPC'], init_arg => undef );
has _hash_cache => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Hash::RandKey'], default => sub { Pcore::Util::Hash::RandKey->new }, init_arg => undef );

sub _build__hash_rpc($self) {
    return P->pm->run_rpc(
        'Pcore::App::API::RPC::Hash',
        workers   => undef,
        buildargs => {
            scrypt_n   => 16_384,
            scrypt_r   => 8,
            scrypt_p   => 1,
            scrypt_len => 32,
        },
    );
}

# TOKEN
sub create_token ( $self, $token_id, $salt, $cb ) {

    # generate public token
    my $public_token = P->random->bytes(32) . pack( 'L', $token_id );

    # encode public token to the base64
    $public_token = to_b64_url $public_token;

    # create private token
    my $private_token = $salt . $public_token . $salt;

    $self->_hash_rpc->rpc_call(
        'create_scrypt',
        $private_token,
        sub ( $status, $private_token_hash ) {
            $cb->( $public_token, $private_token_hash );

            return;
        }
    );

    return;
}

sub decode_token ( $self, $public_token_b64 ) {
    my $public_token_decoded = from_b64 $public_token_b64;

    my $token_id = unpack 'L', substr $public_token_decoded, -4;

    return $token_id;
}

# TODO limit cache size
# TODO make token_type - constant
# TODO pack token type into private token
sub verify_token ( $self, $public_token, $token_type, $token_id, $salt, $hash, $cb ) {

    # create private token
    my $private_token = $salt . $public_token . $salt;

    my $cache_id = "$token_type-$token_id";

    my $cache_hash = "$hash-$private_token";

    if ( my $cached_token = $self->{_hash_cache}->{$cache_id} ) {
        if ( $cached_token eq $cache_hash ) {
            $cb->(1);

            return;
        }
        else {
            delete $self->{_hash_cache}->{$cache_id};
        }
    }

    $self->_hash_rpc->rpc_call(
        'verify_scrypt',
        $private_token,
        $hash,
        sub ( $status, $match ) {
            if ($match) {
                $self->{_hash_cache}->{$cache_id} = $cache_hash;
            }
            else {
                delete $self->{_hash_cache}->{$cache_id};
            }

            $cb->($match);

            return;
        }
    );

    return;
}

sub invalidate_token ( $self, $token_type, $token_id ) {
    my $cache_id = "$token_type-$token_id";

    delete $self->{_hash_cache}->{$cache_id};

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 63                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 31                   | CodeLayout::ProhibitParensWithBuiltins - Builtin function called with parentheses                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Auth::Local

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
