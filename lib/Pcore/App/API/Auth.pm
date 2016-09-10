package Pcore::App::API::Auth;

use Pcore -const, -role, -export => { CONST => [qw[$TOKEN_TYPE_APP_INSTANCE $TOKEN_TYPE_USER]] };
use Pcore::Util::Data qw[from_b64];

requires qw[
  backend
  get_user_token_by_id
  get_user_by_id
  get_app_by_id
  get_app_instance_by_id
];

has _auth_cache => (
    is      => 'lazy',
    isa     => HashRef,
    default => sub {
        {   user_name_user_id     => {},    # user_name -> user_id cache
            user                  => {},    # user cache by user_id
            app_instance          => {},    # app_instance cache by app_instance_id
            user_token_id_user_id => {},    # user_token_id -> user_id cache
            app                   => {},    # app cache by app_id
        };
    },
    init_arg => undef
);

const our $TOKEN_TYPE_APP_INSTANCE => 1;
const our $TOKEN_TYPE_USER         => 2;

# AUTHENTICATION
sub authenticate_user_password ( $self, $user_name, $user_password, $cb ) {
    my $cache = $self->{_auth_cache};

    # user name -> user id assoc. is cached
    if ( my $user_id = $cache->{user_name_user_id}->{$user_name} ) {

        # user is cached
        if ( my $user = $cache->{user}->{$user_id} ) {

            # valid user password is cached
            if ( defined( my $valid_password = $user->{valid_password} ) ) {

                # password is match valid password
                if ( $user_password eq $valid_password ) {
                    $cb->( { user_id => $user_id } );

                    return;
                }

                # password is not match
                else {
                    $cb->(undef);

                    return;
                }
            }
        }
    }

    # validate user password on backend
    $self->{backend}->auth_user_password(
        $user_name,
        $user_password,
        sub ( $status, $user ) {
            if ($status) {
                my $user_id = $user->{id};

                # cache user_name -> user_id
                $cache->{user_name_user_id}->{$user_name} = $user_id;

                # cache valid user password
                $cache->{user}->{$user_id}->{valid_password} = $user_password;

                # cache user
                $cache->{user}->{$user_id}->{_} = $user;

                $cb->( { user_id => $user_id } );
            }
            else {
                $cb->(undef);
            }

            return;
        }
    );

    return;
}

sub authenticate_token ( $self, $token, $cb ) {

    # decode token
    my ( $token_type, $token_id ) = eval { unpack 'CL', from_b64 $token };

    # error decoding token
    if ($@) {
        $cb->(undef);

        return;
    }

    # app instance token
    if ( $token_type == $TOKEN_TYPE_APP_INSTANCE ) {
        my $app_instance_id = $token_id;

        my $cache = $self->{_auth_cache}->{app_instance};

        # valid app instance token cached
        if ( defined( my $valid_token = $cache->{$app_instance_id}->{valid_token} ) ) {

            # token is match
            if ( $token eq $valid_token ) {
                $cb->( { app_instance_id => $app_instance_id } );

                return;
            }

            # token is not match
            else {
                $cb->(undef);

                return;
            }
        }

        # app instance valid token is not cached
        $self->{backend}->auth_token(
            $token,
            sub ( $status, $app_instance ) {

                # token is valid
                if ($status) {

                    # cache valid token
                    $cache->{$app_instance_id}->{valid_token} = $token;

                    # cache app instance
                    $cache->{$app_instance_id}->{_} = $app_instance;

                    $cb->( { app_instance_id => $app_instance_id } );
                }

                # token is not valid
                else {
                    $cb->(undef);
                }

                return;
            }
        );
    }

    # user token
    elsif ( $token_type == $TOKEN_TYPE_USER ) {
        my $user_token_id = $token_id;

        my $cache = $self->{_auth_cache};

        # user token id -> user id assoc. is cached
        if ( my $user_id = $cache->{user_token_id_user_id}->{$user_token_id} ) {

            # valid token is cached
            if ( defined( my $valid_token = $cache->{user}->{$user_id}->{token}->{$user_token_id}->{valid_token} ) ) {

                # token is match
                if ( $token eq $valid_token ) {
                    $cb->( { user_token_id => $user_token_id } );
                }

                # token is not match
                else {
                    $cb->(undef);
                }
            }
        }

        # user token is not cached
        $self->{backend}->auth_token(
            $token,
            sub ( $status, $user_token ) {

                # token is valid
                if ($status) {
                    my $user_id = $user_token->{user_id};

                    # cache user token id -> user id assoc.
                    $cache->{user_token_id_user_id}->{$user_token_id} = $user_id;

                    # cache valid token
                    $cache->{user}->{$user_id}->{token}->{$user_token_id}->{valid_token} = $token;

                    # cache user token
                    $cache->{user}->{$user_id}->{token}->{$user_token_id}->{_} = $user_token;

                    $cb->( { user_token_id => $user_token_id } );
                }

                # token is not valid
                else {
                    $cb->(undef);
                }

                return;
            }
        );
    }

    # invalid token type
    else {
        $cb->( undef, undef );
    }

    return;
}

# TODO
sub authorize_method ( $self, $req, $roles, $cb ) {
    if ( $req->{app_instance_id} ) {
        $self->_check_app_instance_enabled(
            $req->{app_instance_id},
            sub ($status) {
                return;
            }
        );
    }
    elsif ( $req->{user_token_id} ) {
        $self->_check_user_token_enabled(
            $req->{user_token_id},
            sub ($status) {
                return;
            }
        );
    }
    elsif ( $req->{user_id} ) {
        $self->_check_user_enabled(
            $req->{user_id},
            sub ($status) {
                return;
            }
        );
    }
    else {
        ...;
    }

    return;
}

sub _check_user_enabled ( $self, $user_id, $cb ) {
    my $cache = $self->{_auth_cache}->{user};

    if ( my $user = $cache->{$user_id}->{_} ) {
        $cb->( $user->{enabled} );
    }
    else {
        $self->get_user_by_id(
            $user_id,
            sub ( $status, $user ) {
                if ( !$status ) {
                    $cb->(undef);
                }
                else {

                    # cache user
                    $cache->{$user_id}->{_} = $user;

                    $cb->( $user->{enabled} );
                }

                return;
            }
        );
    }

    return;
}

sub _check_user_token_enabled ( $self, $user_token_id, $cb ) {
    my $cache = $self->{_auth_cache};

    state $check_user_token_enabled = sub ( $self, $user_id, $user_token_id, $cb ) {
        if ( !$cache->{user}->{$user_id}->{token}->{$user_token_id}->{_}->{enabled} ) {
            $cb->(0);
        }
        else {
            $self->_check_user_enabled( $user_id, $cb );
        }

        return;
    };

    if ( my $user_id = $cache->{user_token_id_user_id}->{$user_token_id} ) {
        $check_user_token_enabled->( $self, $user_id, $user_token_id, $cb );
    }
    else {
        $self->get_user_token_by_id(
            $user_token_id,
            sub ( $status, $user_token ) {
                if ( !$status ) {
                    $cb->(undef);
                }
                else {
                    $user_id = $user_token->{user_id};

                    # cache user_token_id
                    $cache->{user_token_id_user_id}->{$user_token_id} = $user_id;

                    # cache user token
                    $cache->{user}->{$user_id}->{token}->{$user_token_id}->{_} = $user_token;

                    $check_user_token_enabled->( $self, $user_id, $user_token_id, $cb );
                }

                return;
            }
        );
    }

    return;
}

sub _check_app_instance_enabled ( $self, $app_instance_id, $cb ) {
    my $cache = $self->{_auth_cache};

    state $check_app_enabled = sub ( $self, $app_id, $cb ) {
        if ( my $app = $cache->{app}->{$app_id}->{_} ) {
            $cb->( $app->{enabled} );
        }
        else {
            $self->get_app_by_id(
                $app_id,
                sub ( $status, $app ) {
                    if ( !$status ) {
                        $cb->(undef);
                    }
                    else {
                        $cache->{app}->{$app_id}->{_} = $app;

                        $cb->( $app->{enabled} );
                    }

                    return;
                }
            );
        }

        return;
    };

    if ( my $app_instance = $cache->{app_instance}->{$app_instance_id}->{_} ) {
        if ( !$app_instance->{enabled} ) {
            $cb->(0);
        }
        else {
            $check_app_enabled->( $self, $app_instance->{app_id}, $cb );
        }
    }
    else {
        $self->get_app_instance_by_id(
            $app_instance_id,
            sub ( $status, $app_instance ) {
                if ( !$status ) {
                    $cb->(undef);
                }
                else {
                    $cache->{app_instance}->{$app_instance_id}->{_} = $app_instance;

                    if ( !$app_instance->{enabled} ) {
                        $cb->(0);
                    }
                    else {
                        $check_app_enabled->( $self, $app_instance->{app_id}, $cb );
                    }
                }

                return;
            }
        );
    }

    return;
}

# sub _get_self_enabled_roles ( $self, $cb ) {
#     if ( my $roles = $self->{_auth_cache}->{self_enabled_roles} ) {
#         $cb->($roles);
#     }
#     else {
#         $self->get_app_instance_roles(
#             $self->app->id,
#             sub ( $status, $roles ) {
#                 if ( !$status ) {
#                     $cb->(undef);
#                 }
#                 else {
#                     my %roles = map { $_->{id} => $_->{name} if $_->{enabled} } $roles->@*;
#
#                     $cache->{$app_id}->{roles} = \%roles;
#
#                     $cb->($roles);
#                 }
#
#                 return;
#             }
#         );
#     }
#
#     return;
# }

sub _get_user_app_permissions ( $self, $user_id, $app_id, $cb ) {
    my $cache = $self->{_auth_cache}->{user};

    if ( my $permissions = $cache->{$user_id}->{permissions} ) {
        $cb->($permissions);
    }
    else {
        $self->get_user_app_permissions(
            $user_id, $app_id,
            sub ( $status, $permissions ) {
                if ( !$status ) {
                    $cb->(undef);
                }
                else {
                    $cache->{$user_id}->{permissions} = $permissions;

                    $cb->($permissions);
                }

                return;
            }
        );
    }

    return;
}

# sub _get_app_app_permissions ( $self, $app_id, $cb ) {
#     my $cache = $self->{_auth_cache}->{app};
#
#     if ( my $permissions = $cache->{$user_id}->{permissions} ) {
#         $cb->($permissions);
#     }
#     else {
#         $self->get_user_app_permissions(
#             $user_id, $app_id,
#             sub ( $status, $permissions ) {
#                 if ( !$status ) {
#                     $cb->(undef);
#                 }
#                 else {
#                     $cache->{$user_id}->{permissions} = $permissions;
#
#                     $cb->($permissions);
#                 }
#
#                 return;
#             }
#         );
#     }
#
#     return;
# }

# EVENTS
# NOTE call on: set_user_password
sub on_user_password_change ( $self, $user_id ) {
    delete $self->{_auth_cache}->{user}->{$user_id}->{valid_password};

    return;
}

# NOTE call on: set_app_instance_token
sub on_app_instance_token_change ( $self, $app_instance_id ) {
    delete $self->{_auth_cache}->{app_instance}->{$app_instance_id}->{valid_token};

    return;
}

# NOTE call on: enable / disale user token
sub on_user_token_change ( $self, $user_token_id ) {

    # resolve user id by user token id
    if ( my $user_id = $self->{_auth_cache}->{user_token_id_user_id}->{$user_token_id} ) {
        delete $self->{_auth_cache}->{user}->{$user_id}->{token}->{$user_token_id}->{_};
    }

    return;
}

sub on_user_token_remove ( $self, $user_token_id ) {

    # resolve user id by user token id
    if ( my $user_id = $self->{_auth_cache}->{user_token_id_user_id}->{$user_token_id} ) {
        delete $self->{_auth_cache}->{user_token_id_user_id}->{$user_token_id};

        delete $self->{_auth_cache}->{user}->{$user_id}->{token}->{$user_token_id};
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
## |    3 | 32, 412              | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 244                  | ControlStructures::ProhibitYadaOperator - yada operator (...) used                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 412                  | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_get_user_app_permissions' declared |
## |      |                      |  but not used                                                                                                  |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 14                   | CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Auth

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
