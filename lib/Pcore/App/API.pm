package Pcore::App::API;

use Pcore -role;
use Pcore::App::API::Map;
use Pcore::App::API::Request;
use Pcore::Util::Status::Keyword qw[status];

requires qw[_build_roles];

has roles       => ( is => 'lazy', isa => HashRef, init_arg => undef );    # API roles, provided by this app
has permissions => ( is => 'lazy', isa => HashRef, init_arg => undef );    # foreign roles, that this app can use

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has map => ( is => 'lazy', isa => InstanceOf ['Pcore::App::API::Map'], init_arg => undef );

has backend => ( is => 'ro', isa => ConsumerOf ['Pcore::App::API::Backend'], init_arg => undef );

has app_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

has app_instance_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

has role_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

has user_cache             => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has user_name_id_cache     => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has user_id_password_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

has user_token_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

around _build_roles => sub ( $orig, $self ) {
    my $roles = $self->$orig;

    # validate roles
    for my $role ( keys $roles->%* ) {

        # check, that role has description
        die qq[API role "$role" requires description] if !$roles->{$role};
    }

    return $roles;
};

sub _build_permissions ($self) {
    return {};
}

sub _build_map ($self) {

    # use class name as string to avoid conflict with Type::Standard Map subroutine, exported to Pcore::App::API
    return 'Pcore::App::API::Map'->new( { app => $self->app } );
}

# INIT AUTH BACKEND
sub init ( $self, $cb ) {

    # create API auth backend
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

            # get app instance credentials from local config
            my ( $app_instance_id, $app_instance_token );

            ( $app_instance_id, $app_instance_token ) = $self->app->cfg->{auth}->{ $self->{backend}->host }->@* if $self->app->cfg->{auth}->{ $self->{backend}->host };

            my $connect_app_instance = sub ( $app_instance_id, $app_instance_token ) {
                print q[Connecting app instance ... ];

                $self->{backend}->connect_app_instance(
                    $app_instance_id,
                    "@{[$self->app->version]}",
                    $self->roles,
                    $self->permissions,
                    sub ($status) {
                        die qq[Error connecting app: $status] if !$status;

                        say 'done';

                        # set app instance token
                        $self->app->{token} = $app_instance_token;

                        $cb->( status 200 );

                        return;
                    }
                );

                return;
            };

            # sending app instance registration request
            if ( !$app_instance_token ) {
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
                            $self->app->cfg->{auth}->{ $self->{backend}->host }->[0] = $app_instance_id;

                            $self->app->cfg->{auth}->{ $self->{backend}->host }->[1] = $app_instance_token;

                            $self->app->store_cfg;
                        }

                        # waiting for app instance approve
                        $connect_app_instance->( $app_instance_id, $app_instance_token );

                        return;
                    }
                );
            }

            # connecting app instance
            else {
                $connect_app_instance->( $app_instance_id, $app_instance_token );
            }

            return;
        }
    );

    return;
}

# AUTH
sub auth_user_password ( $self, $user_name, $password, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->get_user_by_name(
        $user_name,
        sub ( $status, $user ) {
            if ( !$status ) {
                $cb->( $status, undef ) if $cb;

                $blocking_cv->( $status, undef ) if $blocking_cv;
            }
            else {
                if ( my $user_password = $self->{user_id_password_cache}->{ $user->{id} } ) {
                    if ( $user_password eq $password ) {
                        $cb->( status 200, $user ) if $cb;

                        $blocking_cv->( status 200, $user ) if $blocking_cv;
                    }
                    else {
                        $cb->( status [ 400, 'Invalid password' ], undef ) if $cb;

                        $blocking_cv->( status [ 400, 'Invalid password' ], undef ) if $blocking_cv;
                    }
                }
                else {
                    $self->{backend}->auth_user_password(
                        $user_name,
                        $password,
                        sub ( $status ) {
                            if ($status) {
                                $self->{user_id_password_cache}->{ $user->{id} } = $password;
                            }
                            else {
                                undef $user;
                            }

                            $cb->( $status, $user ) if $cb;

                            $blocking_cv->( $status, $user ) if $blocking_cv;

                            return;
                        }
                    );
                }
            }

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

# TODO auth_user_token, auth_app_token

# APP
sub _invalidate_app_cache ( $self, $app_id ) {
    delete $self->{app_cache}->{$app_id};

    return;
}

sub get_app_by_id ( $self, $app_id, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    if ( my $app = $self->{app_cache}->{$app_id} ) {
        $cb->( status 200, $app ) if $cb;

        $blocking_cv->( status 200, $app ) if $blocking_cv;
    }
    else {
        $self->{backend}->get_app_by_id(
            $app_id,
            sub ( $status, $user ) {
                if ($status) {
                    $self->{app_cache}->{$app_id} = $app;
                }

                $cb->( $status, $app ) if $cb;

                $blocking_cv->( $status, $app ) if $blocking_cv;

                return;
            }
        );
    }

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
sub _invalidate_app_instance_cache ( $self, $app_instance_id ) {
    delete $self->{app_instance_cache}->{$app_instance_id};

    return;
}

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
sub _invalidate_role_cache ( $self, $role_id ) {
    delete $self->{role_cache}->{$role_id};

    return;
}

sub get_role_by_id ( $self, $role_id, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    if ( my $role = $self->{role_cache}->{$role_id} ) {
        $cb->( status 200, $role ) if $cb;

        $blocking_cv->( status 200, $role ) if $blocking_cv;
    }
    else {
        $self->{backend}->get_role_by_id(
            $role_id,
            sub ( $status, $role ) {
                if ($status) {
                    $self->{role_cache}->{$role_id} = $role;
                }

                $cb->( $status, $role ) if $cb;

                $blocking_cv->( $status, $role ) if $blocking_cv;

                return;
            }
        );
    }

    return $blocking_cv ? $blocking_cv->recv : ();
}

sub set_role_enabled ( $self, $role_id, $enabled, $cb = undef ) {
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
sub _invalidate_user_cache ( $self, $user_id ) {
    delete $self->{user_cache}->{$user_id};

    delete $self->{user_id_password_cache}->{$user_id};

    return;
}

sub get_user_by_id ( $self, $user_id, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    if ( my $user = $self->{user_cache}->{$user_id} ) {
        $cb->( status 200, $user ) if $cb;

        $blocking_cv->( status 200, $user ) if $blocking_cv;
    }
    else {
        $self->{backend}->get_user_by_id(
            $user_id,
            sub ( $status, $user ) {
                if ($status) {
                    $self->{user_cache}->{$user_id} = $user;
                }

                $cb->( $status, $user ) if $cb;

                $blocking_cv->( $status, $user ) if $blocking_cv;

                return;
            }
        );
    }

    return $blocking_cv ? $blocking_cv->recv : ();
}

sub get_user_by_name ( $self, $user_name, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    # user_name -> user_id is cached
    if ( my $user_id = $self->{user_name_id_cache}->{$user_name} ) {
        $self->get_user_by_id(
            $user_id,
            sub ( $status, $user ) {
                $cb->( $status, $user ) if $cb;

                $blocking_cv->( $status, $user ) if $blocking_cv;
            }
        );
    }
    else {
        $self->{backend}->get_user_by_name(
            $user_name,
            sub ( $status, $user ) {
                if ($status) {
                    $self->{user_cache}->{ $user->{id} } = $user;

                    $self->{user_name_id_cache}->{$user_name} = $user->{id};
                }

                $cb->( $status, $user ) if $cb;

                $blocking_cv->( $status, $user ) if $blocking_cv;

                return;
            }
        );
    }

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

sub set_user_password ( $self, $user_id, $password, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->{backend}->set_user_password(
        $user_id,
        $password,
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

sub set_user_role ( $self, $user_id, $role_id, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->{backend}->set_user_role(
        $user_id, $role_id,
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

# USER TOKEN
sub _invalidate_user_token_cache ( $self, $token_id ) {
    delete $self->{user_token_cache}->{$token_id};

    return;
}

sub create_user_token ( $self, $user_id, $role_id, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->{backend}->create_user_token(
        $user_id, $role_id,
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
## |    3 | 335, 578, 608        | Subroutines::ProhibitManyArgs - Too many arguments                                                             |
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
