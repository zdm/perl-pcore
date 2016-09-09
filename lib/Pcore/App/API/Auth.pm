package Pcore::App::API::Auth;

use Pcore -const, -role, -export => { CONST => [qw[$TOKEN_TYPE_APP_INSTANCE $TOKEN_TYPE_USER]] };
use Pcore::Util::Data qw[from_b64];

has _auth_cache => ( is => 'lazy', isa => HashRef, init_arg => undef );

const our $TOKEN_TYPE_APP_INSTANCE => 1;
const our $TOKEN_TYPE_USER         => 2;

sub _buid__auth_cache ($self) {
    return {
        user_name_id          => {},    # user name to user id cache
        user_id_password      => {},    # valid user password cache
        app_instance_id_token => {},    # valid app instancee token cache
        user_token_id         => {},    # valid user token cache
    };
}

# AUTHENTICATION
sub auth_user_password ( $self, $user_name, $user_password, $cb ) {
    my $cache = $self->{_auth_cache};

    # user name -> user id assoc. is cached
    if ( my $user_id = $cache->{user_name_id}->{$user_name} ) {

        # valid user password is cached
        if ( my $valid_password = $cache->{user_id_password}->{$user_id} ) {

            # password is match valid password
            if ( $valid_password eq $user_password ) {
                $cb->($user_id);
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

                        $cb->($user_id);
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

                    $cb->($user_id);
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
        if ( my $valid_token = $cache->{app_instance_id_token}->{$token_id} ) {

            # token is match
            if ( $valid_token eq $token ) {
                $cb->( $token_type, $token_id );
            }

            # token is not match
            else {
                $cb->( undef, undef );
            }
        }

        # app instance token is not cached
        else {
            $self->{backend}->auth_token(
                $token,
                sub ($status) {

                    # token is valid
                    if ($status) {

                        # cache valid token
                        $cache->{app_instance_id_token}->{$token_id} = $token;

                        $cb->( $token_type, $token_id );
                    }

                    # token is not valid
                    else {
                        $cb->( undef, undef );
                    }

                    return;
                }
            );
        }
    }

    # user token
    elsif ( $token_type == $TOKEN_TYPE_USER ) {

        # valid user token is cached
        if ( my $valid_token = $cache->{user_token_id}->{$token_id} ) {

            # token is match
            if ( $valid_token eq $token ) {
                $cb->( $token_type, $token_id );
            }

            # token is not match
            else {
                $cb->( undef, undef );
            }
        }

        # user token is not cached
        else {
            $self->{backend}->auth_token(
                $token,
                sub ($status) {

                    # token is valid
                    if ($status) {

                        # cache valid token
                        $cache->{user_token_id}->{$token_id} = $token;

                        $cb->( $token_type, $token_id );
                    }

                    # token is not valid
                    else {
                        $cb->( undef, undef );
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
sub auth_app_instance ( $self, $app_instance_id, $cb ) {
    my $cache = $self->{_auth_cache};

    # TODO
    # check, that app is enabled
    # check, that app instance is enabled

    return;
}

# TODO
sub auth_user ( $self, $user_id, $cb ) {

    # TODO
    # get user token
    # check, that user token is enabled;
    # check, that user is enabled;

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
## |    3 | 11                   | Subroutines::ProhibitUnusedPrivateSubroutines - Private subroutine/method '_buid__auth_cache' declared but not |
## |      |                      |  used                                                                                                          |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    3 | 21                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
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
