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

            my ( $app_instance_id, $app_instance_token );

            my $app_instance_file = ( $ENV->{DATA_DIR} // q[] ) . '.app-instance.txt';

            if ( !-f $app_instance_file ) {
                P->file->touch($app_instance_file);
            }
            else {
                my $data = P->file->read_bin($app_instance_file);

                ( $app_instance_id, $app_instance_token ) = split /:/sm, $data->$*;
            }

            my $connect_app_instance = sub ( $app_instance_id, $app_instance_token ) {
                $self->{backend}->connect_app_instance(
                    $app_instance_id,
                    $app_instance_token,
                    sub ($status) {
                        die qq[Error connecting app: $status] if !$status;

                        $cb->( Pcore::Util::Status->new( { status => 200 } ) );

                        return;
                    }
                );

                return;
            };

            my $approve_app_instance = sub ($app_instance_id) {
                $self->{backend}->approve_app_instance(
                    $app_instance_id,
                    sub ( $status, $app_instance_token ) {
                        die qq[Error approving app: $status] if !$status;

                        P->file->write_bin( $app_instance_file, "$app_instance_id:$app_instance_token" );

                        $connect_app_instance->( $app_instance_id, $app_instance_token );

                        return;
                    }
                );

                return;
            };

            if ( !$app_instance_id ) {

                # register app on backend, get and init message broker
                $self->{backend}->register_app_instance(
                    $self->app->name,
                    $self->app->desc,
                    "@{[$self->app->version]}",
                    P->sys->hostname,
                    {},    # handles

                    sub ( $status, $app_instance_id ) {
                        die qq[Error registering app: $status] if !$status;

                        P->file->write_bin( $app_instance_file, "$app_instance_id:" );

                        $approve_app_instance->($app_instance_id);

                        return;
                    }
                );
            }
            elsif ( !$app_instance_token ) {
                $approve_app_instance->($app_instance_id);
            }
            else {
                $connect_app_instance->( $app_instance_id, $app_instance_token );
            }

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
