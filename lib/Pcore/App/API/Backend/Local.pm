package Pcore::App::API::Backend::Local;

use Pcore -role;
use Pcore::Util::Response qw[status];
use Pcore::Util::Data qw[to_b64_url from_b64];
use Pcore::Util::Digest qw[sha1];
use Pcore::App::API qw[:CONST];
use Pcore::Util::Text qw[encode_utf8];

with qw[Pcore::App::API::Backend];

requires(

    # INIT
    'init_db',
    '_connect_app_instance',

    # AUTH
    '_auth_user_password',
    '_auth_app_instance_token',
    '_auth_user_token',
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
    else {
        $cb->( status [ 400, 'Invalid token type' ] );
    }

    return;
}

# TOKEN / HASH GENERATORS
sub _generate_app_instance_token ( $self, $app_instance_id, $cb ) {

    # generate random token
    my $token = to_b64_url pack( 'CL', $TOKEN_TYPE_APP_INSTANCE_TOKEN, $app_instance_id ) . P->random->bytes(48);

    my $private_token = sha1 $token . $app_instance_id;

    $self->_hash_rpc->rpc_call(
        'create_hash',
        $private_token,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);
            }
            else {
                $cb->( status 200, token => $token, hash => $res->{result} );
            }

            return;
        }
    );

    return;
}

sub _generate_user_token ( $self, $user_token_id, $cb ) {

    # generate random token
    my $token = to_b64_url pack( 'CL', $TOKEN_TYPE_USER_TOKEN, $user_token_id ) . P->random->bytes(48);

    my $private_token = sha1 $token . $user_token_id;

    $self->_hash_rpc->rpc_call(
        'create_hash',
        $private_token,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);
            }
            else {
                $cb->( status 200, token => $token, hash => $res->{result} );
            }

            return;
        }
    );

    return;
}

sub _generate_user_password_hash ( $self, $user_name_utf8, $user_password_utf8, $cb ) {
    my $private_token = sha1 encode_utf8 $user_password_utf8 . $user_name_utf8;

    $self->_hash_rpc->rpc_call(
        'create_hash',
        $private_token,
        sub ( $res ) {
            if ( !$res ) {
                $cb->($res);
            }
            else {
                $cb->( status 200, hash => $res->{result} );
            }

            return;
        }
    );

    return;
}

sub _verify_token_hash ( $self, $token, $hash, $cb ) {
    my $cache_id = "$hash-$token";

    if ( exists $self->{_hash_cache}->{$cache_id} ) {
        $cb->( $self->{_hash_cache}->{$cache_id} );
    }
    else {
        $self->_hash_rpc->rpc_call(
            'verify_hash',
            $token, $hash,
            sub ( $res ) {
                my $status = $self->{_hash_cache}->{$cache_id} = $res->{result} ? status 200 : status [ 400, 'Invalid token' ];

                $cb->($status);

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
## |    3 | 70, 76, 84, 152      | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 |                      | Subroutines::ProhibitUnusedPrivateSubroutines                                                                  |
## |      | 102                  | * Private subroutine/method '_generate_app_instance_token' declared but not used                               |
## |      | 127                  | * Private subroutine/method '_generate_user_token' declared but not used                                       |
## |      | 152                  | * Private subroutine/method '_generate_user_password_hash' declared but not used                               |
## |      | 173                  | * Private subroutine/method '_verify_token_hash' declared but not used                                         |
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
