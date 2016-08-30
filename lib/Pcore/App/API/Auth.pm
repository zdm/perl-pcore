package Pcore::App::API::Auth;

use Pcore -class;

has app => ( is => 'ro', isa => ConsumerOf ['Pcore::App'], required => 1 );

has backend => ( is => 'ro', isa => ConsumerOf ['Pcore::App::API::Auth::Backend'], init_arg => undef );

sub init ( $self, $cb ) {

    # create API auth backend
    my $auth_uri = P->uri( $self->{app}->{auth} );

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

    # init auth backend, create DB schema
    $self->{backend}->init(
        sub ($status) {
            die qq[Error initialising API auth backend: $status] if !$status;

            # TODO register app on backend, get and init message broker

            # TODO upload methods

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
