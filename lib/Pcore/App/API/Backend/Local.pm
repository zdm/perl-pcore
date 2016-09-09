package Pcore::App::API::Backend::Local;

use Pcore -role;
use Pcore::Util::Status::Keyword qw[status];
use Pcore::Util::Hash::RandKey;
use Pcore::Util::Data qw[to_b64_url from_b64];
use Pcore::App::API::Auth qw[:CONST];

with qw[Pcore::App::API::Backend];

requires qw[init_db];

has dbh => ( is => 'ro', isa => ConsumerOf ['Pcore::DBH'], required => 1 );

has _hash_rpc => ( is => 'ro', isa => InstanceOf ['Pcore::Util::PM::RPC'], init_arg => undef );
has _hash_cache => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Hash::RandKey'], default => sub { Pcore::Util::Hash::RandKey->new }, init_arg => undef );
has _hash_cache_size => ( is => 'ro', isa => PositiveInt, default => 10_000 );

has _local_app_instance_connected => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

sub _build_is_local ($self) {
    return 1;
}

sub _build_host ($self) {
    return 'local';
}

# INIT
sub init ( $self, $cb ) {

    $self->init_db(
        sub {

            # create hash RPC
            P->pm->run_rpc(
                'Pcore::App::API::RPC::Hash',
                workers   => undef,
                buildargs => {
                    scrypt_n   => 16_384,
                    scrypt_r   => 8,
                    scrypt_p   => 1,
                    scrypt_len => 32,
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

# REGISTER APP INSTANCE
sub register_app_instance ( $self, $app_name, $app_desc, $app_permissions, $app_instance_host, $app_instance_version, $cb ) {
    my $dbh = $self->dbh;

    # create app
    $self->_create_app(
        $app_name,
        $app_desc,
        sub ( $status, $app_id ) {

            # get app, check, that app created and enabled
            $self->get_app_by_id(
                $app_id,
                sub ( $status, $app ) {

                    # can't register new app instance if app is disabled
                    if ( !$app->{enabled} ) {
                        $cb->( status [ 400, 'App is disabled' ], undef, undef );
                    }
                    else {

                        # create disabled app instance
                        $self->_create_app_instance(
                            $app_id,
                            $app_instance_host,
                            $app_instance_version,
                            sub ( $status, $app_instance_id ) {

                                # add app permissions;
                                $self->add_app_permissions(
                                    $app_id,
                                    $app_permissions,
                                    sub($status) {

                                        # return error, if permission can't be stored
                                        if ( !$status ) {
                                            $cb->( $status, undef, undef );
                                        }

                                        # permissions stored
                                        else {

                                            # set app instance token
                                            $self->set_app_instance_token(
                                                $app_instance_id,
                                                sub ( $status, $token ) {
                                                    $cb->( $status, $app_instance_id, $token );

                                                    return;
                                                }
                                            );
                                        }

                                        return;
                                    }
                                );

                                return;
                            }
                        );
                    }

                    return;
                }
            );

            return;
        }
    );

    return;
}

# CONNECT APP INSTANCE
sub connect_app_instance ( $self, $app_instance_id, $app_instance_version, $app_roles, $app_permissions, $cb ) {
    $self->get_app_instance_by_id(
        $app_instance_id,
        sub ( $status, $app_instance ) {

            # app instance was not found
            if ( !$status ) {
                $cb->($status);
            }
            else {

                # update app version, host, last_connected_ts
                $self->update_app_instance(
                    $app_instance_id,
                    $app_instance_version,
                    sub ($status) {

                        # add new permissions
                        $self->add_app_permissions(
                            $app_instance->{app_id},
                            $app_permissions,
                            sub ($status) {
                                my $continue = sub {

                                    # check, that all app permissions are enabled
                                    $self->get_app_germissions(
                                        $app_instance->{app_id},
                                        sub ( $status, $permissions ) {
                                            for my $permission ( $permissions->@* ) {
                                                if ( !$permission->{enabled} ) {
                                                    $cb->( status [ 400, 'Not all required app permissions asr enabled' ] );

                                                    return;
                                                }
                                            }

                                            # add app roles
                                            $self->add_app_roles(
                                                $app_instance->{app_id},
                                                $app_roles,
                                                sub($status) {

                                                    # connection allowed
                                                    $cb->( status 200 );

                                                    return;
                                                }
                                            );

                                            return;
                                        }
                                    );

                                    return;
                                };

                                # local app
                                if ( $app_instance_id == $self->app->instance_id && !$self->{_local_app_instance_connected} ) {
                                    $self->_connect_local_app_instance( $app_instance->{app_id}, $continue );
                                }

                                # remote app
                                else {
                                    $continue->();
                                }

                                return;
                            }
                        );

                        return;
                    }
                );
            }

            return;
        }
    );

    return;
}

# TODO create app registration token, call app local_init hook
sub _connect_local_app_instance ( $self, $app_id, $cb ) {
    $self->{_local_app_instance_connected} = 1;

    # enable app
    $self->set_app_enabled(
        $app_id, 1,
        sub ($tatus) {

            # enable app instance
            $self->set_app_instance_enabled(
                $self->app->{instance_id},
                1,
                sub ($tatus) {

                    # enable all app permissions
                    $self->app_permissions_enable_all(
                        $self->app->{instance_id},
                        sub($status) {

                            # get root user
                            $self->get_user_by_id(
                                1,
                                sub ( $status, $user ) {

                                    # root user is not exists
                                    if ( !$status ) {

                                        # generate root user password
                                        my $root_password = to_b64_url P->random->bytes(32);

                                        # create root user
                                        $self->create_user(
                                            'root',
                                            $root_password,
                                            sub ( $status, $user_id ) {

                                                # root user created
                                                if ($status) {
                                                    say qq[Root user created: $root_password];
                                                }
                                                else {
                                                    say qq[Error creating root user: $status];
                                                }

                                                # continue
                                                $cb->();

                                                return;
                                            }
                                        );
                                    }
                                    else {

                                        # continue
                                        $cb->();
                                    }

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
    );

    return;
}

# AUTH
sub auth_token ( $self, $token, $cb ) {

    # decode token
    my ( $token_type, $token_id ) = unpack 'CL', from_b64 $token;

    if ( $token_type == $TOKEN_TYPE_APP_INSTANCE ) {
        $self->auth_app_instance_token( $token_id, $token, $cb );
    }
    elsif ( $token_type == $TOKEN_TYPE_USER ) {
        $self->auth_user_token( $token_id, $token, $cb );
    }
    else {
        $cb->( status [ 400, 'Invalid token type' ] );
    }

    return;
}

# APP TOKEN
sub generate_app_instance_token ( $self, $app_instance_id, $cb ) {

    # generate random token
    my $token = P->random->bytes(48);

    # add token type, app instance id
    $token = to_b64_url pack( 'C', $TOKEN_TYPE_APP_INSTANCE ) . pack( 'L', $app_instance_id ) . $token;

    $self->_hash_rpc->rpc_call(
        'create_scrypt',
        $token,
        sub ( $status, $hash ) {
            $cb->( $status, $token, $hash );

            return;
        }
    );

    return;
}

# USER TOKEN
sub generate_user_token ( $self, $user_token_id, $user_id, $cb ) {

    # generate random token
    my $token = P->random->bytes(48);

    # add token type, user token id
    $token = to_b64_url pack( 'C', $TOKEN_TYPE_USER ) . pack( 'L', $user_token_id ) . $token;

    my $private_token = $token . $user_id;

    $self->_hash_rpc->rpc_call(
        'create_scrypt',
        $private_token,
        sub ( $status, $hash ) {
            $cb->( $status, $token, $hash );

            return;
        }
    );

    return;
}

sub validate_user_token_hash ( $self, $hash, $token, $user_id, $cb ) {
    my $private_token = $token . $user_id;

    $self->verify_hash( $hash, $private_token, $cb );

    return;
}

# USER PASSWORD
sub generate_user_password_hash ( $self, $user_password, $user_id, $cb ) {
    my $private_token = $user_password . $user_id;

    $self->_hash_rpc->rpc_call(
        'create_scrypt',
        $private_token,
        sub ( $status, $hash ) {
            $cb->( $status, $hash );

            return;
        }
    );

    return;
}

sub validate_user_password_hash ( $self, $hash, $user_password, $user_id, $cb ) {
    my $private_token = $user_password . $user_id;

    $self->verify_hash( $hash, $private_token, $cb );

    return;
}

# HASH
# TODO limit cache size
sub verify_hash ( $self, $hash, $token, $cb ) {
    my $cache_id = "$hash-$token";

    if ( exists $self->{_hash_cache}->{$cache_id} ) {
        $cb->( $self->{_hash_cache}->{$cache_id} );
    }
    else {
        $self->_hash_rpc->rpc_call(
            'verify_scrypt',
            $token, $hash,
            sub ( $rpc_status, $match ) {
                my $status = $match ? status 200 : status [ 400, 'Invalid token' ];

                $self->{_hash_cache}->{$cache_id} = $status;

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
## |    3 | 62, 135, 336, 359,   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |      | 368, 384             |                                                                                                                |
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
