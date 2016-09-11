package Pcore::App::API::Auth;

use Pcore -const, -role, -export => { CONST => [qw[$TOKEN_TYPE_USER_PASSWORD $TOKEN_TYPE_APP_INSTANCE_TOKEN $TOKEN_TYPE_USER_TOKEN]] };
use Pcore::Util::Data qw[to_b64_url from_b64];
use Pcore::Util::Digest qw[sha1];
use Pcore::Util::Text qw[encode_utf8];
use Pcore::App::API::Request;

requires qw[
];

has _auth_cache => (
    is      => 'ro',
    isa     => HashRef,
    default => sub {
        {   auth => {},
            tag  => {},
        };
    },
    init_arg => undef
);

const our $TOKEN_TYPE_USER_PASSWORD      => 1;
const our $TOKEN_TYPE_APP_INSTANCE_TOKEN => 2;
const our $TOKEN_TYPE_USER_TOKEN         => 3;

sub authenticate ( $self, $token, $user_name_utf8, $cb ) {
    my ( $token_type, $token_id, $token_id_encoded );

    # detect auth type
    if ($user_name_utf8) {
        $token_id_encoded = eval {
            encode_utf8 $token;
            encode_utf8 $user_name_utf8;
        };

        # error decoding token
        if ($@) {
            $cb->(undef);

            return;
        }

        $token_type = $TOKEN_TYPE_USER_PASSWORD;

        \$token_id = \$user_name_utf8;
    }
    else {

        # decode token
        ( $token_type, $token_id ) = eval {
            encode_utf8 $token;
            unpack 'CL', from_b64 $token;
        };

        # error decoding token
        if ($@) {
            $cb->(undef);

            return;
        }

        # token is invalid
        if ( $token_type != $TOKEN_TYPE_APP_INSTANCE_TOKEN || $token_type != $TOKEN_TYPE_USER_TOKEN ) {
            $cb->(undef);

            return;
        }

        \$token_id_encoded = \$token_id;
    }

    # convert token to private token
    $token = sha1 $token . $token_id_encoded;

    # create auth key
    my $auth_id = "$token_type-$token_id_encoded-$token";

    my $cache = $self->{_auth_cache};

    # valid private token is cached
    if ( my $valid_token = $cache->{auth}->{$auth_id}->{valid_token} ) {
        if ( $token eq $valid_token ) {
            $cb->(
                bless {
                    api     => $self,
                    auth_id => $auth_id
                },
                'Pcore::App::API::Request'
            );
        }
        else {
            $cb->(undef);
        }
    }

    # not cached, unknown authentication
    else {
        $self->{backend}->authenticate(
            $token_type,
            $token_id,
            $token,
            sub ( $status, $tags ) {

                # not authenticated
                if ( !$status ) {
                    $cb->(undef);
                }

                # authenticated
                else {

                    # store authenticated token
                    $cache->{auth}->{$auth_id}->{token_type}  = $token_type;
                    $cache->{auth}->{$auth_id}->{token_id}    = $token_id;
                    $cache->{auth}->{$auth_id}->{valid_token} = $token;

                    # store authentication tags
                    for my $tag ( keys $tags->%* ) {
                        $cache->{tag}->{$tag}->{ $tags->{$tag} }->{$auth_id} = undef;
                    }

                    $cb->(
                        bless {
                            api     => $self,
                            auth_id => $auth_id
                        },
                        'Pcore::App::API::Request'
                    );
                }

                return;
            }
        );
    }

    return;
}

sub authorize ( $self, $auth_id, $cb ) {
    my $auth = $self->{_auth_cache}->{auth}->{$auth_id};

    # token is not authenticated
    if ( !$auth ) {
        $cb->(undef);

        return;
    }

    # permissions are cached
    if ( exists $auth->{permissions} ) {
        $cb->( $auth->{permissions} );

        return;
    }

    # get permissions from backend
    else {
        $self->{backend}->authorize(
            $self->app->instance_id,
            $auth->{token_type},
            $auth->{token_id},
            sub ( $status, $permissions, $tags ) {
                if ( !$status ) {
                    $cb->(undef);
                }
                else {
                    # cache permissions
                    $auth->{permissions} = $permissions;

                    $cb->($permissions);
                }

                return;
            }
        );
    }

    return;
}

sub invalidate_cache ( $self, $tags ) {
    my $cache = $self->{_auth_cache};

    for my $tag ( keys $tags->%* ) {
        delete $cache->{auth}->@{ keys $cache->{tag}->{$tag}->{ $tags->{$tag} }->%* };

        delete $cache->{tag}->{$tag}->{ $tags->{$tag} };
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
## |    3 | 27                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 12                   | CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    |
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
