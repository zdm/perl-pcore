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
        {   user_name_id          => {},    # user_name -> user_id cache
            user_id_password      => {},    # valid user password cache
            app_instance_id_token => {},    # valid app instancee token cache
            user_token_id         => {},    # valid user token cache
            user_token            => {},    # user token cache by user_token_id
            user                  => {},    # user cache by user_id
            app                   => {},    # app cache by app_id
            app_instance          => {},    # app instance cache by app_instance_id
        };
    },
    init_arg => undef
);

const our $TOKEN_TYPE_APP_INSTANCE => 1;
const our $TOKEN_TYPE_USER         => 2;

# AUTHENTICATION
sub auth_user_password ( $self, $user_name, $user_password, $cb ) {
    my $cache = $self->{_auth_cache};

    # user name -> user id assoc. is cached
    if ( my $user_id = $cache->{user_name_id}->{$user_name} ) {

        # valid user password is cached
        if ( my $valid_password = $cache->{user_id_password}->{$user_id} ) {

            # password is match valid password
            if ( $valid_password eq $user_password ) {
                $cb->( { user_id => $user_id } );
            }

            # password is not match
            else {
                $cb->(undef);
            }
        }

        # valid user password is not cached
        else {
            $self->{backend}->auth_user_password(
                $user_name,
                $user_password,
                sub ( $status, $user_id ) {
                    if ($status) {
                        $cache->{user_id_password}->{$user_id} = $user_password;

                        $cb->( { user_id => $user_id } );
                    }
                    else {
                        $cb->(undef);
                    }

                    return;
                }
            );
        }
    }

    # user name -> user id is not cached
    else {
        $self->{backend}->auth_user_password(
            $user_name,
            $user_password,
            sub ( $status, $user_id ) {

                # store user name -> user id assoc.
                $cache->{user_name_id}->{$user_name} = $user_id if $user_id;

                if ($status) {
                    $cache->{user_id_password}->{$user_id} = $user_password;

                    $cb->( { user_id => $user_id } );
                }
                else {
                    $cb->(undef);
                }

                return;
            }
        );
    }

    return;
}

sub auth_token ( $self, $token, $cb ) {
    my $cache = $self->{_auth_cache};

    # decode token
    my ( $token_type, $token_id ) = unpack 'CL', from_b64 $token;

    # app token
    if ( $token_type == $TOKEN_TYPE_APP_INSTANCE ) {

        # valid app instance token is cached
        if ( my $cached_token = $cache->{app_instance_id_token}->{$token_id} ) {

            # token is match
            if ( $token eq $cached_token->[0] ) {
                $cb->( { app_id => $cached_token->[1], app_instance_id => $token_id } );
            }

            # token is not match
            else {
                $cb->(undef);
            }
        }

        # app instance token is not cached
        else {
            $self->{backend}->auth_token(
                $token,
                sub ( $status, $app_id ) {

                    # token is valid
                    if ($status) {

                        # cache valid token
                        $cache->{app_instance_id_token}->{$token_id} = [ $token, $app_id ];

                        $cb->( { app_id => $app_id, app_instance_id => $token_id } );
                    }

                    # token is not valid
                    else {
                        $cb->(undef);
                    }

                    return;
                }
            );
        }
    }

    # user token
    elsif ( $token_type == $TOKEN_TYPE_USER ) {

        # valid user token is cached
        if ( my $cached_token = $cache->{user_token_id}->{$token_id} ) {

            # token is match
            if ( $token eq $cached_token->[0] ) {
                $cb->( { user_id => $cached_token->[1], user_token_id => $token_id } );
            }

            # token is not match
            else {
                $cb->(undef);
            }
        }

        # user token is not cached
        else {
            $self->{backend}->auth_token(
                $token,
                sub ( $status, $user_id ) {

                    # token is valid
                    if ($status) {

                        # cache valid token
                        $cache->{user_token_id}->{$token_id} = [ $token, $user_id ];

                        $cb->( { user_id => $user_id, user_token_id => $token_id } );
                    }

                    # token is not valid
                    else {
                        $cb->(undef);
                    }

                    return;
                }
            );
        }
    }

    # invalid token type
    else {
        $cb->( undef, undef );
    }

    return;
}

# TODO
sub auth_method ( $self, $req, $roles, $cb ) {
    state $check_user_token_enabled = sub ( $self, $user_token_id, $cb ) {
        my $cache = $self->{_auth_cache}->{user_token};

        if ( my $user_token = $cache->{$user_token_id} ) {
            $cb->( $user_token->{enabled} );
        }
        else {
            $self->get_user_token_by_id(
                $user_token_id,
                sub ( $status, $user_token ) {
                    if ( !$status ) {
                        $cb->(0);
                    }
                    else {
                        $cache->{$user_token_id} = $user_token;

                        $cb->( $user_token->{enabled} );
                    }

                    return;
                }
            );
        }

        return;
    };

    state $check_user_enabled = sub ( $self, $user_id, $cb ) {
        my $cache = $self->{_auth_cache}->{user};

        if ( my $user = $cache->{$user_id} ) {
            $cb->( $user->{enabled} );
        }
        else {
            $self->get_user_by_id(
                $user_id,
                sub ( $status, $user ) {
                    if ( !$status ) {
                        $cb->(0);
                    }
                    else {
                        $cache->{$user_id} = $user;

                        $cb->( $user->{enabled} );
                    }

                    return;
                }
            );
        }

        return;
    };

    state $check_app_enabled = sub ( $self, $app_id, $cb ) {
        my $cache = $self->{_auth_cache}->{app};

        if ( my $app = $cache->{$app_id} ) {
            $cb->( $app->{enabled} );
        }
        else {
            $self->get_app_by_id(
                $app_id,
                sub ( $status, $app ) {
                    if ( !$status ) {
                        $cb->(0);
                    }
                    else {
                        $cache->{$app_id} = $app;

                        $cb->( $app->{enabled} );
                    }

                    return;
                }
            );
        }

        return;
    };

    state $check_app_instance_enabled = sub ( $self, $app_instance_id, $cb ) {
        my $cache = $self->{_auth_cache}->{app_instance};

        if ( my $app_instance = $cache->{$app_instance_id} ) {
            $cb->( $app_instance->{enabled} );
        }
        else {
            $self->get_app_instance_by_id(
                $app_instance_id,
                sub ( $status, $app_instance ) {
                    if ( !$status ) {
                        $cb->(0);
                    }
                    else {
                        $cache->{$app_instance_id} = $app_instance;

                        $cb->( $app_instance->{enabled} );
                    }

                    return;
                }
            );
        }

        return;
    };

    if ( $req->{user_token_id} ) {

        # TODO check, that user token is enabled
        # TODO store user_id in sec
    }

    if ( $req->{app_instance_id} ) {

        # TODO check, that app is enabled
        # TODO check, that app instance is enabled
        # TODO get enabled app roles
        # TODO get enabled app permissions
    }
    elsif ( $req->{user_id} ) {

        # TODO check, that user is enabled
        # TODO if user_token_id -> get enabled token roles
        # TODO if user password -> get enabled user roles
    }
    else {
        ...;
    }

    return;
}

# EVENTS
# NOTE call on: set_user_password
sub on_user_password_change ( $self, $user_id ) {
    delete $self->{_auth_cache}->{user_id_password}->{$user_id};

    return;
}

# NOTE call on: set_app_instance_token
sub on_app_instance_token_change ( $self, $app_instance_id ) {
    delete $self->{_auth_cache}->{app_instance_id_token}->{$app_instance_id};

    return;
}

# NOTE call on: remove_user_token
sub on_user_token_change ( $self, $token_id ) {
    delete $self->{_auth_cache}->{user_token}->{$token_id};

    return;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 35                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 204                  | Subroutines::ProhibitExcessComplexity - Subroutine "auth_method" with high complexity score (21)               |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 333                  | ControlStructures::ProhibitYadaOperator - yada operator (...) used                                             |
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
