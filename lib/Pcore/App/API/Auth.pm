package Pcore::App::API::Auth;

use Pcore -const, -role, -export => { CONST => [qw[$TOKEN_TYPE_USER_PASSWORD $TOKEN_TYPE_APP_INSTANCE_TOKEN $TOKEN_TYPE_USER_TOKEN]] };
use Pcore::Util::Data qw[to_b64_url from_b64];
use Pcore::Util::Digest qw[sha1];
use Pcore::Util::Text qw[encode_utf8];

requires qw[
];

has _auth_cache => (
    is      => 'lazy',
    isa     => HashRef,
    default => sub {
        {   token => {},
            tag   => {},
        };
    },
    init_arg => undef
);

const our $TOKEN_TYPE_USER_PASSWORD      => 1;
const our $TOKEN_TYPE_APP_INSTANCE_TOKEN => 2;
const our $TOKEN_TYPE_USER_TOKEN         => 3;

sub authenticate ( $self, $token, $user_name_utf8, $cb ) {
    my ( $token_type, $token_id, $token_id_utf8 );

    # detect auth type
    if ($user_name_utf8) {
        $token_id = eval {
            encode_utf8 $token;
            encode_utf8 $user_name_utf8;
        };

        # error decoding token
        if ($@) {
            $cb->(undef);

            return;
        }

        $token_type = $TOKEN_TYPE_USER_PASSWORD;

        \$token_id_utf8 = \$user_name_utf8;
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

        \$token_id_utf8 = \$token_id;
    }

    $token = sha1 $token . $token_id;

    my $auth_id = "$token_type-$token_id-$token";

    my $cache = $self->{_auth_cache};

    # cached
    if ( my $valid_token = $cache->{token}->{$auth_id}->{valid_token} ) {
        if ( $token eq $valid_token ) {
            $cb->(1);
        }
        else {
            $cb->(0);
        }
    }

    # not cached, unknown authentication
    else {
        $self->{backend}->authenticate(
            $token_type,
            $token_id_utf8,
            $token,
            sub ( $status, $tags ) {

                # not authenticated
                if ( !$status ) {
                    $cb->(0);
                }

                # authenticated
                else {
                    # store authenticated token
                    $cache->{token}->{$auth_id}->{token_type}  = $token_type;
                    $cache->{token}->{$auth_id}->{token_id}    = $token_id;
                    $cache->{token}->{$auth_id}->{valid_token} = $token;

                    # store authentication tags
                    for my $tag ( keys $tags->%* ) {
                        $cache->{tag}->{$tag}->{ $tags->{$tag} }->{$auth_id} = undef;
                    }

                    $cb->(1);
                }

                return;
            }
        );
    }

    return;
}

sub authorize ( $self, $auth_id, $roles, $cb ) {
    if (1) {

    }

    return;
}

sub invalidate_cache ( $self, $tags ) {
    my $cache = $self->{_auth_cache};

    for my $tag ( keys $tags->%* ) {
        delete $cache->{token}->@{ keys $cache->{tag}->{$tag}->{ $tags->{$tag} }->%* };

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
## |------+----------------------+----------------------------------------------------------------------------------------------------------------|
## |    1 | 11                   | CodeLayout::RequireTrailingCommas - List declaration without trailing comma                                    |
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
