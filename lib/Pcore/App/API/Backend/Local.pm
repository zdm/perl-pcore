package Pcore::App::API::Backend::Local;

use Pcore -role, -const;
use Pcore::Util::Status::Keyword qw[status];
use Pcore::Util::Hash::RandKey;
use Pcore::Util::Data qw[to_b64_url from_b64];

with qw[Pcore::App::API::Backend];

requires qw[init_db];

has dbh => ( is => 'ro', isa => ConsumerOf ['Pcore::DBH'], required => 1 );

has _hash_rpc => ( is => 'ro', isa => InstanceOf ['Pcore::Util::PM::RPC'], init_arg => undef );
has _hash_cache => ( is => 'ro', isa => InstanceOf ['Pcore::Util::Hash::RandKey'], default => sub { Pcore::Util::Hash::RandKey->new }, init_arg => undef );
has _hash_cache_size => ( is => 'ro', isa => PositiveInt, default => 10_000 );

has _local_app_instance_connected => ( is => 'ro', isa => Bool, default => 0, init_arg => undef );

const our $TOKEN_TYPE_APP_INSTANCE => 1;
const our $TOKEN_TYPE_USER         => 2;

sub _build_is_local ($self) {
    return 1;
}

sub _build_host ($self) {
    return 'local';
}

# CONNECT LOCAL APP INSTANCE
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
    $self->create_app(
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
                        $self->create_app_instance(
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

# TODO create app registration token
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

                    # enable all permissions
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

sub validate_app_instance_token_hash ( $self, $token, $hash, $cb ) {
    $self->verify_hash( $token, $hash, $cb );

    return;
}

# USER TOKEN
sub generate_user_token ( $self, $token_id, $user_id, $role_id, $cb ) {

    # generate random token
    my $token = P->random->bytes(48);

    # add token type, app instance id
    $token = to_b64_url pack( 'C', $TOKEN_TYPE_USER ) . pack( 'L', $token_id ) . $token;

    my $private_token = $token . $user_id . $role_id;

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

sub validate_user_token_hash ( $self, $token, $hash, $user_id, $role_id, $cb ) {
    my $private_token = $token . $user_id . $role_id;

    $self->verify_hash( $private_token, $hash, $cb );

    return;
}

# USER PASSWORD
sub generate_user_password_hash ( $self, $password, $user_id, $cb ) {
    my $private_token = $password . $user_id;

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

sub validate_user_password_hash ( $self, $password, $hash, $user_id, $cb ) {
    my $private_token = $password . $user_id;

    $self->verify_hash( $private_token, $hash, $cb );

    return;
}

# HASH
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
            sub ( $rpc_status, $match ) {
                my $status = $match ? status 200 : status 400;

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
## |    3 | 64, 137, 325, 348,   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |      | 373                  |                                                                                                                |
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
