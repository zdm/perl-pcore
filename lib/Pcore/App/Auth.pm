package Pcore::App::Auth;

use Pcore -role, -const, -export;
use Pcore::Util::Scalar qw[is_plain_arrayref];
use Pcore::Util::Data qw[from_b64 from_b64_url];
use Pcore::Util::Digest qw[sha3_512];
use Pcore::Util::Text qw[encode_utf8];
use Pcore::Util::UUID qw[uuid_from_bin];
use Pcore::App::Auth::Descriptor;

our $EXPORT = { CONST => [qw[$TOKEN_TYPE $TOKEN_TYPE_USER_PASSWORD $TOKEN_TYPE_USER_TOKEN $TOKEN_TYPE_USER_SESSION]] };

has app => ( required => 1 );    # ConsumerOf ['Pcore::App']

has _auth_cb_queue => ( init_arg => undef );    # HashRef
has _auth_cache    => ( init_arg => undef );    # HashRef

const our $TOKEN_TYPE_USER_PASSWORD => 1;
const our $TOKEN_TYPE_USER_TOKEN    => 3;
const our $TOKEN_TYPE_USER_SESSION  => 4;

const our $TOKEN_TYPE => {
    $TOKEN_TYPE_USER_PASSWORD => undef,
    $TOKEN_TYPE_USER_TOKEN    => undef,
    $TOKEN_TYPE_USER_SESSION  => undef,
};

sub new ( $self, $app ) {
    state $scheme_class = {
        sqlite => 'Pcore::App::Auth::Backend::Local::sqlite',
        pgsql  => 'Pcore::App::Auth::Backend::Local::pgsql',
        ws     => 'Pcore::App::Auth::Backend::Remote',
        wss    => 'Pcore::App::Auth::Backend::Remote',
    };

    if ( defined $app->{app_cfg}->{auth}->{backend} ) {
        my $uri = P->uri( $app->{app_cfg}->{auth}->{backend} );

        if ( my $class = $scheme_class->{ $uri->{scheme} } ) {
            return P->class->load($class)->new( { app => $app } );
        }
        else {
            die 'Unknown API scheme';
        }
    }
    else {
        return P->class->load('Pcore::App::Auth::Backend::NoAuth')->new( { app => $app } );
    }
}

# setup events listeners
around init => sub ( $orig, $self ) {

    # setup events listeners
    P->bind_events(
        'app.api.auth',
        sub ($ev) {
            $self->{_auth_cache}->%* = ();

            return;
        }
    );

    return $self->$orig;
};

# AUTHENTICATE
# parse token, create private token, forward to authenticate_private
sub authenticate ( $self, $token ) {

    # no auth token provided
    return bless { app => $self->{app} }, 'Pcore::App::Auth::Descriptor' if !defined $token;

    my ( $token_type, $token_id, $private_token_hash );

    # authenticate user password
    if ( is_plain_arrayref $token) {

        # generate private token hash
        $private_token_hash = eval { sha3_512 encode_utf8( $token->[1] ) . encode_utf8 $token->[0] };

        # error decoding token
        return bless { app => $self->{app} }, 'Pcore::App::Auth::Descriptor' if $@;

        $token_type = $TOKEN_TYPE_USER_PASSWORD;

        \$token_id = \$token->[0];
    }

    # authenticate token
    else {

        # decode token
        eval {
            my $token_bin = from_b64_url $token;

            # unpack token type
            $token_type = unpack 'C', $token_bin;

            # unpack token id
            $token_id = uuid_from_bin( substr $token_bin, 1, 16 )->str;

            $private_token_hash = sha3_512 $token;
        };

        # error decoding token
        return bless { app => $self->{app} }, 'Pcore::App::Auth::Descriptor' if $@;

        # invalid token type
        return bless { app => $self->{app} }, 'Pcore::App::Auth::Descriptor' if !exists $TOKEN_TYPE->{$token_type};
    }

    return $self->authenticate_private( [ $token_type, $token_id, $private_token_hash ] );
}

sub authenticate_private ( $self, $private_token ) {

    # try to find token in cache
    my $auth = $self->{_auth_cache}->{ $private_token->[2] };

    # token was cached
    return $auth if defined $auth;

    my $cv = P->cv;

    my $cache = $self->{_auth_cb_queue};

    push $cache->{ $private_token->[2] }->@*, $cv;

    return $cv->recv if $cache->{ $private_token->[2] }->@* > 1;

    # authenticate on backend
    my $res = $self->do_authenticate_private($private_token);

    # authentication error
    if ( !$res ) {

        # delete private token from cache
        delete $self->{_auth_cache}->{ $private_token->[2] };

        # return new unauthenticated auth object
        $auth = bless {
            app              => $self->{app},
            is_authenticated => 0,
            private_token    => $private_token,
          },
          'Pcore::App::Auth::Descriptor';
    }

    # authenticated
    else {

        # create auth
        $auth = bless $res->{data}, 'Pcore::App::Auth::Descriptor';

        $auth->{app}              = $self->{app};
        $auth->{is_authenticated} = 1;
        $auth->{private_token}    = $private_token;

        # store in cache
        $self->{_auth_cache}->{ $private_token->[2] } = $auth;
    }

    # call callbacks
    $cache = delete $cache->{ $private_token->[2] };

    while ( my $cb = shift $cache->@* ) {
        $cb->($auth);
    }

    return $cv->recv;
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 94                   | ErrorHandling::RequireCheckingReturnValueOfEval - Return value of eval not tested                              |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::Auth

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 AUTHENTICATION METHODS

=head2 authentocate( $user_name, $token, $cb )

Performs user authentication and returns instance of Pcore::App::Auth::Drscriptor.

C<$user_name> can be undefined.

=head2 authentocate_private( $private_token, $cb )

Performs private token authentication and returns instance of Pcore::App::Auth::Drscriptor.

Private token structure is [ %token_type, $token_id, $token_hash ].

=head1 USER METHODS

=head2 create_user ( $user_name, $password, $enabled, $permissions, $cb )

Creates user and returns user id.

C<$permissions> - ArrayRef[ 'role1', 'role2', ... ]

=head2 get_users ( $cb )

Returns all users.

=head1 SEE ALSO

=cut