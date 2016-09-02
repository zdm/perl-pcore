package Pcore::App::API::Auth::Backend::Local;

use Pcore -role, -const;
use Pcore::Util::Hash::RandKey;
use Pcore::Util::Data qw[to_b64_url from_b64];

with qw[Pcore::App::API::Auth::Backend];

has dbh => ( is => 'ro', isa => ConsumerOf ['Pcore::DBH'], required => 1 );

has _hash_rpc => ( is => 'ro', isa => InstanceOf ['Pcore::Util::PM::RPC'], init_arg => undef );
has _hash_cache => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Hash::RandKey'], default => sub { Pcore::Util::Hash::RandKey->new }, init_arg => undef );
has _hash_cache_size => ( is => 'ro', isa => PositiveInt, default => 10_000 );

const our $TOKEN_TYPE_APP_INSTANCE => 1;
const our $TOKEN_TYPE_USER         => 2;

around init => sub ( $orig, $self, $cb ) {
    $self->{_hash_rpc} = P->pm->run_rpc(
        'Pcore::App::API::RPC::Hash',
        workers   => undef,
        buildargs => {
            scrypt_n   => 16_384,
            scrypt_r   => 8,
            scrypt_p   => 1,
            scrypt_len => 32,
        },
    );

    return $self->$orig($cb);
};

# TOKEN
sub create_app_instance_token ( $self, $app_instance_id, $cb ) {

    # generate random token
    my $token = P->random->bytes(27);

    # add token type, app instance id
    $token = to_b64_url pack( 'C', $TOKEN_TYPE_APP_INSTANCE ) . pack( 'L', $app_instance_id ) . $token;

    $self->create_hash(
        $token,
        sub ($hash) {
            $cb->( $token, $hash );

            return;
        }
    );

    return;
}

sub create_user_token ( $self, $token_id, $user_id, $role_id, $cb ) {

    # generate random token
    my $token = P->random->bytes(27);

    # add token type, app instance id
    $token = to_b64_url pack( 'C', $TOKEN_TYPE_USER ) . pack( 'L', $token_id ) . $token;

    my $private_token = $token . $user_id . $role_id;

    $self->create_hash(
        $private_token,
        sub ($hash) {
            $cb->( $private_token, $hash );

            return;
        }
    );

    return;
}

sub create_user_password_hash ( $self, $password, $user_id, $cb ) {
    my $private_token = $password . $user_id;

    $self->create_hash(
        $private_token,
        sub ($hash) {
            $cb->($hash);

            return;
        }
    );

    return;
}

# HASH
sub create_hash ( $self, $token, $cb ) {
    $self->_hash_rpc->rpc_call(
        'create_scrypt',
        $token,
        sub ( $status, $hash ) {
            $cb->($hash);

            return;
        }
    );

    return;
}

# TODO limit cache size
sub verify_hash ( $self, $token, $hash, $cb ) {
    my $cache_id = "$hash-$token";

    if ( exists $self->{_hash_cache}->{$cache_id} ) {
        $cb->( $self->{_hash_cache}->{$cache_id} );
    }
    else {
        $self->_hash_rpc->rpc_call(
            'verify_scrypt',
            $token, $hash,
            sub ( $status, $match ) {
                $self->{_hash_cache}->{$cache_id} = $match;

                $cb->($match);

                return;
            }
        );
    }

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 54                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Auth::Backend::Local

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
