package Pcore::App::API;

use Pcore -role, -const, -export => { CONST => [qw[$TOKEN_TYPE_USER_PASSWORD $TOKEN_TYPE_APP_INSTANCE_TOKEN $TOKEN_TYPE_USER_TOKEN]] };
use Pcore::App::API::Map;
use Pcore::Util::Status::Keyword qw[status];
use Pcore::Util::Data qw[from_b64];
use Pcore::Util::Digest qw[sha1];
use Pcore::Util::Text qw[encode_utf8];

const our $TOKEN_TYPE_USER_PASSWORD      => 1;
const our $TOKEN_TYPE_APP_INSTANCE_TOKEN => 2;
const our $TOKEN_TYPE_USER_TOKEN         => 3;

require Pcore::App::API::Auth;

requires qw[_build_roles];

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has map => ( is => 'ro', isa => InstanceOf ['Pcore::App::API::Map'], init_arg => undef );
has roles => ( is => 'ro', isa => HashRef, init_arg => undef );    # API roles, provided by this app
has permissions => ( is => 'ro', isa => Maybe [HashRef], init_arg => undef );    # foreign app roles, that this app can use
has backend => ( is => 'ro', isa => ConsumerOf ['Pcore::App::API::Backend'], init_arg => undef );

has _auth_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

around _build_roles => sub ( $orig, $self ) {
    my $roles = $self->$orig;

    die q[App must provide roles] if !keys $roles->%*;

    # validate roles
    for my $role ( keys $roles->%* ) {

        # check, that role has description
        die qq[API role "$role" requires description] if !$roles->{$role};
    }

    return $roles;
};

# TODO
# events:
#     - on token authenticate - put token descriptor to cache, if authenticated;
#     - on token remove - remove descriptor from cache, drop all descriptor - related connections;
#     - on token change - remove descriptor from cache
#     - on token disable / enable - set enabled attribute, if disabled - drop all descriptor - related connections;
#     - on token permission change - undef descriptor permissions;
# NOTE this method can be redefined in app instance
sub _build_permissions ($self) {
    return;
}

# INIT API
sub init ( $self, $cb ) {

    # build roles
    $self->{roles} = $self->_build_roles;

    # build permissions
    $self->{permissions} = $self->_build_permissions;

    # build map
    # use class name as string to avoid conflict with Type::Standard Map subroutine, exported to Pcore::App::API
    $self->{map} = 'Pcore::App::API::Map'->new( { app => $self->app } );

    # init map
    $self->{map}->method;

    # build API auth backend
    my $auth_uri = P->uri( $self->{app}->{auth} );

    print q[Creating API backend ... ];

    if ( $auth_uri->scheme eq 'sqlite' || $auth_uri->scheme eq 'pgsql' ) {
        my $dbh = P->handle($auth_uri);

        my $class = P->class->load( $dbh->uri->scheme, ns => 'Pcore::App::API::Backend::Local' );

        $self->{backend} = $class->new( { app => $self->app, dbh => $dbh } );
    }
    elsif ( $auth_uri->scheme eq 'http' || $auth_uri->scheme eq 'https' || $auth_uri->scheme eq 'ws' || $auth_uri->scheme eq 'wss' ) {
        require Pcore::App::API::Backend::Cluster;

        $self->{backend} = Pcore::App::API::Backend::Cluster->new( { app => $self->app, uri => $auth_uri } );
    }
    else {
        die q[Unknown API auth scheme];
    }

    say 'done';

    print q[Initialising API backend ... ];

    $self->{backend}->init(
        sub ($status) {
            die qq[Error initialising API auth backend: $status] if !$status;

            say 'done';

            my $connect_app_instance = sub {
                print q[Connecting app instance ... ];

                $self->{backend}->connect_app_instance(
                    $self->app->{instance_id},
                    "@{[$self->app->version]}",
                    $self->roles,
                    $self->permissions,
                    sub ($status) {
                        die qq[Error connecting app: $status] if !$status;

                        say 'done';

                        $cb->( status 200 );

                        return;
                    }
                );

                return;
            };

            # get app instance credentials from local config
            $self->app->{instance_id}    = $self->app->cfg->{auth}->{ $self->{backend}->host }->[0];
            $self->app->{instance_token} = $self->app->cfg->{auth}->{ $self->{backend}->host }->[1];

            # sending app instance registration request
            if ( !$self->app->{instance_token} ) {
                print q[Sending app instance registration request ... ];

                # register app on backend, get and init message broker
                $self->{backend}->register_app_instance(
                    $self->app->name,
                    $self->app->desc,
                    $self->permissions,
                    P->sys->hostname,
                    "@{[$self->app->version]}",
                    sub ( $status, $app_instance_id, $app_instance_token ) {
                        die qq[Error registering app: $status] if !$status;

                        say 'done';

                        # store app instance credentials
                        {
                            $self->app->{instance_id}    = $self->app->cfg->{auth}->{ $self->{backend}->host }->[0] = $app_instance_id;
                            $self->app->{instance_token} = $self->app->cfg->{auth}->{ $self->{backend}->host }->[1] = $app_instance_token;

                            $self->app->store_cfg;
                        }

                        # waiting for app instance approve
                        $connect_app_instance->();

                        return;
                    }
                );
            }

            # connecting app instance
            else {
                $connect_app_instance->();
            }

            return;
        }
    );

    return;
}

# AUTH
sub authenticate ( $self, $user_name_utf8, $token, $cb ) {
    my ( $token_type, $token_id, $token_id_encoded );

    # token is user_password
    if ($user_name_utf8) {
        $token_id_encoded = eval {
            encode_utf8 $token;
            encode_utf8 $user_name_utf8;
        };

        # error decoding token
        if ($@) {
            $cb->( status [ 400, 'Error decoding user token' ], undef );

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
            $cb->( status [ 400, 'Error decoding user token' ], undef );

            return;
        }

        # token is invalid
        if ( $token_type != $TOKEN_TYPE_APP_INSTANCE_TOKEN && $token_type != $TOKEN_TYPE_USER_TOKEN ) {
            $cb->( status [ 400, 'Invalid token type' ], undef );

            return;
        }

        \$token_id_encoded = \$token_id;
    }

    # create private token
    my $private_token = sha1 $token . $token_id_encoded;

    # create auth id
    my $auth_id = "$token_type-$token_id_encoded-$private_token";

    my $auth = $self->{_auth_cache}->{$auth_id};

    if ($auth) {

        # auth enabled status is defined
        if ( defined $auth->{enabled} ) {

            # auth is disabled
            if ( !$auth->{enabled} ) {
                $cb->( status [ 400, 'Token is disabled' ], undef );

                return;
            }

            # auth is enabled and has permissions
            elsif ( defined $auth->{permissions} ) {
                $cb->($auth);

                return;
            }
        }
    }

    # authenticate on backend
    $self->{backend}->auth_token(
        $self->{app}->{instance_id},
        $token_type,
        $token_id,
        $auth ? undef : $private_token,    # validate token, if auth is new
        sub ( $status, $auth_attrs, $tags ) {
            my $cache = $self->{_auth_cache};

            if ( !$status ) {
                delete $cache->{$auth_id};

                $cb->( $status, undef );

                return;
            }

            $auth = $cache->{$auth_id};

            # auth is not cached, create new auth
            if ( !$auth ) {
                $auth = $cache->{$auth_id} = bless $auth_attrs, 'Pcore::App::API::Auth';

                $auth->{app}        = $self->{app};
                $auth->{id}         = $auth_id;
                $auth->{token_type} = $token_type;
                $auth->{token_id}   = $token_id;
            }
            else {
                $auth->{enabled}     = $auth_attrs->{enabled};
                $auth->{permissions} = $auth_attrs->{permissions};
            }

            if ( $auth->{enabled} ) {
                $cb->( status 200, $auth );
            }
            else {
                $cb->( status [ 400, 'Token is disabled' ], undef );
            }

            return;
        }
    );

    return;
}

# TODO how to work with cache tags
# sub invalidate_cache ( $self, $event, $tags ) {
#     my $cache = $self->{_auth_cache};
#
#     for my $tag ( keys $tags->%* ) {
#         delete $cache->{auth}->@{ keys $cache->{tag}->{$tag}->{ $tags->{$tag} }->%* };
#
#         delete $cache->{tag}->{$tag}->{ $tags->{$tag} };
#     }
#
#     return;
# }

# APP
sub get_app ( $self, $app_id, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->{backend}->get_app(
        $app_id,
        sub ( $status, $app ) {
            $cb->( $status, $app ) if $cb;

            $blocking_cv->( $status, $app ) if $blocking_cv;

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

sub set_app_enabled ( $self, $app_id, $enabled, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->{backend}->set_app_enabled(
        $app_id, $enabled,
        sub ($status) {

            # invalidate app cache on success
            if ($status) {
                $self->_invalidate_app_cache($app_id);
            }

            $cb->($status) if $cb;

            $blocking_cv->($status) if $blocking_cv;

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

sub delete_app ( $self, $app_id, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->{backend}->delete_app(
        $app_id,
        sub ( $status ) {

            # invalidate app cache on success
            if ($status) {
                $self->_invalidate_app_cache($app_id);
            }

            $cb->($status) if $cb;

            $blocking_cv->($status) if $blocking_cv;

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

# APP INSTANCE
sub get_app_instance_by_id ( $self, $app_instance_id, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    if ( my $app_instance = $self->{app_instance_cache}->{$app_instance_id} ) {
        $cb->( status 200, $app_instance ) if $cb;

        $blocking_cv->( status 200, $app_instance ) if $blocking_cv;
    }
    else {
        $self->{backend}->get_app_instance_by_id(
            $app_instance_id,
            sub ( $status, $user ) {
                if ($status) {
                    $self->{app_instance_cache}->{$app_instance_id} = $app_instance;
                }

                $cb->( $status, $app_instance ) if $cb;

                $blocking_cv->( $status, $app_instance ) if $blocking_cv;

                return;
            }
        );
    }

    return $blocking_cv ? $blocking_cv->recv : ();
}

sub set_app_instance_enabled ( $self, $app_instance_id, $enabled, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->{backend}->set_app_instance_enabled(
        $app_instance_id,
        $enabled,
        sub ($status) {

            # invalidate app instance cache on success
            if ($status) {
                $self->_invalidate_app_instance_cache($app_instance_id);
            }

            $cb->($status) if $cb;

            $blocking_cv->($status) if $blocking_cv;

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

sub delete_app_instance ( $self, $app_instance_id, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->{backend}->delete_app_instance(
        $app_instance_id,
        sub ( $status ) {

            # invalidate app instance cache on success
            if ($status) {
                $self->_invalidate_app_instance_cache($app_instance_id);
            }

            $cb->($status) if $cb;

            $blocking_cv->($status) if $blocking_cv;

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

# APP ROLE
sub set_app_role_enabled ( $self, $role_id, $enabled, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->{backend}->set_role_enabled(
        $role_id, $enabled,
        sub ($status) {

            # invalidate role cache on success
            if ($status) {
                $self->_invalidate_role_cache($role_id);
            }

            $cb->($status) if $cb;

            $blocking_cv->($status) if $blocking_cv;

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

# USER
sub get_user ( $self, $user_id, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->{backend}->get_user(
        $user_id,
        sub ( $status, $user ) {
            $cb->( $status, $user ) if $cb;

            $blocking_cv->( $status, $user ) if $blocking_cv;

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

sub create_user ( $self, $user_name, $password, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->{backend}->create_user(
        $user_name,
        $password,
        sub ( $status, $user_id ) {
            $cb->( $status, $user_id ) if $cb;

            $blocking_cv->( $status, $user_id ) if $blocking_cv;

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

sub set_user_password ( $self, $user_id, $user_password_utf8, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    encode_utf8 $user_password_utf8;

    $self->{backend}->set_user_password(
        $user_id,
        $user_password_utf8,
        sub ($status) {

            # invalidate user cache on success
            if ($status) {

                # $self->on_user_password_change($user_id);
            }

            $cb->($status) if $cb;

            $blocking_cv->($status) if $blocking_cv;

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

sub set_user_enabled ( $self, $user_id, $enabled, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->{backend}->set_user_enabled(
        $user_id, $enabled,
        sub ($status) {

            # invalidate user cache on success
            if ($status) {
                $self->_invalidate_user_cache($user_id);
            }

            $cb->($status) if $cb;

            $blocking_cv->($status) if $blocking_cv;

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

sub add_user_permissions ( $self, $user_id, $permissions, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->{backend}->add_user_permissions(
        $user_id,
        $permissions,
        sub ($status) {

            # invalidate user cache on success
            if ($status) {

                # $self->_invalidate_user_cache($user_id);
            }

            $cb->($status) if $cb;

            $blocking_cv->($status) if $blocking_cv;

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

# USER TOKEN
sub get_user_token_by_id ( $self, $user_token_id, $cb ) {
    $self->{backend}->get_user_token_by_id(
        $user_token_id,
        sub ( $status, $user_token ) {
            $cb->( $status, $user_token ) if $cb;

            return;
        }
    );

    return;
}

sub create_user_token ( $self, $user_id, $permissions, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->{backend}->create_user_token(
        $user_id,
        $permissions,
        sub ( $status, $token ) {
            $cb->( $status, $token ) if $cb;

            $blocking_cv->( $status, $token ) if $blocking_cv;

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

sub delete_user_token ( $self, $token_id, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->{backend}->delete_user_token(
        $token_id,
        sub ( $status, $token ) {

            # invalidate user token cache on success
            if ($status) {
                $self->_invalidate_user_token_cache($token_id);
            }

            $cb->($status) if $cb;

            $blocking_cv->($status) if $blocking_cv;

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

1;
## -----SOURCE FILTER LOG BEGIN-----
##
## PerlCritic profile "pcore-script" policy violations:
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
## | Sev. | Lines                | Policy                                                                                                         |
## |======+======================+================================================================================================================|
## |    3 | 172, 400, 507        | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
## +------+----------------------+----------------------------------------------------------------------------------------------------------------+
##
## -----SOURCE FILTER LOG END-----
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
