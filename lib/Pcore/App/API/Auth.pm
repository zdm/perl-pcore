package Pcore::App::API::Auth;

use Pcore -const, -role, -export => { CONST => [qw[$TOKEN_TYPE_USER_PASSWORD $TOKEN_TYPE_APP_INSTANCE_TOKEN $TOKEN_TYPE_USER_TOKEN]] };
use Pcore::Util::Data qw[to_b64_url from_b64];
use Pcore::Util::Digest qw[sha1];
use Pcore::Util::Text qw[encode_utf8];

requires qw[app backend];

has _auth_descriptor_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

const our $TOKEN_TYPE_USER_PASSWORD      => 1;
const our $TOKEN_TYPE_APP_INSTANCE_TOKEN => 2;
const our $TOKEN_TYPE_USER_TOKEN         => 3;

require Pcore::App::API::Auth::Descriptor;

# TODO
# events:
#     - on token authenticate - put token descriptor to cache, if authenticated;
#     - on token remove - remove descriptor from cache, drop all descriptor - related connections;
#     - on token change - remove descriptor from cache
#     - on token disable / enable - set enabled attribute, if disabled - drop all descriptor - related connections;
#     - on token permission change - undef descriptor permissions;

sub authenticate ( $self, $token, $user_name_utf8, $cb ) {
    my ( $token_type, $token_id, $token_id_encoded );

    # token is user password
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
    my $private_token = sha1 $token . $token_id_encoded;

    undef $token;

    # create auth descriptor  key
    my $descriptor_id = "$token_type-$token_id_encoded-$private_token";

    my $descriptor = $self->{_auth_descriptor_cache}->{$descriptor_id};

    if ($descriptor) {

        # descriptor enabled status is defined
        if ( defined $descriptor->{enabled} ) {

            # descriptor is disabled
            if ( !$descriptor->{enabled} ) {
                $cb->(undef);

                return;
            }

            # descriptor is enabled and has permissions
            elsif ( defined $descriptor->{permissions} ) {
                $cb->($descriptor);

                return;
            }
        }
    }

    $self->{backend}->auth_token(
        $self->app->instance_id,
        $token_type,
        $token_id,
        $descriptor ? undef : $private_token,    # validate token
        sub ( $status, $descriptor, $tags ) {
            my $cache = $self->{_auth_descriptor_cache};

            if ( !$status ) {
                delete $cache->{$descriptor_id};

                $cb->(undef);
            }
            else {

                # descriptor is not cached, create new descriptor
                if ( !$cache->{$descriptor_id} ) {
                    $cache->{$descriptor_id} = bless {
                        app        => $self->app,
                        id         => $descriptor_id,
                        token_type => $token_type,
                        token_id   => $token_id,
                      },
                      'Pcore::App::API::Auth::Descriptor';
                }

                $cache->{$descriptor_id}->@{ keys $descriptor->%* } = values $descriptor->%*;

                $descriptor = $cache->{$descriptor_id};

                if ( $descriptor->{enabled} ) {
                    $cb->($descriptor);
                }
                else {
                    $cb->(undef);
                }
            }

            return;
        }
    );

    return;
}

# TODO how to work with cache tags
sub invalidate_cache ( $self, $event, $tags ) {
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
## |    3 | 26                   | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
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
