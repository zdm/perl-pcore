package Pcore::App::API::Auth;

use Pcore -class;
use Pcore::Util::Status;

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has backend => ( is => 'ro', isa => ConsumerOf ['Pcore::App::API::Auth::Backend'], init_arg => undef );

sub init ( $self, $cb ) {

    # create API auth backend
    my $auth_uri = P->uri( $self->{app}->{auth} );

    if ( $auth_uri->scheme eq 'sqlite' || $auth_uri->scheme eq 'pgsql' ) {
        my $dbh = P->handle($auth_uri);

        my $class = P->class->load( $dbh->uri->scheme, ns => 'Pcore::App::API::Auth::Backend::Local' );

        $self->{backend} = $class->new( { app => $self->app, is_local => 1, dbh => $dbh } );
    }
    elsif ( $auth_uri->scheme eq 'http' || $auth_uri->scheme eq 'https' || $auth_uri->scheme eq 'ws' || $auth_uri->scheme eq 'wss' ) {
        require Pcore::App::API::Auth::Backend::Cluster;

        $self->{backend} = Pcore::App::API::Auth::Backend::Cluster->new( { app => $self->app, is_local => 0, uri => $auth_uri } );
    }
    else {
        die q[Unknown API auth scheme];
    }

    # init auth backend, create DB schema
    $self->{backend}->init(
        sub ($status) {
            die qq[Error initialising API auth backend: $status] if !$status;

            # register app on backend, get and init message broker
            $self->{backend}->register_app(
                $self->app->name,
                $self->app->desc,
                "@{[$self->app->version]}",
                P->sys->hostname,
                {},    # handles

                sub ( $status, $app_instance_id ) {
                    die qq[Error registering app: $status] if !$status;

                    # approve immediately, if local backend
                    if ( $self->{backend}->is_local ) {
                        $self->{backend}->approve_app(
                            $app_instance_id,
                            sub ( $status, $token ) {
                                die qq[Error approving app: $status] if !$status;

                                $cb->( Pcore::Util::Status->new( { status => 200 } ) );

                                return;
                            }
                        );
                    }
                    else {
                        $cb->( Pcore::Util::Status->new( { status => 200 } ) );
                    }

                    return;
                }
            );

            return;
        }
    );

    return;
}

1;
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
