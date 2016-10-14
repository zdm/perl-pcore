package Pcore::App::API::Backend::Local;

use Pcore -role;
use Pcore::Util::Response qw[status];
use Pcore::Util::Data qw[to_b64_url from_b64];
use Pcore::Util::Digest qw[sha3_512];
use Pcore::App::API qw[:CONST];
use Pcore::Util::Text qw[encode_utf8];
use Pcore::Util::UUID qw[uuid_bin];

with qw[Pcore::App::API::Backend];

requires(

    # INIT
    'init_db',
    '_connect_app_instance',

    # AUTH
    '_auth_user_password',
    '_auth_app_instance_token',
    '_auth_user_token',
    '_auth_user_session',
);

has dbh => ( is => 'ro', isa => ConsumerOf ['Pcore::DBH'], required => 1 );

has _hash_rpc   => ( is => 'ro', isa => InstanceOf ['Pcore::Util::PM::RPC'],       init_arg => undef );
has _hash_cache => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Hash::RandKey'], init_arg => undef );
has _hash_cache_size => ( is => 'ro', isa => PositiveInt, default => 10_000 );

sub _build_is_local ($self) {
    return 1;
}

sub _build_host ($self) {
    return 'local';
}

# INIT
sub init ( $self, $cb ) {
    $self->{_hash_cache} = P->hash->limited( $self->{_hash_cache_size} );

    $self->init_db(
        sub {

            # create hash RPC
            P->pm->run_rpc(
                'Pcore::App::API::RPC::Hash',
                workers   => undef,
                buildargs => {
                    argon2_time        => 3,
                    argon2_memory      => '64M',
                    argon2_parallelism => 1,
                },
                on_ready => sub ($rpc) {
                    $self->{_hash_rpc} = $rpc;

                    $cb->( status 200 );

                    return;
                },
            );

            return;
        }
    );

    return;
}

sub connect_app_instance ( $self, $app_instance_id, $app_instance_version, $app_roles, $app_permissions, $cb ) {
    $self->_connect_app_instance( 0, $app_instance_id, $app_instance_version, $app_roles, $app_permissions, $cb );

    return;
}

sub connect_local_app_instance ( $self, $app_instance_id, $app_instance_version, $app_roles, $app_permissions, $cb ) {
    $self->_connect_app_instance( 1, $app_instance_id, $app_instance_version, $app_roles, $app_permissions, $cb );

    return;
}

# AUTH
# NOTE this method should be accessible only for applications
sub auth_token ( $self, $app_instance_id, $token_type, $token_id, $private_token, $cb ) {
    if ( $token_type == $TOKEN_TYPE_USER_PASSWORD ) {
        $self->_auth_user_password( $app_instance_id, $token_id, $private_token, $cb );
    }
    elsif ( $token_type == $TOKEN_TYPE_APP_INSTANCE_TOKEN ) {
        $self->_auth_app_instance_token( $app_instance_id, $token_id, $private_token, $cb );
    }
    elsif ( $token_type == $TOKEN_TYPE_USER_TOKEN ) {
        $self->_auth_user_token( $app_instance_id, $token_id, $private_token, $cb );
    }
    elsif ( $token_type == $TOKEN_TYPE_USER_SESSION ) {
        $self->_auth_user_session( $app_instance_id, $token_id, $private_token, $cb );
    }
    else {
        $cb->( status [ 400, 'Invalid token type' ] );
    }

    return;
}

# TOKEN / HASH GENERATORS
sub _generate_app_instance_token ( $self, $app_instance_id, $cb ) {

    # generate random token
    my $token_bin = pack( 'CL', $TOKEN_TYPE_APP_INSTANCE_TOKEN, $app_instance_id ) . P->random->bytes(27);

    $self->_hash_rpc->rpc_call(
        'create_hash',
        sha3_512($token_bin),
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);
            }
            else {
                $cb->( status 200, token => to_b64_url($token_bin), hash => $res->{hash} );
            }

            return;
        }
    );

    return;
}

sub _generate_user_token ( $self, $user_id, $cb ) {

    # generate token id
    my $token_id_bin = uuid_bin;    # 16 bytes

    # create token
    my $token_bin = pack( 'C', $TOKEN_TYPE_USER_TOKEN ) . $token_id_bin . P->random->bytes(31);

    $self->_hash_rpc->rpc_call(
        'create_hash',
        sha3_512($token_bin) . $user_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);
            }
            else {
                $cb->( status 200, token_id => unpack( 'H*', $token_id_bin ), token => to_b64_url($token_bin), hash => $res->{hash} );
            }

            return;
        }
    );

    return;
}

sub _generate_user_session ( $self, $user_id, $cb ) {

    # generate token id
    my $token_id_bin = uuid_bin;    # 16 bytes

    # create token
    my $token_bin = pack( 'C', $TOKEN_TYPE_USER_SESSION ) . $token_id_bin . P->random->bytes(31);

    $self->_hash_rpc->rpc_call(
        'create_hash',
        sha3_512($token_bin) . $user_id,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);
            }
            else {
                $cb->( status 200, token_id => unpack( 'H*', $token_id_bin ), token => to_b64_url($token_bin), hash => $res->{hash} );
            }

            return;
        }
    );

    return;
}

sub _generate_user_password_hash ( $self, $user_name_utf8, $user_password_utf8, $cb ) {
    my $user_name_bin = encode_utf8 $user_name_utf8;

    my $token_bin = $user_name_bin . encode_utf8($user_password_utf8) . $user_name_bin;

    $self->_hash_rpc->rpc_call(
        'create_hash',
        sha3_512($token_bin),
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);
            }
            else {
                $cb->( status 200, hash => $res->{hash} );
            }

            return;
        }
    );

    return;
}

sub _verify_token_hash ( $self, $private_token, $hash, $cb ) {
    my $cache_id = "$hash-$private_token";

    if ( exists $self->{_hash_cache}->{$cache_id} ) {
        $cb->( $self->{_hash_cache}->{$cache_id} );
    }
    else {
        $self->_hash_rpc->rpc_call(
            'verify_hash',
            $private_token,
            $hash,
            sub ( $res ) {
                $cb->( $self->{_hash_cache}->{$cache_id} = $res->{match} ? status 200 : status [ 400, 'Invalid token' ] );

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
## |    3 | 72, 78, 86, 182      | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 |                      | Subroutines::ProhibitUnusedPrivateSubroutines                                                                  |
## |      | 107                  | * Private subroutine/method '_generate_app_instance_token' declared but not used                               |
## |      | 130                  | * Private subroutine/method '_generate_user_token' declared but not used                                       |
## |      | 156                  | * Private subroutine/method '_generate_user_session' declared but not used                                     |
## |      | 182                  | * Private subroutine/method '_generate_user_password_hash' declared but not used                               |
## |      | 205                  | * Private subroutine/method '_verify_token_hash' declared but not used                                         |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Backend::Local

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
