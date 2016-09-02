package Pcore::App::API::Auth;

use Pcore -class;
use Pcore::Util::Status::Keyword qw[status];

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has backend => ( is => 'ro', isa => ConsumerOf ['Pcore::App::API::Auth::Backend'], init_arg => undef );

has user_cache             => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has username_id_cache      => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );
has user_id_password_cache => ( is => 'ro', isa => HashRef, default => sub { {} }, init_arg => undef );

# INIT AUTH BACKEND
sub init ( $self, $cb ) {

    # create API auth backend
    my $auth_uri = P->uri( $self->{app}->{auth} );

    print q[Creating API backend ... ];

    if ( $auth_uri->scheme eq 'sqlite' || $auth_uri->scheme eq 'pgsql' ) {
        my $dbh = P->handle($auth_uri);

        my $class = P->class->load( $dbh->uri->scheme, ns => 'Pcore::App::API::Auth::Backend::Local' );

        $self->{backend} = $class->new( { app => $self->app, dbh => $dbh } );
    }
    elsif ( $auth_uri->scheme eq 'http' || $auth_uri->scheme eq 'https' || $auth_uri->scheme eq 'ws' || $auth_uri->scheme eq 'wss' ) {
        require Pcore::App::API::Auth::Backend::Cluster;

        $self->{backend} = Pcore::App::API::Auth::Backend::Cluster->new( { app => $self->app, uri => $auth_uri } );
    }
    else {
        die q[Unknown API auth scheme];
    }

    say 'done';

    print q[Initialising API backend ... ];

    # init auth backend, create DB schema
    $self->backend->init(
        sub ($status) {
            die qq[Error initialising API auth backend: $status] if !$status;

            say 'done';

            # get app instance credentials from local config
            my $app_instance_id = $self->app->cfg->{auth}->{ $self->backend->host }->[0];

            my $app_instance_token = $self->app->cfg->{auth}->{ $self->backend->host }->[1];

            my $connect_app_instance = sub ( $app_instance_id, $app_instance_token ) {
                print q[Connecting app instance ... ];

                $self->backend->connect_app_instance(
                    $app_instance_id,
                    $app_instance_token,
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

            my $approve_app_instance = sub ($app_instance_id) {
                print q[Waiting for app instance approval ... ];

                $self->backend->approve_app_instance(
                    $app_instance_id,
                    sub ( $status, $app_instance_token ) {
                        die qq[Error approving app: $status] if !$status;

                        say 'done';

                        # store app instance token
                        {
                            $self->app->cfg->{auth}->{ $self->backend->host }->[1] = $app_instance_token;

                            $self->app->store_cfg;
                        }

                        # connecting app instance
                        $connect_app_instance->( $app_instance_id, $app_instance_token );

                        return;
                    }
                );

                return;
            };

            # sending app instance registration request
            if ( !$app_instance_id ) {
                print q[Sending app instance registration request ... ];

                # register app on backend, get and init message broker
                $self->backend->register_app_instance(
                    $self->app->name,
                    $self->app->desc,
                    "@{[$self->app->version]}",
                    P->sys->hostname,
                    {},    # handles

                    sub ( $status, $app_instance_id ) {
                        die qq[Error registering app: $status] if !$status;

                        say 'done';

                        # store app instance id
                        {
                            $self->app->cfg->{auth}->{ $self->backend->host }->[0] = $app_instance_id;

                            $self->app->cfg->{auth}->{ $self->backend->host }->[1] = undef;

                            $self->app->store_cfg;
                        }

                        # waiting for app instance approve
                        $approve_app_instance->($app_instance_id);

                        return;
                    }
                );
            }

            # waiting for app instance approve
            elsif ( !$app_instance_token ) {
                $approve_app_instance->($app_instance_id);
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
sub auth_user_password ( $self, $username, $password, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->get_user_by_name(
        $username,
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
                    $self->backend->auth_user_password(
                        $username,
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

# ROLE
sub create_role ( $self, $name, $desc, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->backend->create_role(
        $name, $desc,
        sub ( $status, $role_id ) {
            $cb->( $status, $role_id ) if $cb;

            $blocking_cv->( $status, $role_id ) if $blocking_cv;

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

# USER
# NOTE this method should be called, when user was changed
sub invalidate_user_cache ( $self, $user_id ) {
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
        $self->backend->get_user_by_id(
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

sub get_user_by_name ( $self, $username, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    # username -> id is cached
    if ( my $user_id = $self->{username_id_cache}->{$username} ) {
        $self->get_user_by_id(
            $user_id,
            sub ( $status, $user ) {
                $cb->( $status, $user ) if $cb;

                $blocking_cv->( $status, $user ) if $blocking_cv;
            }
        );
    }
    else {
        $self->backend->get_user_by_name(
            $username,
            sub ( $status, $user ) {
                if ($status) {
                    $self->{user_cache}->{ $user->{id} } = $user;

                    $self->{username_id_cache}->{$username} = $user->{id};
                }

                $cb->( $status, $user ) if $cb;

                $blocking_cv->( $status, $user ) if $blocking_cv;

                return;
            }
        );
    }

    return $blocking_cv ? $blocking_cv->recv : ();
}

sub create_user ( $self, $username, $password, $cb = undef ) {
    my $blocking_cv = defined wantarray ? AE::cv : undef;

    $self->backend->create_user(
        $username,
        $password,
        sub ( $status, $user_id ) {
            $cb->( $status, $user_id ) if $cb;

            $blocking_cv->( $status, $user_id ) if $blocking_cv;

            return;
        }
    );

    return $blocking_cv ? $blocking_cv->recv : ();
}

1;
__END__
=pod

=encoding utf8

=head1 NAME

Pcore::App::API::Auth - application API authentication frontend

=head1 SYNOPSIS

=head1 DESCRIPTION

=head1 ATTRIBUTES

=head1 METHODS

=head1 SEE ALSO

=cut
